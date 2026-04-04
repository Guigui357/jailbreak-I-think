#import "KernelDriver.h"
#import <mach/mach.h>
#import <spawn.h>
#import <sys/wait.h>
#import <unistd.h>

// Definição necessária para o compilador
extern kern_return_t mach_vm_write(vm_map_t, mach_vm_address_t, vm_offset_t, mach_msg_type_number_t);
extern char **environ;

@implementation KernelDriver {
    mach_port_t _tfp0;
}

- (instancetype)init {
    if (self = [super init]) {
        _tfp0 = MACH_PORT_NULL;
        // Obtém a porta de tarefa do kernel
        task_for_pid(mach_task_self(), 0, &_tfp0);
    }
    return self;
}

- (void)kwrite64:(uint64_t)addr value:(uint64_t)val {
    mach_vm_write(_tfp0, (mach_vm_address_t)addr, (vm_offset_t)&val, 8);
}

- (NSString *)executeShell:(NSString *)cmd {
    pid_t pid;
    int pipefd[2];
    pipe(pipefd);

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, pipefd[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, pipefd[1], STDERR_FILENO);

    const char *args[] = {"sh", "-c", [cmd UTF8String], NULL};
    extern char **environ;

    // FORÇAR ROOT VIA TFP0 NA TASK ATUAL
    setuid(0); 
    setgid(0);

    // Tentativa de Spawn
    int status = posix_spawn(&pid, "/bin/sh", &actions, NULL, (char* const*)args, environ);
    
    if (status == 0) {
        close(pipefd[1]);
        waitpid(pid, NULL, 0);
        
        char buffer[1024];
        ssize_t n = read(pipefd[0], buffer, sizeof(buffer)-1);
        close(pipefd[0]);
        
        if (n > 0) {
            buffer[n] = '\0';
            return [NSString stringWithUTF8String:buffer];
        }
        return @"[Executado]";
    }
    
    // Se der erro, retornamos o código do erro UNIX para depurar
    return [NSString stringWithFormat:@"[!] Erro no Spawn: %d (%s)", status, strerror(status)];
}



- (NSString *)prepareSSHDEnvironment {
    NSString *bundlePath = [[NSBundle mainBundle] pathForResource:@"sshd" ofType:nil];
    NSString *targetPath = @"/Library/Jailbreak/sshd";
    [self executeShell:[NSString stringWithFormat:@"cp %@ %@", bundlePath, targetPath]];
    [self executeShell:[NSString stringWithFormat:@"chmod 755 %@", targetPath]];
    return targetPath;
}

- (NSString *)generateSSHKeys {
    [self executeShell:@"mkdir -p /Library/Jailbreak/etc"];
    NSString *bin = [self prepareSSHDEnvironment];
    [self executeShell:[NSString stringWithFormat:@"%@ -t rsa -f /Library/Jailbreak/etc/dropbear_rsa_host_key", bin]];
    return @"[+] Keys Generated";
}

- (void)escalatePrivileges {
    // 1. Localiza o endereço do seu próprio processo (struct proc)
    // No iOS 26.4, o offset do 'self_proc' costuma ser 0x470 na struct task
    uint64_t self_proc = [self find_self_proc]; 
    
    // 2. Localiza a struct de credenciais (ucred)
    // Offset ucred no iOS 26.4: 0x110 ou 0x120
    uint64_t ucred = [self kread64:(self_proc + 0x110)]; 
    
    NSLog(@"[*] Corrompendo ucred em 0x%llx", ucred);

    // 3. Sobrescreve UID, GID, RUID, RGID para 0 (ROOT)
    [self kwrite32:(ucred + 0x18) value:0]; // cr_uid
    [self kwrite32:(ucred + 0x1c) value:0]; // cr_ruid
    [self kwrite32:(ucred + 0x20) value:0]; // cr_svuid
    [self kwrite32:(ucred + 0x24) value:0]; // cr_ngroups
    [self kwrite32:(ucred + 0x28) value:0]; // cr_groups[0]

    NSLog(@"[+] Privilégios elevados via Kernel Write.");
}

- (NSString *)executeSSHD {
    // 1. Caminho do binário no Bundle e no Alvo (RootFS)
    NSString *bundlePath = [[NSBundle mainBundle] pathForResource:@"sshd" ofType:nil];
    NSString *rootfsPath = @"/Library/Jailbreak/sshd";
    
    // 2. Mover o binário para fora da Sandbox (Bypass EPERM)
    [self executeShell:[NSString stringWithFormat:@"cp %@ %@", bundlePath, rootfsPath]];
    [self executeShell:[NSString stringWithFormat:@"chmod 755 %@", rootfsPath]];
    [self executeShell:@"mkdir -p /Library/Jailbreak/etc"];

    pid_t pid;
    // 3. Argumentos Críticos:
    // -i: Executar em modo inetd (evita alguns checks de daemon)
    // -p 2222: Porta alta
    // -P /tmp/sshd.pid: Caminho de escrita permitido
    const char *args[] = {
        [rootfsPath UTF8String], 
        "-p", "2222", 
        "-P", "/tmp/sshd.pid",
        "-r", "/Library/Jailbreak/etc/dropbear_rsa_host_key",
        "-E", "-R", NULL
    };

    setuid(0); // Garante UID 0 antes do spawn
    setgid(0);

    // 4. Spawn do binário migrado
    int status = posix_spawn(&pid, [rootfsPath UTF8String], NULL, NULL, (char* const*)args, environ);

    if (status == 0) {
        return [NSString stringWithFormat:@"[+] SSHD MIGRADO E ATIVO! PID: %d", pid];
    } else {
        return [NSString stringWithFormat:@"[-] Erro %d: %s. Tente 'Remount RW' novamente.", status, strerror(status)];
    }
}

@end
