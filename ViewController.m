#import "ViewController.h"
#import <WebKit/WebKit.h>
#import "KernelDriver.h"

@implementation ViewController {
    WKWebView *_webView;
    KernelDriver *_driver;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Inicia o motor de kernel
    _driver = [[KernelDriver alloc] init];

    // Configura a ponte A13_LAB
    WKUserContentController *ucc = [[WKUserContentController alloc] init];
    [ucc addScriptMessageHandler:self name:@"A13_LAB"];

    WKWebViewConfiguration *cfg = [[WKWebViewConfiguration alloc] init];
    cfg.userContentController = ucc;

    _webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:cfg];
    [self.view addSubview:_webView];

    // Carrega o seu HTML do Jailbreak
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"index" withExtension:@"html"];
    [_webView loadFileURL:url allowingReadAccessToURL:url];
}

// --- RECEBENDO COMANDOS DO HTML ---
- (void)userContentController:(WKUserContentController *)ucc didReceiveScriptMessage:(WKScriptMessage *)msg {
    NSDictionary *data = msg.body;
    NSString *action = data[@"action"];
    
    // Ação 1: Patch de Memória (AMFI/PAC)
    if ([action isEqualToString:@"kwrite"]) {
        uint64_t addr = [data[@"addr"] longLongValue];
        uint64_t val = [data[@"val"] longLongValue];
        [_driver kwrite64:addr value:val];
    }
    
    // Ação 2: Comandos de Shell (Remount, MKDIR, etc)
    if ([action isEqualToString:@"shell"]) {
        [_driver executeShell:data[@"payload"]];
        // Retorna sucesso para o console do HTML
        [_webView evaluateJavaScript:@"log('Shell: Comando Executado.', 'success')" completionHandler:nil];
    }
}

@end
