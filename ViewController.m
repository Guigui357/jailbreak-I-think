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
    
    // Inicializa o motor de kernel (A13/TFP0)
    _driver = [[KernelDriver alloc] init];

    // Configura a ponte para o JavaScript
    WKUserContentController *ucc = [[WKUserContentController alloc] init];
    [ucc addScriptMessageHandler:self name:@"A13_LAB"];

    WKWebViewConfiguration *cfg = [[WKWebViewConfiguration alloc] init];
    cfg.userContentController = ucc;

    _webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:cfg];
    [self.view addSubview:_webView];

    // Carrega o index.html do Bundle
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"index" withExtension:@"html"];
    if (url) [_webView loadFileURL:url allowingReadAccessToURL:url];
}

// --- BRIDGE: RECEBENDO MENSAGENS DO INDEX.HTML ---
- (void)userContentController:(WKUserContentController *)ucc didReceiveScriptMessage:(WKScriptMessage *)message {
    NSDictionary *data = message.body;
    NSString *action = data[@"action"];
    
    // 1. AÇÃO DE ESCRITA NO KERNEL (PATCH AMFI/PAC)
    if ([action isEqualToString:@"kwrite"]) {
        uint64_t addr = (uint64_t)[data[@"addr"] longLongValue];
        uint64_t val = (uint64_t)[data[@"val"] longLongValue];
        [_driver kwrite64:addr value:val];
    }
    
    // 2. AÇÃO DE SHELL (COMANDOS ROOT)
    else if ([action isEqualToString:@"shell"]) {
        NSString *payload = data[@"payload"];
        NSString *output = @"";

        // SE O COMANDO FOR 'sshd', BUSCAMOS O CAMINHO NO BUNDLE
        if ([payload isEqualToString:@"sshd"]) {
            NSString *sshPath = [[NSBundle mainBundle] pathForResource:@"sshd" ofType:nil];
            if (sshPath) {
                // Comando real: /caminho/do/app/sshd -p 2222 -R (para rodar em background)
                NSString *fullCmd = [NSString stringWithFormat:@"%@ -p 2222 -R", sshPath];
                output = [_driver executeShell:fullCmd];
            } else {
                output = @"Erro: Binário sshd não encontrado no Bundle.";
            }
        } else {
            // Comando comum (id, ls, mount, etc)
            output = [_driver executeShell:payload];
        }

        // RETORNA A SAÍDA PARA O TERMINAL DO HTML
        NSString *js = [NSString stringWithFormat:@"log('%@', 'success')", [output stringByReplacingOccurrencesOfString:@"\n" withString:@"<br>"]];
        [_webView evaluateJavaScript:js completionHandler:nil];
    }
}

// Métodos exigidos pelo Header
- (void)log:(NSString *)message { NSLog(@"%@", message); }
- (void)executeCommand { }
- (void)runExploit { }

@end
