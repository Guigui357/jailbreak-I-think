#import "ViewController.h"
#import "KernelDriver.h"

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // 1. Inicializa o motor (KernelBridge)
    // Certifique-se de que a variável 'kernelBridge' está declarada no ViewController.h
    self.kernelBridge = [[KernelBridge alloc] init];
    
    // 2. Configura a WebView com o Handler "kernel"
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    
    // O SEGREDO: Registrar ANTES de criar a WebView
    // O nome "kernel" deve ser exatamente igual ao usado no JS
    [config.userContentController addScriptMessageHandlerWithReply:self.kernelBridge 
                                                      contentWorld:WKContentWorld.pageWorld 
                                                              name:@"kernel"];
    
    // 3. Cria a WebView ocupando a tela toda
    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:config];
    self.webView.autoresizingMask = (UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight);
    [self.view addSubview:self.webView];
    
    // 4. Carrega o HTML do Bundle
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"index" withExtension:@"html"];
    if (url) {
        // 'allowingReadAccessToURL' permite que o HTML leia arquivos na mesma pasta
        [self.webView loadFileURL:url allowingReadAccessToURL:url.URLByDeletingLastPathComponent];
        NSLog(@"[+] Bridge 'kernel' injetada e index.html carregado.");
    } else {
        NSLog(@"[!] ERRO: index.html não encontrado no projeto Xcode.");
    }
}

@end
