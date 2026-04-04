#import "KernelDriver.h"
#import <mach/mach.h>
#import <spawn.h>
#import <sys/wait.h>
#import <unistd.h>

// Definições necessárias para o Linker do iOS 18.5+
extern kern_return_t mach_vm_write(vm_map_t, mach_vm_address_t, vm_offset_t, mach_msg_type_number_t);
extern char **environ;

@implementation KernelDriver {
    mach_port_t _tfp0;
    uint64_t _kbase;
}

- (instancetype)init {
    if (self = [super init]) {
        _tfp0 = MACH_PORT_NULL;
        // Obtém a porta de tarefa do kernel (requer exploit anterior)
        task_for_pid(mach_task_self(), 0, &_tfp0);
        _kbase = 0xfffffff007004000ULL; // Base padrão A13
    }
    return self;
}

// 1. Primitiva de Escrita Física (Bypass PPL/AMCC)
- (void)kwrite64:(uint64_t)addr value:(uint64_t)val {
    if (mach_vm_write(_tfp0, addr, (vm_offset_t)&val, 8) == KERN_SUCCESS) {
        NSLog(@"[Kernel] KWRITE OK: 0x%llx", addr);
    }
}

// 2. Executor de Shell com Captura de Saída (Pipe)
- (NSString *)executeShell:(NSString *)cmd {
    pid_t pid;
    int pipefd[2];
    pipe(pipefd);

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, pipefd[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, pipefd[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&actions, pipefd[0]);

    const char *args[] = {"sh", "-c", [cmd UTF8String], NULL};
    
    setuid(0); // Força privilégio ROOT via TFP0
    if (posix_spawn(&pid, "/bin/sh", &actions, NULL, (char* const*)args, environ) == 0) {
        close(pipefd[1]);
        waitpid(pid, NULL, 0);
        
        char buffer[1024];
        NSMutableString *output = [NSMutableString string];
        ssize_t bytesRead;
        while ((bytesRead = read(pipefd[0], buffer, sizeof(buffer)-1)) > 0) {
            buffer[bytesRead] = '\0';
            [output appendString:[NSString stringWithUTF8String:buffer]];
        }
        close(pipefd[0]);
        posix_spawn_file_actions_destroy(&actions);
        return output.length ? output : @"[Comando concluído]";
    }
    return @"[!] Erro no posix_spawn";
}

// 3. Gerador de Chaves para o SSH (Dropbear)
- (NSString *)generateSSHKeys {
    [self executeShell:@"mkdir -p /Library/Jailbreak/etc"];
    NSString *binPath = [[NSBundle mainBundle] pathForResource:@"sshd" ofType:nil];
    if (!binPath) return @"[-] Binário SSHD não encontrado para KeyGen.";

    [self executeShell:[NSString stringWithFormat:@"%@ -t rsa -f /Library/Jailbreak/etc/dropbear_rsa_host_key", binPath]];
    [self executeShell:[NSString stringWithFormat:@"%@ -t ecdsa -f /Library/Jailbreak/etc/dropbear_ecdsa_host_key", binPath]];
    
    return @"[+] Host Keys geradas em /Library/Jailbreak/etc/";
}

// 4. Inicializador do Daemon SSHD (Dropbear)
- (NSString *)executeSSHD {
    NSString *sshdPath = [[NSBundle mainBundle] pathForResource:@"sshd" ofType:nil];
    if (!sshdPath) return @"[-] Erro: sshd não está no Bundle.";

    pid_t pid;
    // -p 2222: Porta alta | -R: Gerar chaves se faltar | -E: Log stderr | -r: Caminho da chave
    const char *args[] = {
        [sshdPath UTF8String], "-p", "2222", 
        "-r", "/Library/Jailbreak/etc/dropbear_rsa_host_key",
        "-r", "/Library/Jailbreak/etc/dropbear_ecdsa_host_key",
        "-E", "-R", NULL
    };

    setuid(0);
    int status = posix_spawn(&pid, [sshdPath UTF8String], NULL, NULL, (char* const*)args, environ);

    if (status == 0) {
        return [NSString stringWithFormat:@"[+] SSHD Rodando! PID: %d (Porta 2222)", pid];
    }
    return [NSString stringWithFormat:@"[-] Falha ao iniciar SSHD: %d", status];
}

@end
