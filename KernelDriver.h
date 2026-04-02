#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

// CERTIFIQUE-SE DE QUE O NOME DO PROTOCOLO ESTÁ EXATAMENTE ASSIM:
@interface KernelBridge : NSObject <WKScriptMessageHandlerWithReply>

// Assinatura do método que o WebKit procura para habilitar a função no JS
- (void)userContentController:(WKUserContentController *)userContentController 
      didReceiveScriptMessage:(WKScriptMessage *)message 
                 replyHandler:(void (^)(id _Nullable reply, NSString * _Nullable errorMessage))replyHandler;

@end
