#import "ViewController.h"
#import "KernelDriver.h"

@interface ViewController ()
@property (strong, nonatomic) KernelDriver *driver; 
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.driver = [[KernelDriver alloc] init];
    
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    
    // 1. INJEÇÃO MANUAL: Força o objeto existir no JS antes do HTML carregar
    NSString *js = @"window.A13_LAB = window.webkit.messageHandlers.A13_LAB;";
    WKUserScript *s = [[WKUserScript alloc] initWithSource:js 
                                              injectionTime:WKUserScriptInjectionTimeAtDocumentStart 
                                           forMainFrameOnly:YES];
    [config.userContentController addUserScript:s];

    // 2. REGISTRO: Nome único para evitar filtros do sistema
    [config.userContentController addScriptMessageHandler:self.driver name:@"A13_LAB"];

    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:config];
    self.driver.webView = self.webView; // Importante para o Callback
    [self.view addSubview:self.webView];
    
    // 3. CARREGAMENTO: O iOS 26.4 bloqueia handlers em file:// 
    // Carregar como String remove a restrição de 'Origin' do WebKit
    NSString *path = [[NSBundle mainBundle] pathForResource:@"index" ofType:@"html"];
    NSString *html = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    [self.webView loadHTMLString:html baseURL:[[NSBundle mainBundle] bundleURL]];
}

@end
