//
//  ViewController.m
//  JailbreakApp
//

#import "ViewController.h"
#import "KernelDriver.h"

@interface ViewController () <WKNavigationDelegate>
@property (nonatomic, strong) KernelDriver *kernelDriver;
@property (nonatomic, strong) UIButton *sendButton;
@property (nonatomic, strong) UIButton *exploitButton;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor blackColor];
    
    // Configurar WebView (oculta, apenas para bridge)
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    self.webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:config];
    self.webView.navigationDelegate = self;
    self.webView.backgroundColor = [UIColor blackColor];
    self.webView.translatesAutoresizingMaskIntoConstraints = NO;
    self.webView.hidden = YES; // Esconder, apenas para comunicação
    [self.view addSubview:self.webView];
    
    // Inicializar KernelDriver
    self.kernelDriver = [[KernelDriver alloc] initWithWebView:self.webView];
    
    // Configurar console
    self.consoleView = [[UITextView alloc] init];
    self.consoleView.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.1 alpha:1.0];
    self.consoleView.textColor = [UIColor colorWithRed:0.0 green:1.0 blue:0.0 alpha:1.0];
    self.consoleView.font = [UIFont fontWithName:@"Courier" size:12];
    self.consoleView.editable = NO;
    self.consoleView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.consoleView];
    
    // Configurar campo de comando
    self.commandField = [[UITextField alloc] init];
    self.commandField.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.15 alpha:1.0];
    self.commandField.textColor = [UIColor colorWithRed:0.0 green:1.0 blue:0.0 alpha:1.0];
    self.commandField.font = [UIFont fontWithName:@"Courier" size:14];
    self.commandField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"$> " attributes:@{NSForegroundColorAttributeName: [UIColor grayColor]}];
    self.commandField.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.commandField];
    
    // Botão de enviar
    self.sendButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.sendButton setTitle:@"▶" forState:UIControlStateNormal];
    [self.sendButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    self.sendButton.backgroundColor = [UIColor colorWithRed:0.0 green:1.0 blue:0.0 alpha:1.0];
    self.sendButton.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    self.sendButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.sendButton addTarget:self action:@selector(executeCommand) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.sendButton];
    
    // Botão de exploit
    self.exploitButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.exploitButton setTitle:@"🚀 EXECUTAR EXPLOIT" forState:UIControlStateNormal];
    [self.exploitButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    self.exploitButton.backgroundColor = [UIColor colorWithRed:1.0 green:0.5 blue:0.0 alpha:1.0];
    self.exploitButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    self.exploitButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.exploitButton addTarget:self action:@selector(runExploit) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.exploitButton];
    
    // Layout
    [NSLayoutConstraint activateConstraints:@[
        [self.webView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.webView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.webView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.webView.heightAnchor constraintEqualToConstant:0],
        
        [self.consoleView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:10],
        [self.consoleView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10],
        [self.consoleView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10],
        [self.consoleView.heightAnchor constraintEqualToConstant:400],
        
        [self.commandField.topAnchor constraintEqualToAnchor:self.consoleView.bottomAnchor constant:10],
        [self.commandField.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10],
        [self.commandField.trailingAnchor constraintEqualToAnchor:self.sendButton.leadingAnchor constant:-10],
        [self.commandField.heightAnchor constraintEqualToConstant:44],
        
        [self.sendButton.topAnchor constraintEqualToAnchor:self.consoleView.bottomAnchor constant:10],
        [self.sendButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10],
        [self.sendButton.widthAnchor constraintEqualToConstant:50],
        [self.sendButton.heightAnchor constraintEqualToConstant:44],
        
        [self.exploitButton.topAnchor constraintEqualToAnchor:self.commandField.bottomAnchor constant:10],
        [self.exploitButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10],
        [self.exploitButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10],
        [self.exploitButton.heightAnchor constraintEqualToConstant:50]
    ]];
    
    // Carregar HTML bridge
    NSString *html = [self htmlBridge];
    [self.webView loadHTMLString:html baseURL:nil];
    
    [self log:@"KernelDriver loaded - Ready"];
    [self log:@"Target: iPhone 11 (A13) iOS 26.3"];
}

- (NSString *)htmlBridge {
    return @"<!DOCTYPE html><html><head><meta name='viewport' content='width=device-width'><style>body{background:#000;color:#0f0;font-family:monospace;}</style></head><body><h2>KernelDriver Bridge</h2><script>window.KernelDriver={call:function(a,d){return new Promise((r,j)=>{window.webkit.messageHandlers.kernelDriver.postMessage({action:a,...d});window._cb={r,j}});},getStatus:function(){return this.call('getStatus');},leakSlide:function(){return this.call('leakSlide');},ptePatch:function(){return this.call('ptePatch');},executeCommand:function(c){return this.call('executeCommand',{command:c});}};window._handleReply=function(r,e){if(window._cb){if(e)window._cb.j(e);else window._cb.r(r);window._cb=null;}};document.body.innerHTML+='<div>✓ Bridge ready</div>';</script></body></html>";
}

- (void)log:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *timestamp = [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                              dateStyle:NSDateFormatterNoStyle
                                                              timeStyle:NSDateFormatterMediumStyle];
        self.consoleView.text = [NSString stringWithFormat:@"[%@] %@\n%@", timestamp, message, self.consoleView.text];
    });
}

- (void)executeCommand {
    NSString *cmd = self.commandField.text;
    if (cmd.length == 0) return;
    
    [self log:[NSString stringWithFormat:@"$> %@", cmd]];
    self.commandField.text = @"";
    
    if ([cmd isEqualToString:@"clear"]) {
        self.consoleView.text = @"";
        return;
    }
    
    // Usar KernelDriver diretamente
    [self.kernelDriver executeCommand:cmd withCallback:^(NSString *result) {
        [self log:result];
    }];
}

- (void)runExploit {
    [self log:@"========================================"];
    [self log:@"Starting kernel exploit..."];
    [self log:@"========================================"];
    
    [self.kernelDriver executeExploitWithCallback:^(BOOL success, NSString *message) {
        if (success) {
            [self log:message];
            [self log:@"✅ JAILBREAK COMPLETO! Root access acquired!"];
        } else {
            [self log:[NSString stringWithFormat:@"❌ Exploit failed: %@", message]];
        }
    }];
}

@end
