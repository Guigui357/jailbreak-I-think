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
    
    // Injeção manual para garantir visibilidade do objeto no JS
    WKUserScript *s = [[WKUserScript alloc] initWithSource:@"window.kernel = window.webkit.messageHandlers.kernel;" 
                                              injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES];
    [config.userContentController addUserScript:s];

    // USAR defaultWorld para arquivos locais/strings no iOS 26.4
    [config.userContentController addScriptMessageHandlerWithReply:self.driver 
                                                      contentWorld:[WKContentWorld defaultWorld] name:@"kernel"];

    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:config];
    [self.view addSubview:self.webView];
    
    // CARREGAR COMO STRING: Burlar restrições de 'file://' do A13
    NSString *path = [[NSBundle mainBundle] pathForResource:@"index" ofType:@"html"];
    NSString *html = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    [self.webView loadHTMLString:html baseURL:[[NSBundle mainBundle] bundleURL]];
}
@end
