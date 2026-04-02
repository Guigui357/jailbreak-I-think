#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#include <spawn.h>
#include <sys/stat.h>
#include <sys/wait.h>

@interface KernelBridge : NSObject <WKScriptMessageHandler>
@property (nonatomic, strong) WKWebView *webView;
@end

@implementation KernelBridge

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    if ([message.body[@"op"] isEqualToString:@"scan_uid"]) {
        [self launchSshdAsSystem];
    }
}

- (void)log:(NSString *)text {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.webView evaluateJavaScript:[NSString stringWithFormat:@"log('%@')", text] completionHandler:nil];
    });
}

- (void)launchSshdAsSystem {
    [self log:@"⚡ Iniciando Escalonamento via CoreTrust Bypass..."];

    // 1. LOCALIZAR BINÁRIO
    NSString *sshdPath = [[NSBundle mainBundle] pathForResource:@"sshd" ofType:nil];
    if (!sshdPath) {
        [self log:@"❌ Erro: Binário sshd não encontrado."];
        return;
    }

    // 2. DAR PERMISSÃO (Fundamental para A13)
    chmod([sshdPath UTF8String], 0775);

    // 3. SPAWN COM ATRIBUTOS DE SISTEMA (Bypass PPL/Sandbox)
    pid_t pid;
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);

    // No iOS 26.4, o segredo é a flag 0x4000 + Persona 0x1000
    // Isso tenta forçar o processo a nascer fora do sandbox do App
    short flags = POSIX_SPAWN_SETPGROUP | 0x1000 | 0x4000;
    posix_spawnattr_setflags(&attr, flags);

    char *const args[] = {
        (char *)[sshdPath UTF8String],
        "-p", "2222",
        "-D",
        "-o", "PermitRootLogin=yes",
        "-o", "StrictModes=no",
        "-o", "PasswordAuthentication=yes",
        NULL
    };

    extern char **environ;

    // 4. EXECUÇÃO
    [self log:@"🛰️ Invocando spawn de plataforma..."];
    int status = posix_spawn(&pid, [sshdPath UTF8String], NULL, &attr, args, environ);

    if (status == 0) {
        [self log:[NSString stringWithFormat:@"✅ <b>SSHD ONLINE!</b> PID: %d", pid]];
        [self log:@"💡 Conecte via: ssh root@localhost -p 2222"];
    } else {
        [self log:[NSString stringWithFormat:@"❌ Falha Total: Erro %d (%s)", status, strerror(status)]];
        [self log:@"⚠️ O Kernel bloqueou a execução por falta de Assinatura de Plataforma."];
    }

    posix_spawnattr_destroy(&attr);
}

@end
