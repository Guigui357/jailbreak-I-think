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
- (void)executeShell:(NSString *)cmd {
    pid_t pid;
    // O comando é passado via /bin/sh para aceitar pipes e redirecionamentos
    const char *args[] = {"sh", "-c", [cmd UTF8String], NULL};
    
    // Elevando privilégios antes do spawn
    setuid(0);
    setgid(0);
    
    int status = posix_spawn(&pid, "/bin/sh", NULL, NULL, (char* const*)args, environ);
    
    if (status == 0) {
        NSLog(@"[Spawn] Processo iniciado: %d", pid);
        waitpid(pid, &status, 0); // Aguarda o comando terminar
        NSLog(@"[Spawn] Processo finalizado");
    } else {
        NSLog(@"[Spawn] Erro ao executar: %s", strerror(status));
    }
}
@end
