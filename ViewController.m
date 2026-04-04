#import "ViewController.h"
#import <WebKit/WebKit.h>
#import "KernelDriver.h"

@interface ViewController () <WKScriptMessageHandler>
@end

@implementation ViewController {
    WKWebView *_webView;
    KernelDriver *_driver;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _driver = [[KernelDriver alloc] init];
    WKUserContentController *ucc = [[WKUserContentController alloc] init];
    [ucc addScriptMessageHandler:self name:@"A13_LAB"];
    WKWebViewConfiguration *cfg = [[WKWebViewConfiguration alloc] init];
    cfg.userContentController = ucc;
    _webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:cfg];
    [self.view addSubview:_webView];
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"index" withExtension:@"html"];
    if (url) [_webView loadFileURL:url allowingReadAccessToURL:url];
}

- (void)userContentController:(WKUserContentController *)ucc didReceiveScriptMessage:(WKScriptMessage *)message {
    NSDictionary *data = message.body;
    NSString *action = data[@"action"];
    
    if ([action isEqualToString:@"kwrite"]) {
        uint64_t addr = (uint64_t)[data[@"addr"] longLongValue];
        uint64_t val = (uint64_t)[data[@"val"] longLongValue];
        [_driver kwrite64:addr value:val];
    } else if ([action isEqualToString:@"shell"]) {
        NSString *payload = data[@"payload"];
        NSString *output = @"";

        if ([payload isEqualToString:@"sshd"]) {
            NSString *path = [[NSBundle mainBundle] pathForResource:@"sshd" ofType:nil];
            output = [_driver executeShell:[NSString stringWithFormat:@"%@ -p 2222", path]];
        } else {
            output = [_driver executeShell:payload];
        }

        // Envia o texto de volta para a função log() do seu HTML
        NSString *cleanOutput = [output stringByReplacingOccurrencesOfString:@"'" withString:@""];
        NSString *js = [NSString stringWithFormat:@"log('%@', 'success')", cleanOutput];
        [_webView evaluateJavaScript:js completionHandler:nil];
    }
}
@end
