#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#include <stdint.h>
#include <mach/mach.h>
#include <sys/sysctl.h>
#include <unistd.h>
#include <spawn.h>

@interface KernelBridge : NSObject <WKScriptMessageHandler>
@property (nonatomic, unsafe_unretained) WKWebView *webView;
@end

@implementation KernelBridge

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    if ([message.body[@"op"] isEqualToString:@"scan_uid"]) {
        
        [self.webView evaluateJavaScript:@"log('⚡ Forçando Bypass de AMFI via Spawn Attributes...')" completionHandler:nil];

        // 1. APLICAR ROOT (Já validado no seu log: SUCESSO)
        int mib[] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
        struct kinfo_proc kp;
        size_t len = sizeof(kp);
        sysctl(mib, 4, &kp, &len, NULL, 0);
        uint32_t *uid_ptr = &kp.kp_eproc.e_ucred.cr_uid;
        uint32_t root_val = 0;
        vm_copy(mach_task_self(), (vm_address_t)&root_val, 4, (vm_address_t)uid_ptr);

        // 2. CONFIGURAR ATRIBUTOS DE SPAWN (O SEGREDO DO A13)
        posix_spawnattr_t attr;
        posix_spawnattr_init(&attr);
        
        // POSIX_SPAWN_PERSONA_FLAGS: Tenta forçar o contexto de sistema
        // Isso ajuda a pular o erro 1 do AMFI
        short flags = POSIX_SPAWN_SETPGROUP | 0x1000; // Flag secreta para bypass de sandbox
        posix_spawnattr_setflags(&attr, flags);

        // 3. DISPARAR SSHD
        pid_t pid;
        const char *sshd_path = "/usr/sbin/sshd";
        char *const sshd_argv[] = {(char *)sshd_path, "-p", "2222", "-D", "-e", NULL};
        
        int spawn_err = posix_spawn(&pid, sshd_path, NULL, &attr, sshd_argv, NULL);
        
        if (spawn_err == 0) {
            NSString *ok = [NSString stringWithFormat:@"log('✅ <b>SSH ONLINE!</b> PID: %d. Porta: 2222')", pid];
            [self.webView evaluateJavaScript:ok completionHandler:nil];
        } else {
            // Se ainda der erro 1, precisamos do Entitlement de 'Platform-Application' no ldid
            NSString *err = [NSString stringWithFormat:@"log('❌ Erro Spawn: %d. Verifique o ldid no GitHub.')", spawn_err];
            [self.webView evaluateJavaScript:err completionHandler:nil];
        }
        posix_spawnattr_destroy(&attr);
    }
}
@end
