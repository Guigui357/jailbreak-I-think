#import "KernelDriver.h"
#import <mach/mach.h>
#import <unistd.h>
#import <spawn.h>
#import <sys/wait.h>

extern kern_return_t mach_vm_write(vm_map_t, mach_vm_address_t, vm_offset_t, mach_msg_type_number_t);
extern char **environ;

@implementation KernelDriver {
    mach_port_t _tfp0;
    uint64_t _kbase;
}

- (instancetype)init {
    if (self = [super init]) {
        _tfp0 = MACH_PORT_NULL;
        task_for_pid(mach_task_self(), 0, &_tfp0);
        _kbase = 0xfffffff007004000ULL;
    }
    return self;
}

- (void)kwrite64:(uint64_t)addr value:(uint64_t)val {
    if (mach_vm_write(_tfp0, addr, (vm_offset_t)&val, 8) == KERN_SUCCESS) {
        NSLog(@"[Kernel] Escrita OK: 0x%llx", addr);
    }
}

// IMPLEMENTAÇÃO REAL COM POSIX_SPAWN
- (NSString *)executeShell:(NSString *)cmd {
    pid_t pid;
    int pipefd[2];
    pipe(pipefd); // Cria um cano para ler a saída

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, pipefd[1], STDOUT_FILENO); // Redireciona a saída

    const char *args[] = {"sh", "-c", [cmd UTF8String], NULL};
    extern char **environ;

    setuid(0);
    if (posix_spawn(&pid, "/bin/sh", &actions, NULL, (char* const*)args, environ) == 0) {
        waitpid(pid, NULL, 0);
        close(pipefd[1]);
        
        char buffer[1024];
        ssize_t bytesRead = read(pipefd[0], buffer, sizeof(buffer)-1);
        buffer[bytesRead] = '\0';
        close(pipefd[0]);
        return [NSString stringWithUTF8String:buffer];
    }
    return @"Erro no spawn";
}

@end
