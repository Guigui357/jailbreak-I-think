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
    
    // Injeção EXTREMA: Força o objeto existir no JS antes de qualquer coisa
    WKUserScript *s = [[WKUserScript alloc] initWithSource:@"window.kernel = window.webkit.messageHandlers.kernel;" 
                                              injectionTime:WKUserScriptInjectionTimeAtDocumentStart 
                                           forMainFrameOnly:YES];
    [config.userContentController addUserScript:s];

    [config.userContentController addScriptMessageHandlerWithReply:self.driver 
                                                      contentWorld:[WKContentWorld pageWorld] 
                                                              name:@"kernel"];

    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:config];
    [self.view addSubview:self.webView];
    
    // Carrega o HTML do Bundle como string para evitar restrições de 'file://'
    NSString *path = [[NSBundle mainBundle] pathForResource:@"index" ofType:@"html"];
    NSString *html = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    [self.webView loadHTMLString:html baseURL:[[NSBundle mainBundle] bundleURL]];
}

@end
