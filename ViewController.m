#import "ViewController.h"
#import <WebKit/WebKit.h>
#import <mach/mach.h>
#import <spawn.h>
#import <sys/wait.h>
#import <unistd.h>
#import <string.h>
#import <errno.h>
#import <dlfcn.h>

// ============================================================
// MARK: - KernelDriver (com fallback libkernrw)
// ============================================================

extern kern_return_t mach_vm_write(vm_map_t, mach_vm_address_t, vm_offset_t, mach_msg_type_number_t);
extern kern_return_t mach_vm_read_overwrite(vm_map_t, mach_vm_address_t, mach_vm_size_t, mach_vm_address_t, mach_vm_size_t *);
extern char **environ;

// Offsets para iOS 26.4 (ajustar conforme seu dispositivo)
#define OFFSET_TASK_BSD_INFO   0x4a8
#define OFFSET_PROC_UCRED      0x138
#define OFFSET_UCRED_UID       0x20
#define OFFSET_UCRED_RUID      0x24
#define OFFSET_UCRED_SVUID     0x28
#define OFFSET_UCRED_NGROUPS   0x2c
#define OFFSET_UCRED_GROUPS    0x30
#define OFFSET_PROC_AMFI_FLAGS 0x2a0

@interface KernelDriver : NSObject
- (BOOL)isAvailable;
- (uint64_t)kread64:(uint64_t)addr;
- (void)kwrite64:(uint64_t)addr value:(uint64_t)val;
- (void)kwrite32:(uint64_t)addr value:(uint32_t)val;
- (NSString *)executeShell:(NSString *)cmd;
- (void)escalatePrivileges;
- (NSString *)generateSSHKeys;
- (NSString *)executeSSHD;
- (void)patchAMFI;
- (NSString *)getDriverInfo;
@end

@implementation KernelDriver {
    mach_port_t _tfp0;
    // libkernrw function pointers
    uint64_t (*_libkernrw_kread64)(uint64_t);
    void (*_libkernrw_kwrite64)(uint64_t, uint64_t);
    void (*_libkernrw_kwrite32)(uint64_t, uint32_t);
    BOOL _libkernrw_loaded;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _tfp0 = MACH_PORT_NULL;
        _libkernrw_loaded = NO;
        _libkernrw_kread64 = NULL;
        _libkernrw_kwrite64 = NULL;
        _libkernrw_kwrite32 = NULL;
        
        // Tenta carregar libkernrw primeiro (se disponível)
        [self loadLibKernRW];
        
        // Se não carregou, tenta task_for_pid
        if (!_libkernrw_loaded) {
            kern_return_t kr = task_for_pid(mach_task_self(), 0, &_tfp0);
            if (kr == KERN_SUCCESS && _tfp0 != MACH_PORT_NULL) {
                NSLog(@"[+] KernelDriver: tfp0 = %d", _tfp0);
            } else {
                NSLog(@"[!] KernelDriver: nenhuma primitiva de kernel disponível");
            }
        }
    }
    return self;
}

- (BOOL)loadLibKernRW {
    if (_libkernrw_loaded) return YES;
    
    // Tenta caminhos possíveis
    NSArray *paths = @[
        [[NSBundle mainBundle] pathForResource:@"libkernrw.0" ofType:@"dylib"],
        @"/usr/lib/libkernrw.0.dylib",
        @"/Library/jailbreak/libkernrw.0.dylib"
    ];
    
    void *handle = NULL;
    for (NSString *path in paths) {
        if (path && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
            handle = dlopen([path UTF8String], RTLD_LAZY);
            if (handle) break;
        }
    }
    
    if (!handle) {
        NSLog(@"[!] libkernrw.0.dylib não encontrado");
        return NO;
    }
    
    _libkernrw_kread64 = dlsym(handle, "kread64");
    _libkernrw_kwrite64 = dlsym(handle, "kwrite64");
    _libkernrw_kwrite32 = dlsym(handle, "kwrite32");
    
    if (!_libkernrw_kread64 || !_libkernrw_kwrite64 || !_libkernrw_kwrite32) {
        NSLog(@"[!] libkernrw símbolos ausentes");
        return NO;
    }
    
    _libkernrw_loaded = YES;
    NSLog(@"[+] libkernrw carregado com sucesso");
    return YES;
}

