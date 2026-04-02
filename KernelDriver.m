#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#include <spawn.h>
#include <sys/wait.h>
#include <sys/stat.h>

@interface KernelBridge : NSObject <WKScriptMessageHandler>
@property (nonatomic, strong) WKWebView *webView;
@end

@implementation KernelBridge

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    if ([message.body[@"op"] isEqualToString:@"scan_uid"]) {
        [self runDirectSshd];
    }
}

- (void)log:(NSString *)text {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *js = [NSString stringWithFormat:@"log('%@')", text];
        [self.webView evaluateJavaScript:js completionHandler:nil];
    });
}

- (void)runDirectSshd {
    [self log:@"⚡ Verificando privilégios..."];

    // 1. CHECAGEM DE SEGURANÇA (Evita crash se o exploit falhar)
    if (getuid() != 0) {
        [self log:@"❌ Erro: UID não é 0. O exploit falhou antes de chegar aqui."];
        return;
    }

    [self log:@"👑 Root detectado! Preparando SSHD..."];

    // 2. LOCALIZAR BINÁRIO NO BUNDLE
    // O Feather coloca o app em /var/containers/Bundle/Application/...
    NSString *sshdPath = [[NSBundle mainBundle] pathForResource:@"sshd" ofType:nil];
    
    if (!sshdPath) {
        [self log:@"❌ Erro: Arquivo 'sshd' não encontrado no Bundle do App."];
        return;
    }

    // 3. GARANTIR PERMISSÃO DE EXECUÇÃO (CHMOD)
    // Importante: Sem isso o posix_spawn dá Erro 13 e o iOS pode dar crash no app pai
    if (chmod([sshdPath UTF8String], 0755) != 0) {
        [self log:@"⚠️ Falha no chmod. O binário pode estar em partição Read-Only."];
    }

    // 4. SPAWN COM BYPASS DE SANDBOX (O pulo do gato)
    pid_t pid;
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    
    // Flag 0x4000 (POSIX_SPAWN_FOR_SANDBOX) é o que permite ao root 
    // rodar um processo sem as amarras do app original.
    short flags = POSIX_SPAWN_SETPGROUP | 0x4000;
    posix_spawnattr_setflags(&attr, flags);

    // Argumentos mínimos para o SSHD não reclamar de falta de pastas
    char *const args[] = {
        (char *)[sshdPath UTF8String],
        "-p", "2222",
        "-D",                      // Foreground
        "-o", "PermitRootLogin=yes",
        "-o", "StrictModes=no",     // ESSENCIAL: Ignora permissões de pasta no iOS
        "-o", "PasswordAuthentication=yes",
        NULL
    };

    extern char **environ;
    
    // Tenta o spawn
    int spawn_err = posix_spawn(&pid, [sshdPath UTF8String], NULL, &attr, args, environ);

    if (spawn_err == 0) {
        [self log:[NSString stringWithFormat:@"✅ SSHD ONLINE! PID: %d porta 2222", pid]];
    } else {
        // Se der erro 13: O binário sshd não está assinado corretamente (ldid).
        // Se der erro 1: O Sandbox ainda está bloqueando (o Root não foi "total").
        [self log:[NSString stringWithFormat:@"❌ Erro Spawn: %d (%s)", spawn_err, strerror(spawn_err)]];
    }

    posix_spawnattr_destroy(&attr);
}

@end
