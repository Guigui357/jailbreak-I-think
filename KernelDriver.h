#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

@interface KernelDriver : NSObject <WKScriptMessageHandlerWithReply>

- (void)userContentController:(WKUserContentController *)userContentController 
      didReceiveScriptMessage:(WKScriptMessage *)message 
                 replyHandler:(void (^)(id reply, NSString * errorMessage))replyHandler;

@end