- (BOOL)isAvailable {
    return (_tfp0 != MACH_PORT_NULL) || _libkernrw_loaded;
}

- (uint64_t)kread64:(uint64_t)addr {
    if (_libkernrw_loaded && _libkernrw_kread64) {
        return _libkernrw_kread64(addr);
    }
    if (_tfp0 != MACH_PORT_NULL) {
        uint64_t val = 0;
        mach_vm_size_t outSize = 0;
        mach_vm_read_overwrite(_tfp0, (mach_vm_address_t)addr, sizeof(val), (mach_vm_address_t)&val, &outSize);
        return val;
    }
    return 0;
}

- (void)kwrite64:(uint64_t)addr value:(uint64_t)val {
    if (_libkernrw_loaded && _libkernrw_kwrite64) {
        _libkernrw_kwrite64(addr, val);
        return;
    }
    if (_tfp0 != MACH_PORT_NULL) {
        mach_vm_write(_tfp0, (mach_vm_address_t)addr, (vm_offset_t)&val, sizeof(val));
    }
}

- (void)kwrite32:(uint64_t)addr value:(uint32_t)val {
    if (_libkernrw_loaded && _libkernrw_kwrite32) {
        _libkernrw_kwrite32(addr, val);
        return;
    }
    if (_tfp0 != MACH_PORT_NULL) {
        mach_vm_write(_tfp0, (mach_vm_address_t)addr, (vm_offset_t)&val, sizeof(val));
    }
}

- (uint64_t)findSelfProc {
    uint64_t task_kaddr = [self kread64:(uint64_t)mach_task_self() + 0x28];
    if (task_kaddr == 0) return 0;
    return [self kread64:(task_kaddr + OFFSET_TASK_BSD_INFO)];
}

- (void)escalatePrivileges {
    if (![self isAvailable]) return;
    uint64_t proc = [self findSelfProc];
    if (proc == 0) { NSLog(@"[!] proc não encontrado"); return; }
    uint64_t ucred = [self kread64:(proc + OFFSET_PROC_UCRED)];
    if (ucred == 0) { NSLog(@"[!] ucred não encontrado"); return; }
    
    [self kwrite32:(ucred + OFFSET_UCRED_UID) value:0];
    [self kwrite32:(ucred + OFFSET_UCRED_RUID) value:0];
    [self kwrite32:(ucred + OFFSET_UCRED_SVUID) value:0];
    [self kwrite32:(ucred + OFFSET_UCRED_NGROUPS) value:0];
    for (int i = 0; i < 16; i++)
        [self kwrite32:(ucred + OFFSET_UCRED_GROUPS + i*4) value:0];
    setuid(0); setgid(0);
    if (getuid() == 0) NSLog(@"[+] escalatePrivileges: root");
    else NSLog(@"[!] escalate falhou, uid=%d", getuid());
}

- (void)patchAMFI {
    if (![self isAvailable]) return;
    uint64_t proc = [self findSelfProc];
    if (proc == 0) return;
    uint64_t flagsAddr = proc + OFFSET_PROC_AMFI_FLAGS;
    uint32_t flags = [self kread64:flagsAddr] & 0xFFFFFFFF;
    flags |= 0x80000000; // Exemplo: desabilita assinatura
    [self kwrite32:flagsAddr value:flags];
    NSLog(@"[+] AMFI patch aplicado");
}

