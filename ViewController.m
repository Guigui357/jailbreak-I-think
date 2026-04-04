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

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    NSDictionary *data = message.body;
    NSString *action = data[@"action"];
    NSString *payload = data[@"payload"];
    NSString *output = @"";

    if ([action isEqualToString:@"kwrite"]) {
        [_driver kwrite64:[data[@"addr"] longLongValue] value:[data[@"val"] longLongValue]];
    } else if ([action isEqualToString:@"shell"]) {
        if ([payload isEqualToString:@"keygen"]) output = [_driver generateSSHKeys];
        else if ([payload isEqualToString:@"sshd"]) output = [_driver executeSSHD];
        else output = [_driver executeShell:payload];
        
        NSString *js = [NSString stringWithFormat:@"log('%@', 'success')", output];
        [_webView evaluateJavaScript:js completionHandler:nil];
    }
}

// Métodos para satisfazer o ViewController.h
- (void)log:(NSString *)message { NSLog(@"%@", message); }
- (void)executeCommand { }
- (void)runExploit { }

@end
