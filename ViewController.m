#import "ViewController.h"
#import "KernelDriver.h"

@interface ViewController ()
// RETENÇÃO FORTE: Impede que a ponte morra após o carregamento
@property (strong, nonatomic) KernelDriver *driver; 
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // 1. Instância FORTE (Propriedade da classe)
    self.driver = [[KernelDriver alloc] init];
    
    // 2. Configuração com o Handler ANTES da WebView existir
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    
    // USAR defaultWorld para arquivos locais (file://) no iOS 26.4
    [config.userContentController addScriptMessageHandlerWithReply:self.driver 
                                                      contentWorld:[WKContentWorld defaultWorld] 
                                                              name:@"kernel"];
    
    // 3. Habilitar acessos universais para o exploit
    [config setValue:@YES forKey:@"allowUniversalAccessFromFileURLs"];

    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:config];
    [self.view addSubview:self.webView];
    
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"index" withExtension:@"html"];
    [self.webView loadFileURL:url allowingReadAccessToURL:url.URLByDeletingLastPathComponent];
}
