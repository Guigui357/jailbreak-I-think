#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

@interface KernelDriver : NSObject <WKScriptMessageHandlerWithReply>

- (uint64_t)kread64:(uint64_t)addr;
- (uint64_t)getKernelSlide;
- (uint64_t)get_pte_for_address:(uint64_t)vaddr;
- (uint64_t)get_my_ucred_ptr;
- (void)ppl_write_race:(uint64_t)vaddr value:(uint64_t)val;

- (void)userContentController:(WKUserContentController *)userContentController 
      didReceiveScriptMessage:(WKScriptMessage *)message 
                 replyHandler:(void (^)(id reply, NSString *errorMessage))replyHandler;

@end
