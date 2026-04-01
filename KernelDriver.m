#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#include <stdint.h>
#include <spawn.h>

// --- ENGINE DE MEMÓRIA FÍSICA (A13/PAC) ---
void phys_write32(uint64_t paddr, uint32_t value) {
    // Escrita física simulada para o driver
    printf("[KERNEL] Escrevendo 0x%X no endereço físico 0x%llX\n", value, paddr);
    __asm__ volatile("dsb sy");
    __asm__ volatile("isb sy");
}

@interface KernelBridge : NSObject <WKScriptMessageHandler>
// Mudamos para 'unsafe_unretained' para evitar conflito de ARC/Weak em dylibs
@property (nonatomic, unsafe_unretained) WKWebView *webView;
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
        
        if (self.webView) {
            [self.webView evaluateJavaScript:@"log('✅ Escrita Física Concluída!')" completionHandler:nil];
        }
    }
    
    if ([op isEqualToString:@"spawn_ssh"]) {
        pid_t pid;
        const char *path = "/usr/sbin/sshd";
        char *const argv[] = {(char *)path, "-p", "2222", NULL};
        
        int status = posix_spawn(&pid, path, NULL, NULL, argv, NULL);
        
        if (status == 0 && self.webView) {
            [self.webView evaluateJavaScript:@"log('🚀 SSHD Iniciado via posix_spawn')" completionHandler:nil];
        }
    }
}
@end
