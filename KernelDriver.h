#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

@interface KernelDriver : NSObject <WKScriptMessageHandlerWithReply>

@property (nonatomic, weak) WKWebView *webView; // Resolve o erro no ViewController

- (uint64_t)kread64:(uint64_t)addr;
- (void)ppl_write_race:(uint64_t)vaddr value:(uint64_t)val;
- (uint64_t)getActualKernelSlide;
- (uint64_t)leak_kobject_addr:(mach_port_t)port;

@end
