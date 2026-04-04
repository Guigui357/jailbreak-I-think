#import "KernelDriver.h"
#import <mach/mach.h>
#import <unistd.h>

// Definição externa necessária para o compilador
extern kern_return_t mach_vm_write(vm_map_t, mach_vm_address_t, vm_offset_t, mach_msg_type_number_t);

@implementation KernelDriver {
    mach_port_t _tfp0;
    uint64_t _kbase;
}

- (instancetype)init {
    if (self = [super init]) {
        _tfp0 = MACH_PORT_NULL;
        task_for_pid(mach_task_self(), 0, &_tfp0);
        _kbase = 0xfffffff007004000ULL; // Corrigido: ULL em vez de 'n'
    }
    return self;
}

- (void)kwrite64:(uint64_t)addr value:(uint64_t)val {
    if (mach_vm_write(_tfp0, addr, (vm_offset_t)&val, 8) == KERN_SUCCESS) {
        NSLog(@"[Kernel] Escrita OK em 0x%llx", addr);
    }
}

- (void)executeShell:(NSString *)cmd {
    setuid(0);
    setgid(0);
    system([cmd UTF8String]);
}
@end
