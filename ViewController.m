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
    
    // Injeção manual para garantir que o objeto não seja undefined
    NSString *jsInject = @"window.webkit.messageHandlers.kernel = window.webkit.messageHandlers.kernel || {};";
    WKUserScript *script = [[WKUserScript alloc] initWithSource:jsInject 
                                                  injectionTime:WKUserScriptInjectionTimeAtDocumentStart 
                                               forMainFrameOnly:YES];
    [config.userContentController addUserScript:script];

    // Injeção da Ponte Real
    [config.userContentController addScriptMessageHandlerWithReply:self.driver 
                                                      contentWorld:[WKContentWorld pageWorld] 
                                                              name:@"kernel"];
    
    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:config];
    [self.view addSubview:self.webView];
    
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"index" withExtension:@"html"];
    [self.webView loadFileURL:url allowingReadAccessToURL:url.URLByDeletingLastPathComponent];
}

@end
