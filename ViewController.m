#import "ViewController.h"
#import <dlfcn.h>

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    // 1. Forçar carregamento da dylib (GitHub/Feather)
    void *handle = dlopen("@executable_path/KernelBridge.dylib", RTLD_NOW);
    if (!handle) handle = dlopen("KernelBridge.dylib", RTLD_NOW);

    // 2. CONFIGURAÇÃO CRÍTICA: Registrar o handler ANTES da WebView
    WKUserContentController *userContent = [[WKUserContentController alloc] init];
    
    // Tenta achar a classe KernelBridge que compilamos no GitHub
    Class bridgeClass = NSClassFromString(@"KernelBridge");
    if (bridgeClass) {
        id bridgeInstance = [[bridgeClass alloc] init];
        
        // IMPORTANTE: O nome aqui DEVE ser "kexec" para bater com o seu JS
        [userContent addScriptMessageHandler:bridgeInstance name:@"kexec"];
        
        // Conecta a webview à bridge para o C poder mandar logs de volta
        // Usamos delay porque a webview ainda não foi criada
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [bridgeInstance setValue:self.webView forKey:@"webView"];
        });
    }

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.userContentController = userContent;

    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:config];
    [self.view addSubview:self.webView];

    // 3. Carregar o HTML
    NSString *path = [[NSBundle mainBundle] pathForResource:@"index" ofType:@"html"];
    if (path) {
        NSURL *url = [NSURL fileURLWithPath:path];
        [self.webView loadFileURL:url allowingReadAccessToURL:[url URLByDeletingLastPathComponent]];
    }
}
@end
