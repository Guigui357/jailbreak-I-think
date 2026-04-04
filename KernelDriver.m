#import "KernelDriver.h"
#import <mach/mach.h>
#import <spawn.h>
#import <sys/wait.h>

extern kern_return_t mach_vm_write(vm_map_t, mach_vm_address_t, vm_offset_t, mach_msg_type_number_t);
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

- (void)kwrite64:(uint64_t)addr value:(uint64_t)val {
    mach_vm_write(_tfp0, addr, (vm_offset_t)&val, 8);
}

- (NSString *)executeShell:(NSString *)cmd {
    pid_t pid;
    int pipedes[2];
    pipe(pipedes); // Cria a ponte de comunicação

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, pipedes[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, pipedes[1], STDERR_FILENO);

    const char *args[] = {"sh", "-c", [cmd UTF8String], NULL};
    
    setuid(0); // Força Root via TFP0
    if (posix_spawn(&pid, "/bin/sh", &actions, NULL, (char* const*)args, environ) == 0) {
        close(pipedes[1]);
        waitpid(pid, NULL, 0);
        
        char buffer[1024];
        ssize_t n = read(pipedes[0], buffer, sizeof(buffer)-1);
        close(pipedes[0]);
        if (n > 0) {
            buffer[n] = '\0';
            return [NSString stringWithUTF8String:buffer];
        }
    }
    return @"[Comando executado]";
}
@end
