#import "ViewController.h"
#import "KernelDriver.h"

@interface ViewController ()
@property (strong, nonatomic) WKWebView *webView;
@property (strong, nonatomic) KernelDriver *driver; // Retenção FORTE é obrigatória
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // 1. Instanciar o Driver (O objeto que processa o exploit)
    _driver = [[KernelDriver alloc] init];
    
    // 2. Configurar o UserContentController
    WKUserContentController *userContentController = [[WKUserContentController alloc] init];
    
    /** 
     * CRITICAL: 
     * O método 'addScriptMessageHandlerWithReply' é o que injeta 
     * a função 'postMessageWithReply' no JavaScript. 
     * O uso do 'pageWorld' garante que o script do HTML tenha acesso.
     */
    [userContentController addScriptMessageHandlerWithReply:self.driver 
                                               contentWorld:[WKContentWorld pageWorld] 
                                                       name:@"kernel"];
    
    // 3. Configurar a WebView
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.userContentController = userContentController;
    
    // Permitir leitura de arquivos do Bundle (importante para o sshd_static)
    [config.preferences setValue:@YES forKey:@"allowFileAccessFromFileURLs"];
    
    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:config];
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    
    [self.view addSubview:self.webView];
    
    // 4. Carregar o Console de Lab (index.html)
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"index" withExtension:@"html"];
    if (url) {
        [self.webView loadFileURL:url allowingReadAccessToURL:url.URLByDeletingLastPathComponent];
    } else {
        NSLog(@"[!] ERRO: index.html não encontrado no Bundle.");
    }
}

// Ocultar a barra de status para o console ocupar a tela toda
- (BOOL)prefersStatusBarHidden {
    return YES;
}

@end
