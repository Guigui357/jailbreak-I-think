#import "ViewController.h"
#import "KernelDriver.h"

@implementation ViewController {
    KernelDriver *_driver;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _driver = [[KernelDriver alloc] init];
    
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    // CRITICAL: Deve usar addScriptMessageHandlerWithReply
    [config.userContentController addScriptMessageHandlerWithReply:_driver 
                                                      contentWorld:WKContentWorld.pageWorld 
                                                              name:@"kernel"];

    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:config];
    [self.view addSubview:self.webView];
    
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"index" withExtension:@"html"];
    [self.webView loadFileURL:url allowingReadAccessToURL:url.URLByDeletingLastPathComponent];
}
@end
