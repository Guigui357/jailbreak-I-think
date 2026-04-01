#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#include <stdint.h>
#include <mach/mach.h>
#include <dlfcn.h>

// Definimos o tipo da função manualmente para o compilador não reclamar
typedef kern_return_t (*IOMainPortFunc)(mach_port_t, mach_port_t *);

@interface KernelBridge : NSObject <WKScriptMessageHandler>
@property (nonatomic, unsafe_unretained) WKWebView *webView;
@end

@implementation KernelBridge

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    NSDictionary *data = message.body;
    
    if ([data[@"op"] isEqualToString:@"scan_uid"]) {
        [self.webView evaluateJavaScript:@"log('🧪 Tentando Dynamic Leak (IOMainPort)...')" completionHandler:nil];

        // 1. Carregar a biblioteca IOKit dinamicamente (Bypass de SDK check)
        void *iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
        if (!iokit) {
            [self.webView evaluateJavaScript:@"log('❌ Erro: Não foi possível carregar IOKit.')" completionHandler:nil];
            return;
        }

        // 2. Localizar a função IOMainPort (Substituta da IOMasterPort)
        IOMainPortFunc get_main_port = (IOMainPortFunc)dlsym(iokit, "IOMainPort");
        if (!get_main_port) {
            // Tenta o nome antigo se o novo falhar (retrocompatibilidade)
            get_main_port = (IOMainPortFunc)dlsym(iokit, "IOMasterPort");
        }

        if (get_main_port) {
            mach_port_t mainPort;
            kern_return_t kr = get_main_port(MACH_PORT_NULL, &mainPort);
            
            if (kr == KERN_SUCCESS) {
                NSString *ok = [NSString stringWithFormat:@"log('🔓 IOMainPort Obtida: 0x%x. Sandbox perfurada!')", mainPort];
                [self.webView evaluateJavaScript:ok completionHandler:nil];
                
                // Se chegamos aqui, o App tem permissão de hardware.
                // Agora o scan do UID 501 pode ser tentado via porta de host.
            } else {
                [self.webView evaluateJavaScript:@"log('⚠️ IOKit recusou a porta (Erro de Sandbox).')" completionHandler:nil];
            }
        } else {
            [self.webView evaluateJavaScript:@"log('❌ Erro: Símbolo IOMainPort não encontrado.')" completionHandler:nil];
        }
        dlclose(iokit);
    }
}
@end
