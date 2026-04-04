#import "ViewController.h"
#import "KernelDriver.h"
#import <WebKit/WebKit.h>

@interface ViewController () <WKNavigationDelegate, WKScriptMessageHandler>
@property (nonatomic, strong) KernelDriver *kernelDriver;
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) UITextView *consoleView;
@property (nonatomic, strong) UITextField *commandField;
@property (nonatomic, strong) UIButton *sendButton;
@property (nonatomic, strong) UIButton *exploitButton;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    
    // 1. Configurar WebView Invisível (Motor do Exploit)
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    [config.userContentController addScriptMessageHandler:self name:@"A13_LAB"];
    
    self.webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:config];
    self.webView.navigationDelegate = self;
    [self.view addSubview:self.webView];
    
    // 2. Inicializar KernelDriver
    self.kernelDriver = [[KernelDriver alloc] initWithWebView:self.webView];
    
    // 3. UI: Terminal Console
    self.consoleView = [[UITextView alloc] init];
    self.consoleView.backgroundColor = [UIColor colorWithRed:0.02 green:0.02 blue:0.05 alpha:1.0];
    self.consoleView.textColor = [UIColor colorWithRed:0.0 green:1.0 blue:0.41 alpha:1.0];
    self.consoleView.font = [UIFont fontWithName:@"Courier-Bold" size:11];
    self.consoleView.editable = NO;
    self.consoleView.translatesAutoresizingMaskIntoConstraints = NO;
    self.consoleView.layer.cornerRadius = 5;
    [self.view addSubview:self.consoleView];
    
    // 4. UI: Campo de Comando
    self.commandField = [[UITextField alloc] init];
    self.commandField.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.1 alpha:1.0];
    self.commandField.textColor = [UIColor whiteColor];
    self.commandField.font = [UIFont fontWithName:@"Courier" size:14];
    self.commandField.borderStyle = UITextBorderStyleNone;
    self.commandField.placeholder = @" root@iphone:~#";
    self.commandField.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.commandField];
    
    // 5. UI: Botões
    self.sendButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.sendButton setTitle:@"RUN" forState:UIControlStateNormal];
    [self.sendButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    self.sendButton.backgroundColor = [UIColor colorWithRed:0.0 green:1.0 blue:0.41 alpha:1.0];
    self.sendButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.sendButton addTarget:self action:@selector(executeCommand) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.sendButton];
    
    self.exploitButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.exploitButton setTitle:@"🚀 EXECUTE CATALYST-26 (A13)" forState:UIControlStateNormal];
    [self.exploitButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.exploitButton.backgroundColor = [UIColor systemOrangeColor];
    self.exploitButton.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    self.exploitButton.layer.cornerRadius = 8;
    self.exploitButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.exploitButton addTarget:self action:@selector(runExploit) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.exploitButton];
    
    [self setupConstraints];

    // Observador para Logs Nativo -> Console
    [[NSNotificationCenter defaultCenter] addObserverForName:@"KernelLogNotification" object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
        [self log:(NSString *)n.object];
    }];

    [self log:@"[SYSTEM] Catalyst Bridge Ready"];
    [self log:@"[TARGET] A13 iPhone 11 - iOS 26.3"];
}

#pragma mark - Ponte Nativa

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    // Repassa comandos do index.html para o driver
    [self.kernelDriver userContentController:userContentController didReceiveScriptMessage:message];
}

#pragma mark - Ações

- (void)runExploit {
    [self log:@"[!] Disparando Exploit de Memória..."];
    [self.kernelDriver executeExploitWithCallback:^(BOOL success, NSString *message) {
        if (success) {
            [self log:@"✅ ROOT ESCALATION SUCCESSFUL"];
            [self log:[NSString stringWithFormat:@"UID: %llu (root)", [self.kernelDriver getCurrentUID]]];
        } else {
            [self log:[NSString stringWithFormat:@"❌ FALHA: %@", message]];
        }
    }];
}

- (void)executeCommand {
    NSString *cmd = self.commandField.text;
    if (cmd.length == 0) return;
    [self log:[NSString stringWithFormat:@"# %@", cmd]];
    [self.kernelDriver runShell:cmd]; // Chama o método shell do KernelDriver
    self.commandField.text = @"";
    [self.view endEditing:YES];
}

- (void)log:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        [df setDateFormat:@"HH:mm:ss"];
        NSString *time = [df stringFromDate:[NSDate date]];
        self.consoleView.text = [NSString stringWithFormat:@"[%@] %@\n%@", time, message, self.consoleView.text];
    });
}

#pragma mark - Layout

- (void)setupConstraints {
    [NSLayoutConstraint activateConstraints:@[
        [self.consoleView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:10],
        [self.consoleView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:15],
        [self.consoleView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-15],
        [self.consoleView.heightAnchor constraintEqualToConstant:300],
        
        [self.commandField.topAnchor constraintEqualToAnchor:self.consoleView.bottomAnchor constant:15],
        [self.commandField.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:15],
        [self.commandField.trailingAnchor constraintEqualToAnchor:self.sendButton.leadingAnchor constant:-10],
        [self.commandField.heightAnchor constraintEqualToConstant:45],
        
        [self.sendButton.centerYAnchor constraintEqualToAnchor:self.commandField.centerYAnchor],
        [self.sendButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-15],
        [self.sendButton.widthAnchor constraintEqualToConstant:60],
        [self.sendButton.heightAnchor constraintEqualToConstant:45],
        
        [self.exploitButton.topAnchor constraintEqualToAnchor:self.commandField.bottomAnchor constant:20],
        [self.exploitButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:15],
        [self.exploitButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-15],
        [self.exploitButton.heightAnchor constraintEqualToConstant:55]
    ]];
}

@end
