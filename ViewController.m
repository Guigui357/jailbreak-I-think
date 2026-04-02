#import "ViewController.h"
#import "KernelDriver.h"

@interface ViewController ()
@property (strong, nonatomic) KernelDriver *driver;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // 1. Instância do Driver (Retenção forte via property)
    self.driver = [[KernelDriver alloc] init];
    
    // 2. Configuração da Ponte (WKContentWorld pageWorld é o correto)
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    [config.userContentController addScriptMessageHandlerWithReply:self.driver 
                                                      contentWorld:[WKContentWorld pageWorld] 
                                                              name:@"kernel"];
    
    // 3. Permissões de arquivo para o exploit
    [config.preferences setValue:@YES forKey:@"allowFileAccessFromFileURLs"];
    [config setValue:@YES forKey:@"allowUniversalAccessFromFileURLs"];

    // 4. Inicializar WebView com a config pronta
    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:config];
    [self.view addSubview:self.webView];
    
    // 5. Carregar o HTML do Lab
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"index" withExtension:@"html"];
    if (url) {
        [self.webView loadFileURL:url allowingReadAccessToURL:url.URLByDeletingLastPathComponent];
    }
}

@end
