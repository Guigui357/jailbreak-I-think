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
    
    // Inicializa o motor de kernel (TFP0)
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
    NSString *payload = data[@"payload"];
    
    __block NSString *output = @"";

    // 1. AÇÃO DE ESCRITA NO KERNEL (PATCH AMFI/PAC)
    if ([action isEqualToString:@"kwrite"]) {
        uint64_t addr = (uint64_t)[data[@"addr"] longLongValue];
        uint64_t val = (uint64_t)[data[@"val"] longLongValue];
        [_driver kwrite64:addr value:val];
        output = @"[kwrite] Comando enviado ao Kernel.";
    }
    
    // 2. AÇÃO DE SHELL / SSH SETUP
    else if ([action isEqualToString:@"shell"]) {
        
        if ([payload isEqualToString:@"keygen"]) {
            // Chama a função real de geração de chaves no KernelDriver.m
            output = [_driver generateSSHKeys];
        } 
        else if ([payload isEqualToString:@"sshd"]) {
            // Chama a função de posix_spawn do SSHD no KernelDriver.m
            output = [_driver executeSSHD];
        } 
        else {
            // Comandos genéricos (id, ls, mount, etc)
            output = [_driver executeShell:payload];
        }
    }

    // RETORNA A SAÍDA PARA A FUNÇÃO log() DO HTML
    // Limpamos quebras de linha para não quebrar o JS
    NSString *cleanOutput = [output stringByReplacingOccurrencesOfString:@"\n" withString:@"<br>"];
    NSString *js = [NSString stringWithFormat:@"log('%@', 'success')", cleanOutput];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_webView evaluateJavaScript:js completionHandler:nil];
    });
}

@end
