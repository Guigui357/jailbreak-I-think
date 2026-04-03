- (void)viewDidLoad {
    [super viewDidLoad];
    
    // 1. Manter referência forte
    self.driver = [[KernelDriver alloc] init];
    
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    
    // 2. INJEÇÃO: No iOS 26.4, se omitirmos o 'contentWorld', o WebKit 
    // usa o contexto compatível com o JavaScript da página por padrão.
    [config.userContentController addScriptMessageHandlerWithReply:self.driver 
                                                              name:@"kernel"];
    
    // 3. Habilitar TUDO para o exploit
    [config.preferences setValue:@YES forKey:@"allowFileAccessFromFileURLs"];
    [config setValue:@YES forKey:@"allowUniversalAccessFromFileURLs"];
    
    // 4. Inicializar WebView
    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:config];
    [self.view addSubview:self.webView];
    
    // 5. CARREGAMENTO: O segredo para o erro 'is not a function' sumir 
    // é carregar via baseURL do Bundle, mas como String.
    NSString *path = [[NSBundle mainBundle] pathForResource:@"index" ofType:@"html"];
    NSString *html = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    [self.webView loadHTMLString:html baseURL:[[NSBundle mainBundle] bundleURL]];
}
