#import "ViewController.h"
#import "KernelDriver.h"

@interface ViewController ()
@property (strong, nonatomic) KernelDriver *driver; 
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.driver = [[KernelDriver alloc] init];
    
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    
    // 1. O NOME: Mude de 'kernel' para 'A13_LAB' para testar colisão
    [config.userContentController addScriptMessageHandler:self.driver name:@"A13_LAB"];

    // 2. RETER O DRIVER: Vincular a WebView ao Driver para o Callback funcionar
    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:config];
    self.driver.webView = self.webView; 
    
    [self.view addSubview:self.webView];
    
    // 3. CARREGAMENTO: Use um delay de 200ms para garantir a injeção nativa
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSURL *url = [[NSBundle mainBundle] URLForResource:@"index" withExtension:@"html"];
        [self.webView loadFileURL:url allowingReadAccessToURL:url.URLByDeletingLastPathComponent];
    });
}
@end
