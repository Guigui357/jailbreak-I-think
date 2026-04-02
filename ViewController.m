#import "ViewController.h"
#import "KernelDriver.h"

@interface ViewController ()
// RETENÇÃO FORTE: Impede que a ponte morra após o carregamento
@property (strong, nonatomic) KernelDriver *driver; 
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.driver = [[KernelDriver alloc] init];
    
    WKUserContentController *userCC = [[WKUserContentController alloc] init];
    
    // USAR EXATAMENTE ESTE MÉTODO (iOS 14+)
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
