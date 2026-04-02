#import "ViewController.h"
#import "KernelDriver.h"

@interface ViewController ()
@property (strong, nonatomic) KernelDriver *driver;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    _driver = [[KernelDriver alloc] init];
    
    WKUserContentController *userContentController = [[WKUserContentController alloc] init];
    
    // O SEGREDO: addScriptMessageHandlerWithReply + pageWorld
    [userContentController addScriptMessageHandlerWithReply:self.driver 
                                               contentWorld:[WKContentWorld pageWorld] 
                                                       name:@"kernel"];
    
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.userContentController = userContentController;
    
    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:config];
    [self.view addSubview:self.webView];
    
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"index" withExtension:@"html"];
    [self.webView loadFileURL:url allowingReadAccessToURL:url.URLByDeletingLastPathComponent];
}
@end
