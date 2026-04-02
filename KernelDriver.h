#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

@interface KernelBridge : NSObject <WKScriptMessageHandlerWithReply>

// Propriedades para comunicação
@property (nonatomic, weak) WKWebView *webView;

// Definições de Memória (A13 / iOS 26.4)
#define PAGE_SIZE_A13 0x4000
#define PAGE_MASK_A13 ~(PAGE_SIZE_A13 - 1)
#define KERNEL_BASE_STATIC 0xFFFFFFF007004000

// Métodos Principais
- (uint64_t)kread64:(uint64_t)addr;
- (void)kwrite64:(uint64_t)addr value:(uint64_t)val;
- (uint64_t)getKernelSlide;
- (void)launchSshdFinal;

@end
