#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface KernelDriver : NSObject <WKScriptMessageHandlerWithReply>

// Declaração dos métodos de Exploit
- (uint64_t)kread64:(uint64_t)addr;
- (uint64_t)get_pte_for_address:(uint64_t)vaddr;
- (uint64_t)get_my_ucred_ptr;
- (void)ppl_write_race:(uint64_t)vaddr value:(uint64_t)val;
- (uint64_t)getKernelSlide;

// Assinatura correta do protocolo WKWebView
- (void)userContentController:(WKUserContentController *)userContentController 
      didReceiveScriptMessage:(WKScriptMessage *)message 
                 replyHandler:(void (^)(id _Nullable reply, NSString * _Nullable errorMessage))replyHandler;

@end

NS_ASSUME_NONNULL_END
