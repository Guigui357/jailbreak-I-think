#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import "KernelDriver.h" // Importante para o ViewController conhecer o Driver

@interface ViewController : UIViewController

// A WKWebView que exibirá o console hacker (index.html)
@property (nonatomic, strong) WKWebView *webView;

// A instância do motor que processará o kread64 e o SSHD
@property (nonatomic, strong) KernelDriver *kernelBridge;

@end
