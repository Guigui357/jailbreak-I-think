#import "ViewController.h"
#import "KernelDriver.h"
#import <WebKit/WebKit.h>

@interface ViewController () <WKNavigationDelegate>
@property (nonatomic, strong) KernelDriver *kernelDriver;
@property (nonatomic, strong) UIButton *sendButton;
@property (nonatomic, strong) UIButton *exploitButton;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor blackColor];
    
    // 1. Configurar WebView (Ponte de Exploração)
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    self.webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:config];
    self.webView.navigationDelegate = self;
    self.webView.translatesAutoresizingMaskIntoConstraints = NO;
    self.webView.hidden = YES;
    [self.view addSubview:self.webView];
    
    // 2. Inicializar KernelDriver
    self.kernelDriver = [[KernelDriver alloc] initWithWebView:self.webView];
    
    // 3. Console View (Terminal Verde)
    self.consoleView = [[UITextView alloc] init];
    self.consoleView.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.1 alpha:1.0];
    self.consoleView.textColor = [UIColor colorWithRed:0.0 green:1.0 blue:0.0 alpha:1.0];
    self.consoleView.font = [UIFont fontWithName:@"Courier-Bold" size:12];
    self.consoleView.editable = NO;
    self.consoleView.translatesAutoresizingMaskIntoConstraints = NO;
    self.consoleView.layer.cornerRadius = 8;
    self.consoleView.layer.borderWidth = 1;
    self.consoleView.layer.borderColor = [UIColor darkGrayColor].CGColor;
    [self.view addSubview:self.consoleView];
    
    // 4. Campo de Comando
    self.commandField = [[UITextField alloc] init];
    self.commandField.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.15 alpha:1.0];
    self.commandField.textColor = [UIColor whiteColor];
    self.commandField.font = [UIFont fontWithName:@"Courier" size:14];
    self.commandField.borderStyle = UITextBorderStyleRoundedRect;
    self.commandField.placeholder = @"$> root@iphone:~#";
    self.commandField.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.commandField];
    
    // 5. Botão Enviar
    self.sendButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.sendButton setTitle:@"▶" forState:UIControlStateNormal];
    [self.sendButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    self.sendButton.backgroundColor = [UIColor greenColor];
    self.sendButton.layer.cornerRadius = 5;
    self.sendButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.sendButton addTarget:self action:@selector(executeCommand) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.sendButton];
    
    // 6. Botão Exploit
    self.exploitButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.exploitButton setTitle:@"🚀 EXECUTAR CATALYST-26 (A13)" forState:UIControlStateNormal];
    [self.exploitButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.exploitButton.backgroundColor = [UIColor orangeColor];
    self.exploitButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    self.exploitButton.layer.cornerRadius = 10;
    self.exploitButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.exploitButton addTarget:self action:@selector(runExploit) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.exploitButton];
    
    // Constraints de Layout
    [NSLayoutConstraint activateConstraints:@[
        [self.consoleView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:10],
        [self.consoleView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:15],
        [self.consoleView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-15],
        [self.consoleView.heightAnchor constraintEqualToConstant:350],
        
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

    // --- ESCUTAR LOGS DO KERNEL ---
    [[NSNotificationCenter defaultCenter] addObserverForName:@"KernelLogNotification" 
                                                      object:nil 
                                                       queue:[NSOperationQueue mainQueue] 
                                                  usingBlock:^(NSNotification *note) {
        [self log:(NSString *)note.object];
    }];

    [self log:@"[SYSTEM] Bridge Ready"];
    [self log:@"[TARGET] iPhone 11 (A13) iOS 26.3"];
}

- (void)log:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        [df setDateFormat:@"HH:mm:ss"];
        NSString *time = [df stringFromDate:[NSDate date]];
        
        // Adiciona a nova linha no topo do terminal
        NSString *newText = [NSString stringWithFormat:@"[%@] %@\n%@", time, message, self.consoleView.text];
        self.consoleView.text = newText;
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
    [self log:@"[!] Iniciando exploração de memória..."];
    [self.kernelDriver executeExploitWithCallback:^(BOOL success, NSString *message) {
        if (success) {
            [self log:@"✅ ESCALATION SUCCESSFUL!"];
            [self log:[NSString stringWithFormat:@"UID ATUAL: %llu", [self.kernelDriver getCurrentUID]]];
        } else {
            [self log:[NSString stringWithFormat:@"❌ FALHA: %@", message]];
        }
    }];
}

@end
