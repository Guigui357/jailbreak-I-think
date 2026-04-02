#import "ViewController.h"
#import "KernelDriver.h"

@interface ViewController ()
@property (strong, nonatomic) KernelDriver *driver;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    _driver = [[KernelDriver alloc] init];
    
    WKUserContentController *userCC = [[WKUserContentController alloc] init];
    
    // CRITICAL: addScriptMessageHandlerWithReply habilita o método no JS
    [userCC addScriptMessageHandlerWithReply:self.driver 
                                contentWorld:[WKContentWorld pageWorld] 
                                        name:@"kernel"];
    
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.userContentController = userCC;
    
    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:config];
    [self.view addSubview:self.webView];
    
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"index" withExtension:@"html"];
    [self.webView loadFileURL:url allowingReadAccessToURL:url.URLByDeletingLastPathComponent];
}
@end
