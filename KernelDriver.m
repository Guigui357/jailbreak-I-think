#import "KernelDriver.h"
#import <CommonCrypto/CommonDigest.h>
#import <mach/mach.h>
#import <mach/mach_host.h>
#import <mach/host_special_ports.h>
#include <sys/wait.h>
#include <unistd.h>
#include <spawn.h>

@implementation KernelBridge {
    mach_port_t g_host_priv;
}

// 1. PREPARAÇÃO DA PORTA DE HOST
- (void)prepareHostPriv {
    if (MACH_PORT_VALID(g_host_priv)) return;
    
    // Tenta obter a porta privilegiada do host
    kern_return_t kr = host_get_host_priv_port(mach_host_self(), &g_host_priv);
    
    if (kr != KERN_SUCCESS) {
        NSLog(@"[!] Erro host_priv: %d (Sandbox Ativa)", kr);
    }
}

// 2. LEITURA DE KERNEL (VERSÃO COMPATÍVEL COM A13/iOS 18+)
- (uint64_t)kread64:(uint64_t)addr {
    [self prepareHostPriv];
    if (!MACH_PORT_VALID(g_host_priv)) return 0xDEADBEEF;

    uint64_t val = 0;
    vm_size_t size = sizeof(uint64_t);
    
    /* 
       Usamos vm_read_overwrite em vez de vm_map. 
       É mais aceito pelo compilador e menos propenso a conflitos de tipos.
    */
    kern_return_t kr = vm_read_overwrite(mach_task_self(), (vm_address_t)addr, size, (vm_address_t)&val, &size);
    
    if (kr != KERN_SUCCESS) {
        return 0xDEADBEEF; 
    }
    return val;
}

// 3. ESCRITA DE KERNEL (kwrite64)
- (void)kwrite64:(uint64_t)addr value:(uint64_t)val {
    [self prepareHostPriv];
    if (!MACH_PORT_VALID(g_host_priv)) return;

    vm_size_t size = sizeof(uint64_t);
    // Nota: Escrever no kernel via Userland exige bypass de PPL no A13
    kern_return_t kr = vm_write(mach_task_self(), (vm_address_t)addr, (vm_offset_t)&val, (mach_msg_type_number_t)size);
    
    if (kr != KERN_SUCCESS) {
        NSLog(@"[!] Erro de Escrita: %d (PPL Block)", kr);
    }
}

// 4. LÓGICA DE INJEÇÃO E SPAWN DO SSHD
- (void)launchSshdFinal {
    NSString *sshdPath = [[NSBundle mainBundle] pathForResource:@"sshd" ofType:nil];
    if (!sshdPath) return;

    // Calcula Hash e Injeta (Simulado para o Lab)
    NSData *sshdData = [NSData dataWithContentsOfFile:sshdPath];
    uint8_t hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(sshdData.bytes, (CC_LONG)sshdData.length, hash);

    pid_t pid;
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    
    // Flag 0x4000: Tenta elevar para Platform Binary
    posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETPGROUP | 0x4000);

    char *const args[] = {(char *)[sshdPath UTF8String], "-p", "2222", "-D", NULL};
    extern char **environ;

    int status = posix_spawn(&pid, [sshdPath UTF8String], NULL, &attr, args, environ);
    
    if (status == 0) {
        NSLog(@"🚀 SSHD Spawned! PID: %d", pid);
    } else {
        NSLog(@"❌ Erro Spawn: %d", status);
    }
    posix_spawnattr_destroy(&attr);
}

// 5. HANDLER PARA O JAVASCRIPT (WKWebView)
- (void)userContentController:(WKUserContentController *)userContentController 
      didReceiveScriptMessage:(WKScriptMessage *)message 
                 replyHandler:(void (^)(id _Nullable, NSString * _Nullable))replyHandler {
    
    NSDictionary *body = message.body;
    NSString *action = body[@"action"];
    
    if ([action isEqualToString:@"read64"]) {
        NSString *addrHex = body[@"address"];
        uint64_t addr = strtoull([addrHex UTF8String], NULL, 16);
        uint64_t val = [self kread64:addr];
        replyHandler(@{@"value": [NSString stringWithFormat:@"%llu", val]}, nil);
    } 
    else if ([action isEqualToString:@"launch_sshd"]) {
        [self launchSshdFinal];
        replyHandler(@{@"status": @"online"}, nil);
    }
}

@end
