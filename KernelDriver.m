#import "KernelDriver.h"
#import <mach/mach.h>

// Definições para evitar erros de declaração
typedef uint64_t mach_vm_address_t;
extern kern_return_t mach_vm_map(vm_map_t, mach_vm_address_t *, mach_vm_size_t, mach_vm_address_t, int, mach_port_t, memory_object_offset_t, boolean_t, vm_prot_t, vm_prot_t, vm_inherit_t);

@implementation KernelDriver {
    uint64_t _kernelSlide;
    uint64_t _kernelBase;
}

// Primitiva com verificação de pânico
- (uint64_t)kread64:(uint64_t)addr {
    // 1. Verificação de Alinhamento: Endereços de Kernel DEVEM ser múltiplos de 8
    if (addr < 0xFFFFFFF000000000ULL || (addr % 8) != 0) return 0;

    int fds[2];
    if (pipe(fds) != 0) return 0;

    uint64_t val = 0;
    // Usamos um sinalizador para evitar que o kernel tente ler endereço inválido
    // Se o write falhar, ele não crasha o app, apenas retorna -1
    if (write(fds[1], (void *)addr, 8) == 8) {
        read(fds[0], &val, 8);
    }

    close(fds[0]); close(fds[1]);
    return val;
}

- (BOOL)escalateToRoot {
    @try {
        [self logToWeb:@"🛡️ Verificando estabilidade do Kernel..."];
        
        // Obter Slide de forma segura
        _kernelSlide = [self getKernelSlideReal];
        if (_kernelSlide == 0 || _kernelSlide % 0x4000 != 0) {
            [self logToWeb:@"❌ Slide inválido ou desalinhado. Abortando."];
            return NO;
        }

        _kernelBase = 0xFFFFFFF007004000ULL + _kernelSlide;
        
        // TESTE CRÍTICO: Se ler 0 aqui, o Sandbox barrou. 
        // Não tente buscar PIDs se o Magic for 0, ou vai crashar no próximo passo.
        uint32_t magic = (uint32_t)([self kread64:_kernelBase] & 0xFFFFFFFF);
        if (magic != 0xfeedfacf) {
            [self logToWeb:[NSString stringWithFormat:@"⚠️ Sandbox Ativo (Magic: 0x%x). O kread falhou.", magic]];
            return NO; 
        }

        [self logToWeb:@"✅ Leitura estável. Iniciando busca de privilégios..."];
        
        // ... (restante da lógica de busca de PID e Root) ...
        
    } @catch (NSException *e) {
        [self logToWeb:[NSString stringWithFormat:@"🚨 Crash evitado: %@", e.reason]];
    }
    return NO;
}

- (uint64_t)getKernelSlideReal {
    task_dyld_info_data_t info;
    mach_msg_type_number_t cnt = TASK_DYLD_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_DYLD_INFO, (task_info_t)&info, &cnt) == 0) {
        uint64_t addr = info.all_image_info_addr;
        if (addr > 0xFFFFFFF000000000ULL) return addr - 0xFFFFFFF007004000ULL;
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
