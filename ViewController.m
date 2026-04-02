#import "ViewController.h"
#import "KernelDriver.h"

@interface ViewController ()
// RETENÇÃO FORTE: Impede que a ponte morra após o carregamento
@property (strong, nonatomic) KernelDriver *driver; 
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Certifique-se que o driver é uma PROPRIEDADE (strong) da classe
    self.driver = [[KernelDriver alloc] init];
    
    // 1. Criar a configuração PRIMEIRO
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    
    // 2. Injetar o Handler DIRETAMENTE no controller da config
    [config.userContentController addScriptMessageHandlerWithReply:self.driver 
                                                      contentWorld:[WKContentWorld pageWorld] 
                                                              name:@"kernel"];
    
    // 3. Habilitar privilégios de arquivo (necessário para o exploit ler o bundle)
    [config setValue:@YES forKey:@"allowUniversalAccessFromFileURLs"];

    // 4. Instanciar a WebView com a config JÁ POPULADA
    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:config];
    [self.view addSubview:self.webView];
    
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"index" withExtension:@"html"];
    [self.webView loadFileURL:url allowingReadAccessToURL:url.URLByDeletingLastPathComponent];
}
