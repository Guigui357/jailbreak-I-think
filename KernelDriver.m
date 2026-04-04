#import "KernelDriver.h"
#import <spawn.h>
#import <sys/wait.h>
#import <unistd.h>

extern char **environ;

@implementation KernelDriver {
    mach_port_t _tfp0;
}

- (instancetype)init {
    if (self = [super init]) {
        task_for_pid(mach_task_self(), 0, &_tfp0);
    }
    return self;
}

// 1. Mover o binário para fora do Bundle (Bypass Sandbox)
- (NSString *)prepareSSHDEnvironment {
    NSString *bundlePath = [[NSBundle mainBundle] pathForResource:@"sshd" ofType:nil];
    if (!bundlePath) return @"[-] Erro: sshd não encontrado no Bundle.";

    // Caminho no RootFS (Liberado pelo seu Remount RW)
    NSString *targetPath = @"/Library/Jailbreak/sshd";
    
    // Comandos Root para mover e dar permissão
    [self executeShell:[NSString stringWithFormat:@"cp %@ %@", bundlePath, targetPath]];
    [self executeShell:[NSString stringWithFormat:@"chmod 755 %@", targetPath]];
    [self executeShell:@"mkdir -p /Library/Jailbreak/etc"];
    
    return targetPath;
}

// 2. Inicializador do SSHD (Dropbear) - Versão Estável
- (NSString *)executeSSHD {
    // Passo A: Migra o binário para o RootFS
    NSString *realSshdPath = [self prepareSSHDEnvironment];
    if ([realSshdPath hasPrefix:@"[-]"]) return realSshdPath;

    pid_t pid;
    // Argumentos Ajustados:
    // -F: Não rodar em background (ajuda o spawn a não dar erro 1)
    // -p 2222: Porta customizada
    // -P /tmp/dropbear.pid: Local de escrita do PID
    // -r: Chaves de host
    const char *args[] = {
        [realSshdPath UTF8String], 
        "-p", "2222", 
        "-P", "/tmp/dropbear.pid",
        "-r", "/Library/Jailbreak/etc/dropbear_rsa_host_key",
        "-r", "/Library/Jailbreak/etc/dropbear_ecdsa_host_key",
        "-E", "-R", NULL
    };

    setuid(0);
    setgid(0);

    // O Pulo do Gato: posix_spawn direto do RootFS
    int status = posix_spawn(&pid, [realSshdPath UTF8String], NULL, NULL, (char* const*)args, environ);

    if (status == 0) {
        // Desacopla o processo para ele não morrer quando o app fechar
        return [NSString stringWithFormat:@"[+] SSHD ONLINE! PID: %d (Porta 2222)", pid];
    } else {
        return [NSString stringWithFormat:@"[-] Erro %d: %s. Tente 'Remount RW' primeiro.", status, strerror(status)];
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
