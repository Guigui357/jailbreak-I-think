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
@property (nonatomic, strong) UITextView *consoleView;
@property (nonatomic, strong) UITextField *commandField;
@property (nonatomic, strong) WKWebView *webView;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor blackColor];
    
    // 1. Configurar WebView (Bridge Invisível)
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    self.webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:config];
    self.webView.navigationDelegate = self;
    self.webView.translatesAutoresizingMaskIntoConstraints = NO;
    self.webView.hidden = YES;
    [self.view addSubview:self.webView];
    
    // 2. Inicializar KernelDriver
    self.kernelDriver = [[KernelDriver alloc] initWithWebView:self.webView];
    
    // 3. Console View (Terminal)
    self.consoleView = [[UITextView alloc] init];
    self.consoleView.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.1 alpha:1.0];
    self.consoleView.textColor = [UIColor colorWithRed:0.0 green:1.0 blue:0.0 alpha:1.0];
    self.consoleView.font = [UIFont fontWithName:@"Courier" size:12];
    self.consoleView.editable = NO;
    self.consoleView.translatesAutoresizingMaskIntoConstraints = NO;
    self.consoleView.layer.cornerRadius = 8;
    [self.view addSubview:self.consoleView];
    
    // 4. Campo de Comando
    self.commandField = [[UITextField alloc] init];
    self.commandField.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.15 alpha:1.0];
    self.commandField.textColor = [UIColor whiteColor];
    self.commandField.font = [UIFont fontWithName:@"Courier" size:14];
    self.commandField.borderStyle = UITextBorderStyleRoundedRect;
    self.commandField.placeholder = @"$> Digite um comando...";
    self.commandField.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.commandField];
    
    // 5. Botão Enviar (▶)
    self.sendButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.sendButton setTitle:@"▶" forState:UIControlStateNormal];
    [self.sendButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    self.sendButton.backgroundColor = [UIColor greenColor];
    self.sendButton.layer.cornerRadius = 5;
    self.sendButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.sendButton addTarget:self action:@selector(executeCommand) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.sendButton];
    
    // 6. Botão Exploit (Laranja - Visível)
    self.exploitButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.exploitButton setTitle:@"🚀 EXECUTAR EXPLOIT (A13)" forState:UIControlStateNormal];
    [self.exploitButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.exploitButton.backgroundColor = [UIColor orangeColor];
    self.exploitButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    self.exploitButton.layer.cornerRadius = 10;
    self.exploitButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.exploitButton addTarget:self action:@selector(runExploit) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.exploitButton];
    
    // LAYOUT CONSTRAINTS (Ajustado para iPhone 11)
    [NSLayoutConstraint activateConstraints:@[
        [self.consoleView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:10],
        [self.consoleView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:15],
        [self.consoleView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-15],
        [self.consoleView.heightAnchor constraintEqualToConstant:300], // Menor para caber tudo
        
        [self.commandField.topAnchor constraintEqualToAnchor:self.consoleView.bottomAnchor constant:15],
        [self.commandField.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:15],
        [self.commandField.trailingAnchor constraintEqualToAnchor:self.sendButton.leadingAnchor constant:-10],
        [self.commandField.heightAnchor constraintEqualToConstant:44],
        
        [self.sendButton.centerYAnchor constraintEqualToAnchor:self.commandField.centerYAnchor],
        [self.sendButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-15],
        [self.sendButton.widthAnchor constraintEqualToConstant:50],
        [self.sendButton.heightAnchor constraintEqualToConstant:44],
        
        [self.exploitButton.topAnchor constraintEqualToAnchor:self.commandField.bottomAnchor constant:20],
        [self.exploitButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:15],
        [self.exploitButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-15],
        [self.exploitButton.heightAnchor constraintEqualToConstant:60]
    ]];
    
    [self log:@"Catalyst-26: Bridge Ready"];
    [self log:@"Target: iPhone 11 A13 (iOS 26.3)"];
}

- (void)log:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"HH:mm:ss"];
        NSString *time = [formatter stringFromDate:[NSDate date]];
        
        self.consoleView.text = [NSString stringWithFormat:@"[%@] %@\n%@", time, message, self.consoleView.text];
    });
}

- (void)executeCommand {
    NSString *cmd = self.commandField.text;
    if (cmd.length == 0) return;
    
    [self log:[NSString stringWithFormat:@"$> %@", cmd]];
    self.commandField.text = @"";
    
    [self.kernelDriver executeCommand:cmd withCallback:^(NSString *result) {
        [self log:result];
    }];
}

- (void)runExploit {
    [self log:@"[!] Iniciando Catalyst-26..."];
    [self log:@"[!] KASLR Bypass via Leak Port..."];
    
    [self.kernelDriver executeExploitWithCallback:^(BOOL success, NSString *message) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success) {
                [self log:@"✅ ROOT ESCALATION: SUCCESS"];
                [self log:[NSString stringWithFormat:@"UID: %llu", [self.kernelDriver getCurrentUID]]];
                [self log:message];
            } else {
                [self log:[NSString stringWithFormat:@"❌ FALHA: %@", message]];
            }
        });
    }];
}

@end
