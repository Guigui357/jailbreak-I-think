#import "ViewController.h"
#import "KernelDriver.h"

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    // 1. Instância do Driver
    self.kernelBridge = [[KernelBridge alloc] init];

    // 2. Configuração da WebView
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    
    // IMPORTANTE: O nome aqui DEVE ser "kernel" (minúsculo) para bater com o JS
    [config.userContentController addScriptMessageHandlerWithReply:self.kernelBridge 
                                                      contentWorld:WKContentWorld.pageWorld 
                                                              name:@"kernel"];

    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:config];
    
    // 3. Permite acesso a arquivos locais (index.html)
    [self.webView.configuration.preferences setValue:@YES forKey:@"allowFileAccessFromFileURLs"];
    
    [self.view addSubview:self.webView];

    // 4. Carrega o HTML
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"index" withExtension:@"html"];
    if (url) {
        [self.webView loadFileURL:url allowingReadAccessToURL:url.URLByDeletingLastPathComponent];
    }
}
@end
