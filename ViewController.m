#import "ViewController.h"

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    // 1. Instancia o motor PRIMEIRO na propriedade STRONG
    self.kernelBridge = [[KernelBridge alloc] init];

    // 2. Configura a ponte ANTES de criar a WebView
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    
    // O nome "kernel" deve ser exatamente igual ao do JS
    [config.userContentController addScriptMessageHandlerWithReply:self.kernelBridge 
                                                      contentWorld:WKContentWorld.pageWorld 
                                                              name:@"kernel"];

    // 3. Cria a WebView com a config que já contém o handler
    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:config];
    [self.view addSubview:self.webView];

    // 4. Carrega o HTML
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"index" withExtension:@"html"];
    if (url) {
        [self.webView loadFileURL:url allowingReadAccessToURL:url.URLByDeletingLastPathComponent];
    }
}

@end
