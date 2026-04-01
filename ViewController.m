#import "ViewController.h"
#import <WebKit/WebKit.h>
#import <dlfcn.h>

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    // 1. Carregar a dylib injetada pelo Feather
    // O Feather coloca a dylib no Frameworks ou na raiz do App
    dlopen("KernelBridge.dylib", RTLD_NOW);

    // 2. Configurar a WebView
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    
    // IMPORTANTE: O nome "kexec" deve ser o mesmo do KernelDriver.m
    // Se a dylib for injetada corretamente, ela já registra o handler.
    
    WKWebView *webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:config];
    [self.view addSubview:webView];

    // 3. Carregar o index.html
    NSURL *htmlURL = [[NSBundle mainBundle] URLForResource:@"index" withExtension:@"html"];
    if (htmlURL) {
        [webView loadFileURL:htmlURL allowingReadAccessToURL:htmlURL.URLByDeletingLastPathComponent];
    } else {
        NSLog(@"[!] Erro: index.html não encontrado no Bundle!");
    }
}
@end
