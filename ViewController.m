#import "ViewController.h"
#import <WebKit/WebKit.h>
#import "KernelDriver.h"

// Adicionando conformidade ao protocolo para aceitar o 'self' como handler
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

    if ([action isEqualToString:@"kwrite"]) {
        uint64_t addr = (uint64_t)[data[@"addr"] longLongValue];
        uint64_t val = (uint64_t)[data[@"val"] longLongValue];
        [_driver kwrite64:addr value:val];
    } else if ([action isEqualToString:@"shell"]) {
        [_driver executeShell:data[@"payload"]];
    }
}

// Implementando os métodos que o seu Header (.h) exigia para não dar warning
- (void)log:(NSString *)message { NSLog(@"%@", message); }
- (void)executeCommand { [self log:@"Comando executado"]; }
- (void)runExploit { [self log:@"Exploit iniciado"]; }

@end
