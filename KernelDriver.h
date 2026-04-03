//
//  KernelDriver.h
//  A13Exploit - REAL Kernel Exploit for iOS 26.3
//

#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface KernelDriver : NSObject <WKScriptMessageHandler>

// ==================== Inicialização ====================
- (instancetype)initWithWebView:(WKWebView *)webView;

// ==================== Operações de Kernel ====================
- (uint64_t)kread64:(uint64_t)address;
- (uint32_t)kread32:(uint64_t)address;
- (void)kwrite64:(uint64_t)address value:(uint64_t)value;
- (void)kwrite32:(uint64_t)address value:(uint32_t)value;

// ==================== Estágios do Exploit ====================
- (uint64_t)leakKernelSlide;
- (BOOL)disableKTRR;
- (BOOL)escalateToRoot;
- (void)runFullExploitWithCallback:(void(^)(BOOL success, NSString *message))callback;

// ⭐ MÉTODO FALTANTE - Adicionado agora
- (void)executeExploitWithCallback:(void(^)(BOOL success, NSString *message))callback;

// ==================== Utilitários ====================
- (uint64_t)getCurrentUID;
- (void)executeCommand:(NSString *)command withCallback:(void(^)(NSString *output))callback;

@end

NS_ASSUME_NONNULL_END
