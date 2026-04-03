//
//  KernelDriver.h
//  JailbreakApp
//

#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface KernelDriver : NSObject <WKScriptMessageHandler>

- (instancetype)initWithWebView:(WKWebView *)webView;
- (void)executeCommand:(NSString *)command withCallback:(void(^)(NSString *result))callback;
- (void)executeExploitWithCallback:(void(^)(BOOL success, NSString *message))callback;
- (uint64_t)getCurrentUID;

@end

NS_ASSUME_NONNULL_END