- (NSString *)executeShell:(NSString *)cmd {
    pid_t pid;
    int fd[2];
    if (pipe(fd) == -1) return @"pipe failed";
    posix_spawn_file_actions_t acts;
    posix_spawn_file_actions_init(&acts);
    posix_spawn_file_actions_adddup2(&acts, fd[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&acts, fd[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&acts, fd[0]);
    const char *args[] = {"sh", "-c", [cmd UTF8String], NULL};
    setuid(0); setgid(0);
    int status = posix_spawn(&pid, "/bin/sh", &acts, NULL, (char* const*)args, environ);
    posix_spawn_file_actions_destroy(&acts);
    close(fd[1]);
    if (status == 0) {
        waitpid(pid, NULL, 0);
        char buf[4096] = {0};
        ssize_t n = read(fd[0], buf, sizeof(buf)-1);
        close(fd[0]);
        if (n > 0) return [NSString stringWithUTF8String:buf];
        return @"[Executado]";
    } else {
        close(fd[0]);
        return [NSString stringWithFormat:@"Erro %d: %s", status, strerror(status)];
    }
}

- (NSString *)generateSSHKeys {
    [self executeShell:@"mkdir -p /Library/Jailbreak/etc"];
    // Tenta usar ssh-keygen do sistema ou do bundle
    NSString *keygen = @"/usr/bin/ssh-keygen";
    if (![[NSFileManager defaultManager] fileExistsAtPath:keygen]) {
        keygen = [[NSBundle mainBundle] pathForResource:@"ssh-keygen" ofType:nil];
        if (keygen) {
            [self executeShell:[NSString stringWithFormat:@"cp \"%@\" /Library/Jailbreak/ssh-keygen", keygen]];
            [self executeShell:@"chmod 755 /Library/Jailbreak/ssh-keygen"];
            keygen = @"/Library/Jailbreak/ssh-keygen";
        } else return @"[-] ssh-keygen não encontrado";
    }
    NSString *cmd = [NSString stringWithFormat:@"\"%@\" -t rsa -f /Library/Jailbreak/etc/ssh_host_rsa_key -N ''", keygen];
    [self executeShell:cmd];
    if ([[NSFileManager defaultManager] fileExistsAtPath:@"/Library/Jailbreak/etc/ssh_host_rsa_key"])
        return @"[+] Chaves geradas";
    return @"[-] Falha ao gerar chaves";
}

- (NSString *)executeSSHD {
    [self generateSSHKeys];
    NSString *sshd = @"/usr/sbin/sshd";
    if (![[NSFileManager defaultManager] fileExistsAtPath:sshd]) {
        sshd = [[NSBundle mainBundle] pathForResource:@"sshd" ofType:nil];
        if (sshd) {
            [self executeShell:[NSString stringWithFormat:@"cp \"%@\" /Library/Jailbreak/sshd", sshd]];
            [self executeShell:@"chmod 755 /Library/Jailbreak/sshd"];
            sshd = @"/Library/Jailbreak/sshd";
        } else return @"[-] sshd não encontrado";
    }
    pid_t pid;
    const char *args[] = {[sshd UTF8String], "-p", "2222", "-P", "/tmp/sshd.pid", "-f", "/Library/Jailbreak/etc/sshd_config", NULL};
    setuid(0); setgid(0);
    int status = posix_spawn(&pid, [sshd UTF8String], NULL, NULL, (char* const*)args, environ);
    if (status == 0) return [NSString stringWithFormat:@"[+] sshd rodando na porta 2222, PID: %d", pid];
    return [NSString stringWithFormat:@"[-] Erro %d: %s", status, strerror(status)];
}

- (NSString *)getDriverInfo {
    if (_libkernrw_loaded) {
        return @"Driver: libkernrw (kernel read/write via exploit)\nStatus: ATIVO";
    } else if (_tfp0 != MACH_PORT_NULL) {
        return [NSString stringWithFormat:@"Driver: task_for_pid (tfp0=%d)\nStatus: ATIVO", _tfp0];
    } else {
        return @"Driver: NENHUM\nStatus: INATIVO – sem primitivas de kernel";
    }
}

@end

// ============================================================
// MARK: - ViewController (WebKit + bridge)
// ============================================================

@interface ViewController () <WKScriptMessageHandler>
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) KernelDriver *driver;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.driver = [[KernelDriver alloc] init];
    
    // Configura WebView
    WKUserContentController *ucc = [[WKUserContentController alloc] init];
    [ucc addScriptMessageHandler:self name:@"A13_LAB"];
    
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.userContentController = ucc;
    
    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:config];
    [self.view addSubview:self.webView];
    
    // Carrega HTML embutido
    NSString *html = [self embeddedHTML];
    [self.webView loadHTMLString:html baseURL:nil];
}

