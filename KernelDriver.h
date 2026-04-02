#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import <mach/mach.h>

#define PAGE_SIZE_A13 0x4000
#define KERNEL_BASE_STATIC 0xFFFFFFF007004000

@interface KernelBridge : NSObject <WKScriptMessageHandlerWithReply>
@property (nonatomic, assign) mach_port_t g_host_priv;
@property (nonatomic, weak) WKWebView *webView;

- (uint64_t)kread64:(uint64_t)addr;
- (void)kwrite64:(uint64_t)addr value:(uint64_t)val;
- (uint64_t)getKernelSlide;
- (uint64_t)findProcByName:(NSString *)name;
- (void)escalatePrivileges;
@end
