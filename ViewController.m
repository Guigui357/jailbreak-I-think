#import "ViewController.h"

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    // 1. Instancia o motor PRIMEIRO (Garante que a propriedade strong segure o objeto)
    self.kernelBridge = [[KernelBridge alloc] init];

    // 2. Configura a WebView
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    
    // Injeta o handler. O nome "kernel" deve ser EXATAMENTE igual ao do JS.
    [config.userContentController addScriptMessageHandlerWithReply:self.kernelBridge 
                                                      contentWorld:WKContentWorld.pageWorld 
                                                              name:@"kernel"];

    // 3. Inicializa a WebView com a config injetada
    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:config];
    [self.view addSubview:self.webView];

    // 4. Carrega o HTML do Bundle
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"index" withExtension:@"html"];
    if (url) {
        [self.webView loadFileURL:url allowingReadAccessToURL:url.URLByDeletingLastPathComponent];
    }
}
@end
