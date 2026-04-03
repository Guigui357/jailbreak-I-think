#import "ViewController.h"
#import "KernelDriver.h"

@interface ViewController ()
// Retenção FORTE para a ponte não cair
@property (strong, nonatomic) KernelDriver *driver; 
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // 1. Instância do Driver
    self.driver = [[KernelDriver alloc] init];
    
    // 2. Configuração da WebView
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    
    // Injeção manual via UserScript para garantir visibilidade no JS
    WKUserScript *s = [[WKUserScript alloc] initWithSource:@"window.kernel = window.webkit.messageHandlers.kernel;" 
                                              injectionTime:WKUserScriptInjectionTimeAtDocumentStart 
                                           forMainFrameOnly:YES];
    [config.userContentController addUserScript:s];

    // No iOS 26.4, omitir o contentWorld no addScript ajuda na compatibilidade do A13
    [config.userContentController addScriptMessageHandlerWithReply:self.driver 
                                                              name:@"kernel"];

    // 3. Permissões de Sandbox
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
