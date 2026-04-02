#import "ViewController.h"

@implementation ViewController {
    KernelBridge *_strongBridge; // Referência REALMENTE forte
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // 1. Criar o motor ANTES de tudo
    _strongBridge = [[KernelBridge alloc] init];
    
    // 2. Configurar a injeção
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    
    // O nome DEVE ser "kernel" (minúsculo)
    [config.userContentController addScriptMessageHandlerWithReply:_strongBridge 
                                                      contentWorld:WKContentWorld.pageWorld 
                                                              name:@"kernel"];

    // 3. Criar a WebView com essa config
    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:config];
    [self.view addSubview:self.webView];
    
    // 4. Carregar o HTML
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"index" withExtension:@"html"];
    [self.webView loadFileURL:url allowingReadAccessToURL:url.URLByDeletingLastPathComponent];
}
@end