- (NSString *)embeddedHTML {
    return @"<!DOCTYPE html>"
    "<html><head><meta name='viewport' content='width=device-width, initial-scale=1.0'>"
    "<style>body{background:#000;color:#0f0;font-family:monospace;margin:0;padding:10px;display:flex;flex-direction:column;height:100vh;}#log{flex:1;border:1px solid #0f0;overflow-y:auto;padding:5px;font-size:12px;background:#050505;}.buttons{display:flex;gap:5px;margin-bottom:10px;}button{background:#0f0;color:#000;border:none;padding:8px;font-weight:bold;flex:1;}.input-line{display:flex;background:#111;border:1px solid #0f0;padding:8px;}input{flex:1;background:transparent;border:none;color:#fff;outline:none;font-size:14px;}</style>"
    "<body><div class='buttons'>"
    "<button onclick='sendAction(\"shell\",\"amfi\")'>PATCH AMFI</button>"
    "<button onclick='sendAction(\"shell\",\"keygen\")'>GEN KEYS</button>"
    "<button onclick='sendAction(\"shell\",\"sshd\")'>START SSH</button>"
    "<button onclick='sendAction(\"driver_info\",\"\")'>INFO DRIVER</button>"
    "</div><div id='log'>[*] iOS 26.4 Security Research Terminal<br></div>"
    "<div class='input-line'><span style='margin-right:5px'>root#</span>"
    "<input type='text' id='cmd' autofocus></div>"
    "<script>function log(msg,type){let l=document.getElementById('log');l.innerHTML+=`<span style='color:${type==='success'?'#0f0':'#f00'}'> > ${msg}</span><br>`;l.scrollTop=l.scrollHeight;}"
    "function sendAction(action,payload,addr,val){if(window.webkit&&window.webkit.messageHandlers.A13_LAB){window.webkit.messageHandlers.A13_LAB.postMessage({action:action,payload:payload,addr:addr||'',val:val||''});}else{log('Bridge not found','err');}}"
    "document.getElementById('cmd').addEventListener('keyup',(e)=>{if(e.key==='Enter'){let cmd=e.target.value;if(cmd){log(`<b style='color:white'># ${cmd}</b>`,'none');sendAction('shell',cmd);e.target.value='';}}});"
    "window.log = log;"
    "</script></body></html>";
}

#pragma mark - WKScriptMessageHandler

- (void)userContentController:(WKUserContentController *)ucc didReceiveScriptMessage:(WKScriptMessage *)message {
    NSDictionary *data = message.body;
    NSString *action = data[@"action"];
    NSString *payload = data[@"payload"];
    __block NSString *output = @"";
    
    if ([action isEqualToString:@"kwrite"]) {
        uint64_t addr = strtoull([data[@"addr"] UTF8String], NULL, 0);
        uint64_t val = strtoull([data[@"val"] UTF8String], NULL, 0);
        [self.driver kwrite64:addr value:val];
        output = [NSString stringWithFormat:@"[kwrite] 0x%llx <- 0x%llx", addr, val];
    }
    else if ([action isEqualToString:@"shell"]) {
        [self.driver escalatePrivileges];
        if ([payload isEqualToString:@"keygen"]) {
            output = [self.driver generateSSHKeys];
        } else if ([payload isEqualToString:@"sshd"]) {
            output = [self.driver executeSSHD];
        } else if ([payload isEqualToString:@"amfi"]) {
            [self.driver patchAMFI];
            output = @"[AMFI] patch aplicado";
        } else {
            output = [self.driver executeShell:payload];
        }
    }
    else if ([action isEqualToString:@"driver_info"]) {
        output = [self.driver getDriverInfo];
    }
    else {
        output = @"Ação desconhecida";
    }
    
    // Escapa caracteres especiais para JavaScript
    NSString *clean = [output stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    clean = [clean stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
    clean = [clean stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
    NSString *js = [NSString stringWithFormat:@"log('%@', 'success');", clean];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.webView evaluateJavaScript:js completionHandler:^(id result, NSError *error) {
            if (error) NSLog(@"JS error: %@", error);
        }];
    });
}

#pragma mark - Métodos opcionais (para compatibilidade com ViewController.h)

- (void)log:(NSString *)message {
    [self userContentController:nil didReceiveScriptMessage:({
        WKScriptMessage *msg = [WKScriptMessage new];
        [msg setValue:@{@"action": @"shell", @"payload": message} forKey:@"body"];
        msg;
    })];
}

- (void)executeCommand {
    [self log:@"executeCommand chamado (placeholder)"];
}

- (void)runExploit {
    [self log:@"runExploit chamado (placeholder)"];
}

@end
