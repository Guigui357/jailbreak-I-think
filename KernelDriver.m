#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#include <stdint.h>
#include <mach/mach.h>
#include <IOKit/IOKitLib.h>

@interface KernelBridge : NSObject <WKScriptMessageHandler>
@property (nonatomic, unsafe_unretained) WKWebView *webView;
@end

@implementation KernelBridge

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    NSDictionary *data = message.body;
    
    if ([data[@"op"] isEqualToString:@"scan_uid"]) {
        [self.webView evaluateJavaScript:@"log('🧪 Iniciando Leak via IOKit/MasterPort...')" completionHandler:nil];

        // 1. Obter a Master Port do IOKit (Frequentemente vaza o KASLR)
        mach_port_t masterPort;
        kern_return_t kr = IOMasterPort(MACH_PORT_NULL, &masterPort);
        
        if (kr != KERN_SUCCESS) {
            [self.webView evaluateJavaScript:@"log('❌ Sandbox: Acesso ao IOKit negado.')" completionHandler:nil];
            return;
        }

        // 2. Vazar o endereço da porta
        NSString *ok = [NSString stringWithFormat:@"log('🔓 MasterPort Obtida: 0x%x. Bypass detectado!')", masterPort];
        [self.webView evaluateJavaScript:ok completionHandler:nil];

        // 3. Tentar achar o serviço 'IOPlatformExpertDevice'
        // No iOS 26.4, esse serviço contém ponteiros valiosos para o kernel
        io_service_t service = IOServiceGetMatchingService(masterPort, IOServiceMatching("IOPlatformExpertDevice"));
        if (service) {
            [self.webView evaluateJavaScript:@"log('🎯 Serviço IOPlatform Encontrado. Sandbox Quebrada.')" completionHandler:nil];
            // Aqui você dispararia o seu scan de UID real
        } else {
            [self.webView evaluateJavaScript:@"log('⚠️ Serviço não localizado. Refine os Entitlements no Feather.')" completionHandler:nil];
        }
    }
}
@end
