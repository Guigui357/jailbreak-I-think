#import "ViewController.h"
#import "KernelDriver.h"
#import <WebKit/WebKit.h>

@interface ViewController () <WKNavigationDelegate, WKScriptMessageHandler>
@property (nonatomic, strong) UIButton *sendButton;
@property (nonatomic, strong) UIButton *exploitButton;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    
    // Configurar WebView
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    [config.userContentController addScriptMessageHandler:self name:@"A13_LAB"];
    self.webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:config];
    [self.view addSubview:self.webView];
    
    // Driver
    self.kernelDriver = [[KernelDriver alloc] initWithWebView:self.webView];
    
    // UI Setup
    self.consoleView = [[UITextView alloc] init];
    self.consoleView.backgroundColor = [UIColor colorWithRed:0.02 green:0.02 blue:0.05 alpha:1.0];
    self.consoleView.textColor = [UIColor colorWithRed:0.0 green:1.0 blue:0.41 alpha:1.0];
    self.consoleView.font = [UIFont fontWithName:@"Courier-Bold" size:11];
    self.consoleView.editable = NO;
    self.consoleView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.consoleView];
    
    self.commandField = [[UITextField alloc] init];
    self.commandField.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.1 alpha:1.0];
    self.commandField.textColor = [UIColor whiteColor];
    self.commandField.borderStyle = UITextBorderStyleNone;
    self.commandField.placeholder = @" root@iphone:~#";
    self.commandField.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.commandField];
    
    self.sendButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.sendButton setTitle:@"RUN" forState:UIControlStateNormal];
    [self.sendButton setBackgroundColor:[UIColor colorWithRed:0.0 green:1.0 blue:0.41 alpha:1.0]];
    [self.sendButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    self.sendButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.sendButton addTarget:self action:@selector(executeCommand) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.sendButton];
    
    self.exploitButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.exploitButton setTitle:@"🚀 EXECUTE CATALYST-26" forState:UIControlStateNormal];
    self.exploitButton.backgroundColor = [UIColor orangeColor];
    [self.exploitButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.exploitButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.exploitButton addTarget:self action:@selector(runExploit) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.exploitButton];
    
    [self setupLayout];

    [[NSNotificationCenter defaultCenter] addObserverForName:@"KernelLogNotification" object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
        [self log:(NSString *)n.object];
    }];
}

- (void)setupLayout {
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

- (void)userContentController:(WKUserContentController *)u didReceiveScriptMessage:(WKScriptMessage *)m {
    [self.kernelDriver userContentController:u didReceiveScriptMessage:m];
}

- (void)executeCommand {
    NSString *cmd = self.commandField.text;
    if (!cmd.length) return;
    [self log:[NSString stringWithFormat:@"# %@", cmd]];
    // Chamando o método correto de execução do Driver
    [self.kernelDriver executeCommand:cmd withCallback:^(NSString *output) {
        [self log:output];
    }];
    self.commandField.text = @"";
}

- (void)runExploit {
    [self.kernelDriver executeExploitWithCallback:^(BOOL success, NSString *msg) {
        [self log:success ? @"✅ ROOT SUCCESS" : [@"❌ FALHA: " stringByAppendingString:msg]];
    }];
}

- (void)log:(NSString *)m {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.consoleView.text = [NSString stringWithFormat:@"%@\n%@", m, self.consoleView.text];
    });
}
@end
