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
    posix_spawn_file_actions_addclose(&actions, pipefd[0]);

    const char *args[] = {"sh", "-c", [cmd UTF8String], NULL};
    setuid(0);

    if (posix_spawn(&pid, "/bin/sh", &actions, NULL, (char* const*)args, environ) == 0) {
        close(pipefd[1]);
        waitpid(pid, NULL, 0);
        char buffer[1024];
        ssize_t n = read(pipefd[0], buffer, sizeof(buffer)-1);
        close(pipefd[0]);
        if (n > 0) {
            buffer[n] = '\0';
            return [NSString stringWithUTF8String:buffer];
        }
    }
    return @"[OK]";
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

- (NSString *)executeSSHD {
    NSString *bin = [self prepareSSHDEnvironment];
    pid_t pid;
    const char *args[] = {[bin UTF8String], "-p", "2222", "-R", "-E", NULL};
    setuid(0);
    if (posix_spawn(&pid, [bin UTF8String], NULL, NULL, (char* const*)args, environ) == 0) {
        return [NSString stringWithFormat:@"[+] SSHD PID: %d", pid];
    }
    return @"[-] SSHD Fail";
}

@end
