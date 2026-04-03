//
//  KernelDriver.h
//  JailbreakApp
//

#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface KernelDriver : NSObject <WKScriptMessageHandler>

- (instancetype)initWithWebView:(WKWebView *)webView;
- (void)injectJavaScript;
- (uint64_t)getCurrentUID;

@end

NS_ASSUME_NONNULL_END
