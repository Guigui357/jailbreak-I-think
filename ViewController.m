#import "ViewController.h"
#import "KernelDriver.h"

@implementation ViewController {
    KernelDriver *_bridge;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    _bridge = [[KernelBridge alloc] init];
    
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    // Injeção com suporte a Reply (iOS 14+)
    [config.userContentController addScriptMessageHandlerWithReply:_bridge 
                                                      contentWorld:WKContentWorld.pageWorld 
                                                              name:@"kernel"];

    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:config];
    [self.view addSubview:self.webView];
    
    // Carrega o painel de controle do Exploit
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"index" withExtension:@"html"];
    [self.webView loadFileURL:url allowingReadAccessToURL:url.URLByDeletingLastPathComponent];
}
@end
