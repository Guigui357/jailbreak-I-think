#import "ViewController.h"
#import "KernelDriver.h"

@interface ViewController ()
// Removida a linha da webView daqui, pois já existe no ViewController.h
@property (nonatomic, strong) KernelBridge *bridge; 
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // 1. Inicializa o motor do Kernel
    self.bridge = [[KernelBridge alloc] init];
    
    // 2. Configura a WebView (usando a propriedade do .h)
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    [config.userContentController addScriptMessageHandlerWithReply:self.bridge 
                                                      contentWorld:WKContentWorld.pageWorld 
                                                              name:@"kernel"];
    
    // Inicializa a instância
    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:config];
    self.webView.backgroundColor = [UIColor blackColor];
    [self.view addSubview:self.webView];
    
    // 3. Carrega o HTML
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"index" withExtension:@"html"];
    if (url) {
        [self.webView loadFileURL:url allowingReadAccessToURL:url];
    } else {
        NSLog(@"[!] Erro: index.html não encontrado no Bundle.");
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.webView.frame = self.view.bounds;
}

@end
