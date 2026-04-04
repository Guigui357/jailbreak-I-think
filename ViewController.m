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
    NSString *payload = data[@"payload"];
    __block NSString *output = @"";

    if ([action isEqualToString:@"kwrite"]) {
        uint64_t addr = (uint64_t)[data[@"addr"] longLongValue];
        uint64_t val = (uint64_t)[data[@"val"] longLongValue];
        [_driver kwrite64:addr value:val];
        output = @"[kwrite] OK";
    } 
    else if ([action isEqualToString:@"shell"]) {
        // Escala para ROOT antes de qualquer operação de shell
        [_driver escalatePrivileges]; 
        
        if ([payload isEqualToString:@"keygen"]) {
            output = [_driver generateSSHKeys];
        } else if ([payload isEqualToString:@"sshd"]) {
            output = [_driver executeSSHD];
        } else {
            output = [_driver executeShell:payload];
        }
        
        // Sanitização para o JavaScript não quebrar
        NSString *cleanOut = [output stringByReplacingOccurrencesOfString:@"'" withString:@""];
        cleanOut = [cleanOut stringByReplacingOccurrencesOfString:@"\n" withString:@"<br>"];
        
        NSString *js = [NSString stringWithFormat:@"log('%@', 'success')", cleanOut];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_webView evaluateJavaScript:js completionHandler:nil];
        });
    }
}

// Satisfazendo o Header
- (void)log:(NSString *)message { NSLog(@"%@", message); }
- (void)executeCommand { }
- (void)runExploit { }

@end
