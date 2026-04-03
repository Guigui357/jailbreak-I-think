#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

@interface KernelDriver : NSObject <WKScriptMessageHandler>

// Referência à WebView para enviar a resposta de volta
@property (nonatomic, weak) WKWebView *webView;

- (uint64_t)kread64:(uint64_t)addr;
- (uint64_t)getKernelSlide;
- (void)ppl_write_race:(uint64_t)vaddr value:(uint64_t)val;

@end
