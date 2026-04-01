#import "ViewController.h"
#import <dlfcn.h>

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    // 1. Forçar o carregamento da Bridge (Dylib)
    // No A13, o Feather pode colocar a dylib em caminhos diferentes
    void *handle = dlopen("@executable_path/KernelBridge.dylib", RTLD_NOW);
    if (!handle) {
        handle = dlopen("KernelBridge.dylib", RTLD_NOW);
    }

    // 2. Configurar o WKWebView e o Handler "kexec"
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    
    // IMPORTANTE: Criamos a instância da classe que está no KernelDriver.m
    id bridge = [[NSClassFromString(@"KernelBridge") alloc] init];
    if (bridge) {
        [bridge setValue:self.webView forKey:@"webView"];
        [config.userContentController addScriptMessageHandler:bridge name:@"kexec"];
    }

    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:config];
    [self.view addSubview:self.webView];

    // 3. Carregar o HTML
    NSString *path = [[NSBundle mainBundle] pathForResource:@"index" ofType:@"html"];
    if (path) {
        [self.webView loadFileURL:[NSURL fileURLWithPath:path] allowingReadAccessToURL:[NSURL fileURLWithPath:[path stringByDeletingLastPathComponent]]];
    }
}
@end
