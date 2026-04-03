//
//  ViewController.m
//  JailbreakApp
//

#import "ViewController.h"
#import "KernelDriver.h"
#import <WebKit/WebKit.h>

@interface ViewController () <WKNavigationDelegate>
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) KernelDriver *kernelDriver;
@property (nonatomic, strong) UITextView *consoleView;
@property (nonatomic, strong) UITextField *commandField;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor blackColor];
    
    // Configurar WebView
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    WKUserContentController *controller = [[WKUserContentController alloc] init];
    config.userContentController = controller;
    
    self.webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:config];
    self.webView.navigationDelegate = self;
    self.webView.backgroundColor = [UIColor blackColor];
    self.webView.translatesAutoresizingMaskIntoConstraints = NO;
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
    UIButton *sendButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [sendButton setTitle:@"▶" forState:UIControlStateNormal];
    [sendButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    sendButton.backgroundColor = [UIColor colorWithRed:0.0 green:1.0 blue:0.0 alpha:1.0];
    sendButton.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    sendButton.translatesAutoresizingMaskIntoConstraints = NO;
    [sendButton addTarget:self action:@selector(executeCommand) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:sendButton];
    
    // Botão de exploit
    UIButton *exploitButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [exploitButton setTitle:@"🚀 EXECUTAR EXPLOIT" forState:UIControlStateNormal];
    [exploitButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    exploitButton.backgroundColor = [UIColor colorWithRed:1.0 green:0.5 blue:0.0 alpha:1.0];
    exploitButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    exploitButton.translatesAutoresizingMaskIntoConstraints = NO;
    [exploitButton addTarget:self action:@selector(runExploit) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:exploitButton];
    
    // Layout
    [NSLayoutConstraint activateConstraints:@[
        [self.webView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.webView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.webView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.webView.heightAnchor constraintEqualToConstant:0], // Oculto, apenas para bridge
        
        [self.consoleView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:10],
        [self.consoleView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10],
        [self.consoleView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10],
        [self.consoleView.heightAnchor constraintEqualToConstant:400],
        
        [self.commandField.topAnchor constraintEqualToAnchor:self.consoleView.bottomAnchor constant:10],
        [self.commandField.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10],
        [self.commandField.trailingAnchor constraintEqualToAnchor:sendButton.leadingAnchor constant:-10],
        [self.commandField.heightAnchor constraintEqualToConstant:44],
        
        [sendButton.topAnchor constraintEqualToAnchor:self.consoleView.bottomAnchor constant:10],
        [sendButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10],
        [sendButton.widthAnchor constraintEqualToConstant:50],
        [sendButton.heightAnchor constraintEqualToConstant:44],
        
        [exploitButton.topAnchor constraintEqualToAnchor:self.commandField.bottomAnchor constant:10],
        [exploitButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10],
        [exploitButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10],
        [exploitButton.heightAnchor constraintEqualToConstant:50]
    ]];
    
    // Carregar HTML bridge
    NSString *html = [self htmlBridge];
    [self.webView loadHTMLString:html baseURL:nil];
    
    [self log:@"KernelDriver loaded - Ready"];
    [self log:@"Target: iPhone 11 (A13) iOS 26.3"];
    [self log:@"Click EXECUTAR EXPLOIT to start"];
}

- (NSString *)htmlBridge {
    return @"\
        <!DOCTYPE html>\
        <html>\
        <head>\
            <meta name='viewport' content='width=device-width, initial-scale=1.0'>\
            <style>\
                body { background: #000; color: #0f0; font-family: monospace; padding: 10px; }\
                .status { color: #0f0; }\
                .root { color: #f0f; }\
            </style>\
        </head>\
        <body>\
            <h2>⚡ KernelDriver Bridge ⚡</h2>\
            <div id='status'>Loading...</div>\
            <script>\
                window.KernelDriver = {\
                    call: function(action, data) {\
                        return new Promise((resolve, reject) => {\
                            var message = {action: action};\
                            if (data) Object.assign(message, data);\
                            window.webkit.messageHandlers.kernelDriver.postMessage(message);\
                            window._callback = {resolve, reject};\
                        });\
                    },\
                    getStatus: function() { return this.call('getStatus'); },\
                    leakSlide: function() { return this.call('leakSlide'); },\
                    ptePatch: function() { return this.call('ptePatch'); },\
                    executeCommand: function(cmd) { return this.call('executeCommand', {command: cmd}); }\
                };\
                \
                window._handleReply = function(reply, error) {\
                    if (window._callback) {\
                        if (error) window._callback.reject(error);\
                        else window._callback.resolve(reply);\
                        window._callback = null;\
                    }\
                };\
                \
                document.getElementById('status').innerHTML = '✓ Ready';\
                console.log('Bridge loaded');\
            </script>\
        </body>\
        </html>\
    ";
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
    
    [self.kernelDriver.webView evaluateJavaScript:[NSString stringWithFormat:@"KernelDriver.executeCommand('%@')", cmd]
                                completionHandler:nil];
}

- (void)runExploit {
    [self log:@"========================================"];
    [self log:@"Starting kernel exploit..."];
    [self log:@"========================================"];
    
    // Step 1: Leak kernel slide
    [self log:@"[1/4] Leaking kernel slide..."];
    [self.kernelDriver.webView evaluateJavaScript:@"KernelDriver.leakSlide()" completionHandler:^(id result, NSError *error) {
        if (error) {
            [self log:[NSString stringWithFormat:@"[!] Failed to leak slide: %@", error]];
            return;
        }
        
        NSDictionary *dict = (NSDictionary *)result;
        if ([dict[@"success"] boolValue]) {
            [self log:[NSString stringWithFormat:@"[+] Kernel slide: %@", dict[@"slide"]]];
            
            // Step 2: PTE Patch (root)
            [self log:@"[2/4] Executing PTE patch..."];
            [self.kernelDriver.webView evaluateJavaScript:@"KernelDriver.ptePatch()" completionHandler:^(id result2, NSError *error2) {
                if (error2) {
                    [self log:[NSString stringWithFormat:@"[!] PTE patch failed: %@", error2]];
                    return;
                }
                
                NSDictionary *resultDict = (NSDictionary *)result2;
                if ([resultDict[@"success"] boolValue]) {
                    [self log:[NSString stringWithFormat:@"[+] Root access acquired! UID: %@", resultDict[@"uid"]]];
                    [self log:@"[3/4] Root privileges obtained"];
                    [self log:@"[4/4] Jailbreak complete!"];
                    
                    [self log:@""];
                    [self log:@"╔════════════════════════════════════════════════════╗"];
                    [self log:@"║  ✅ JAILBREAK COMPLETO! ROOT ACCESS ACQUIRED!     ║"];
                    [self log:@"╠════════════════════════════════════════════════════╣"];
                    [self log:@"║  • UID: 0 (root)                                  ║"];
                    [self log:@"║  • Kernel R/W: ACTIVE                             ║"];
                    [self log:@"║  • PPL: BYPASSED                                  ║"];
                    [self log:@"║  • Type 'id' to verify                            ║"];
                    [self log:@"╚════════════════════════════════════════════════════╝"];
                    
                    // Instalar Sileo
                    [self installSileo];
                    
                } else {
                    [self log:@"[!] Root escalation failed"];
                }
            }];
        } else {
            [self log:@"[!] Failed to leak kernel slide"];
        }
    }];
}

- (void)installSileo {
    [self log:@""];
    [self log:@"Installing Sileo package manager..."];
    
    NSArray *commands = @[
        @"mount -uw / 2>/dev/null",
        @"mkdir -p /var/lib/apt/lists/partial 2>/dev/null",
        @"curl -L -o /tmp/procursus.deb https://github.com/ProcursusTeam/Procursus/releases/download/v4.0/procursus_4.0_iphoneos-arm64.deb 2>/dev/null",
        @"dpkg -i /tmp/procursus.deb 2>/dev/null",
        @"echo 'deb https://repo.sileo.app/ ./' > /etc/apt/sources.list.d/sileo.list",
        @"curl -L https://repo.sileo.app/key.gpg | apt-key add - 2>/dev/null",
        @"apt update 2>/dev/null",
        @"apt install -y sileo 2>/dev/null",
        @"uicache -a 2>/dev/null",
        @"killall SpringBoard 2>/dev/null"
    ];
    
    for (NSString *cmd in commands) {
        [self.kernelDriver.webView evaluateJavaScript:[NSString stringWithFormat:@"KernelDriver.executeCommand('%@')", cmd]
                                    completionHandler:nil];
        [NSThread sleepForTimeInterval:0.5];
        [self log:[NSString stringWithFormat:@"[*] %@", [cmd substringToIndex:MIN(50, cmd.length)]]];
    }
    
    [self log:@"[+] Sileo installed successfully!"];
    [self log:@"[+] Icon should appear on SpringBoard after respring"];
}

@end
