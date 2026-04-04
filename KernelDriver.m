#import "KernelDriver.h"
#import <spawn.h>
#import <sys/wait.h>

// Importante para acessar as variáveis de ambiente do sistema
extern char **environ;

- (NSString *)executeSSHD {
    // 1. Localiza o binário 'sshd' que você colocou no Bundle via GitHub Actions
    NSString *sshdPath = [[NSBundle mainBundle] pathForResource:@"sshd" ofType:nil];
    
    if (!sshdPath) {
        return @"[!] Erro: Binário sshd não encontrado no Bundle.";
    }

    pid_t pid;
    // 2. Argumentos: -p 2222 (Porta alta), -R (Gerar chaves se não existirem), -E (Log no stderr)
    // Usamos porta 2222 porque a 22 é bloqueada pelo sistema para apps
    const char *args[] = {[sshdPath UTF8String], "-p", "2222", "-R", "-E", NULL};

    // 3. Elevação de Privilégios (UID 0) via TFP0
    setuid(0);
    setgid(0);

    // 4. Execução via posix_spawn
    // O AMFI Patch que fizemos antes permite que este binário rode mesmo sem assinatura
    int status = posix_spawn(&pid, [sshdPath UTF8String], NULL, NULL, (char* const*)args, environ);

    if (status == 0) {
        return [NSString stringWithFormat:@"[+] SSHD Iniciado! PID: %d na porta 2222", pid];
    } else {
        return [NSString stringWithFormat:@"[-] Falha no spawn: %s", strerror(status)];
    }
}
