#import "ViewController.h"
#import "KernelDriver.h"

@interface ViewController ()
@property (strong, nonatomic) KernelDriver *driver;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // 1. Inicializa o Driver
    self.driver = [[KernelDriver alloc] init];
    
    // 2. Configura a comunicação WebKit
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    
    // Injeção de UserScript para facilitar o acesso no JS
    NSString *js = @"window.A13_LAB = window.webkit.messageHandlers.A13_LAB;";
    WKUserScript *script = [[WKUserScript alloc] initWithSource:js 
                                                injectionTime:WKUserScriptInjectionTimeAtDocumentStart 
                                             forMainFrameOnly:YES];
    [config.userContentController addUserScript:script];

    // REGISTRO CRÍTICO: Usa 'addScriptMessageHandlerWithReply' para iOS 14+
    if (@available(iOS 14.0, *)) {
        [config.userContentController addScriptMessageHandlerWithReply:self.driver 
                                                        contentWorld:[WKContentWorld pageWorld] 
                                                                name:@"A13_LAB"];
    }

    // 3. Inicializa a WebView
    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:config];
    self.driver.webView = self.webView; // Referência para callbacks se necessário
    [self.view addSubview:self.webView];
    
    // 4. Carrega o HTML (index.html deve estar no Bundle)
    NSString *path = [[NSBundle mainBundle] pathForResource:@"index" ofType:@"html"];
    if (path) {
        NSString *html = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
        [self.webView loadHTMLString:html baseURL:[[NSBundle mainBundle] bundleURL]];
    }
}

@end
