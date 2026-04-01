#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#include <stdint.h>
#include <mach/mach.h>

// --- DECLARAÇÃO DA INTERFACE (Resolve o erro "cannot find interface") ---
@interface KernelBridge : NSObject <WKScriptMessageHandler>
// Declaramos explicitamente a propriedade para o compilador encontrar
@property (nonatomic, unsafe_unretained) WKWebView *webView;
@end

// --- IMPLEMENTAÇÃO ---
@implementation KernelBridge

- (void)userContentController:(WKUserContentController *)userContentController 
      didReceiveScriptMessage:(WKScriptMessage *)message {
    
    NSDictionary *data = message.body;
    
    // Verificamos se a webView está conectada antes de usar
    if (!self.webView) {
        // Se cair aqui, a bridge não foi vinculada no ViewController.m
        return;
    }

    if ([data[@"op"] isEqualToString:@"scan_uid"]) {
        // 1. Tentar vazar o endereço (KASLR Leak)
        mach_port_t host_port = mach_host_self();
        uint64_t leaked_ptr = (uint64_t)host_port; 

        // Envia o feedback para o HTML
        NSString *status = [NSString stringWithFormat:@"log('🔍 Port Leak: 0x%llX. Bridge C ativa.')", leaked_ptr];
        [self.webView evaluateJavaScript:status completionHandler:nil];

        // 2. Alerta de Sandbox
        [self.webView evaluateJavaScript:@"log('⚠️ Bloqueio de Sandbox: Verifique os Entitlements no Feather.')" completionHandler:nil];
    }
}
@end
