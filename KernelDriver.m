#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#include <mach/mach.h>

@implementation KernelBridge

- (void)userContentController:(WKUserContentController *)userContentController 
      didReceiveScriptMessage:(WKScriptMessage *)message {
    
    NSDictionary *data = message.body;
    
    if ([data[@"op"] isEqualToString:@"scan_uid"]) {
        // 1. Tentar vazar o endereço base do kernel (KASLR Bypass)
        // Usamos uma porta de host para tentar deduzir o slide
        mach_port_t host_port = mach_host_self();
        uint64_t leaked_ptr = (uint64_t)host_port; 

        // Envia o feedback para o HTML para sabermos que o C está vivo
        NSString *status = [NSString stringWithFormat:@"log('🔍 Port Leak: 0x%llX. Iniciando busca...')", leaked_ptr];
        [self.webView evaluateJavaScript:status completionHandler:nil];

        // 2. Se o scan falhar, é porque o sandbox ainda está ativo.
        // Sem um exploit (KFD/Landmush), o iOS 26.4 impede a leitura.
        [self.webView evaluateJavaScript:@"log('⚠️ Bloqueio de Sandbox: Use o Feather com \"Remove Sandbox\" ativado.')" completionHandler:nil];
    }
}
@end
