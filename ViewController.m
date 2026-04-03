#import "ViewController.h"
#import "KernelDriver.h"
#import <WebKit/WebKit.h>

@interface ViewController ()
@property (strong, nonatomic) KernelDriver *driver; 
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // 1. Instância do Driver (Retenção forte)
    self.driver = [[KernelDriver alloc] init];
    
    // 2. Configuração da WebView
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    
    // SINTAXE CORRETA: addScriptMessageHandlerWithReply REQUER o contentWorld
    // Usamos defaultClientWorld para máxima compatibilidade no iOS 26.4
    [config.userContentController addScriptMessageHandlerWithReply:self.driver 
                                                      contentWorld:[WKContentWorld defaultClientWorld] 
                                                              name:@"kernel"];

    // 3. Permissões de Sandbox e JIT para o A13
    [config.preferences setValue:@YES forKey:@"allowFileAccessFromFileURLs"];
    [config setValue:@YES forKey:@"allowUniversalAccessFromFileURLs"];

    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:config];
    [self.view addSubview:self.webView];
    
    // 4. Carregar o HTML como String para evitar restrições de 'file://'
    NSString *path = [[NSBundle mainBundle] pathForResource:@"index" ofType:@"html"];
    if (path) {
        NSString *html = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
        [self.webView loadHTMLString:html baseURL:[[NSBundle mainBundle] bundleURL]];
    }
}

@end
