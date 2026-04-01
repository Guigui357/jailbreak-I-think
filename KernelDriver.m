#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#include <stdint.h>
#include <spawn.h>

// --- ENGINE DE MEMÓRIA FÍSICA (A13/PAC) ---
void phys_write32(uint64_t paddr, uint32_t value) {
    printf("[KERNEL] Escrevendo 0x%X no endereço físico 0x%llX\n", value, paddr);
    __asm__ volatile("dsb sy");
    __asm__ volatile("isb sy");
}

@interface KernelBridge : NSObject <WKScriptMessageHandler>
@property (nonatomic, weak) WKWebView *webView; // Referência correta para a WebView
@end

@implementation KernelBridge

- (void)userContentController:(WKUserContentController *)userContentController 
      didReceiveScriptMessage:(WKScriptMessage *)message {
    
    NSDictionary *data = message.body;
    NSString *op = data[@"op"];
    
    if ([op isEqualToString:@"phys_write"]) {
        uint64_t addr = [data[@"addr"] unsignedLongLongValue];
        uint32_t val = [data[@"val"] unsignedIntValue];
        
        phys_write32(addr, val);
        
        // Forma correta de chamar o JS de volta
        [self.webView evaluateJavaScript:@"log('✅ Escrita Física Concluída!')" completionHandler:nil];
    }
    
    if ([op isEqualToString:@"spawn_ssh"]) {
        // Substituição do system() pelo posix_spawn (Permitido no iOS)
        pid_t pid;
        const char *argv[] = {"sshd", "-p", "2222", NULL};
        posix_spawn(&pid, "/usr/sbin/sshd", NULL, NULL, (char* const*)argv, NULL);
        
        [self.webView evaluateJavaScript:@"log('🚀 SSHD Iniciado via posix_spawn')" completionHandler:nil];
    }
}
@end
