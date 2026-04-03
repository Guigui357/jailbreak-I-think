#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

// Adicione exatamente esta linha:
@interface KernelDriver : NSObject <WKScriptMessageHandlerWithReply>

@property (nonatomic, weak) WKWebView *webView;

@end
