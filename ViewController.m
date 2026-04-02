#import "ViewController.h"
#import "KernelDriver.h" // Importa o seu motor de exploit
#import <WebKit/WebKit.h>

@interface ViewController ()
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) KernelBridge *bridge; // Instância do driver
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // 1. Inicializa o motor do Kernel
    self.bridge = [[KernelBridge alloc] init];
    
    // 2. Configura a WebView e a ponte de comunicação
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    // Registra o bridge para responder às mensagens do JS chamadas "kernel"
    [config.userContentController addScriptMessageHandlerWithReply:self.bridge 
                                                      contentWorld:WKContentWorld.pageWorld 
                                                              name:@"kernel"];
    
    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:config];
    self.webView.backgroundColor = [UIColor blackColor];
    [self.view addSubview:self.webView];
    
    // 3. Carrega o HTML (index.html) que criamos
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"index" withExtension:@"html"];
    if (url) {
        [self.webView loadFileURL:url allowingReadAccessToURL:url];
    }
}

// Garante que a WebView ocupe a tela toda no iPhone 11
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.webView.frame = self.view.bounds;
}

@end
