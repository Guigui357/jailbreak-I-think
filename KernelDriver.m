#import "KernelDriver.h"
#import <mach/mach.h>
#import <unistd.h>

// Definições para o compilador (A13 / iOS 26.4)
#ifndef KERNEL_BASE_STATIC
#define KERNEL_BASE_STATIC 0xFFFFFFF007004000
#endif
#ifndef PAGE_SIZE_A13
#define PAGE_SIZE_A13 0x4000
#endif

@implementation KernelBridge

// 1. LEITURA SEGURA (Retorna DEADBEEF em vez de crashar no Sandbox)
- (uint64_t)kread64:(uint64_t)addr {
    uint64_t val = 0;
    vm_size_t size = sizeof(uint64_t);
    kern_return_t kr = vm_read_overwrite(mach_task_self(), (vm_address_t)addr, size, (vm_address_t)&val, &size);
    return (kr == KERN_SUCCESS) ? val : 0xDEADBEEF;
}

// 2. BUSCA DO KERNEL SLIDE (KASLR)
- (uint64_t)getKernelSlide {
    for (uint64_t i = 0; i < 0x5000; i++) {
        uint64_t addr = KERNEL_BASE_STATIC + (i * PAGE_SIZE_A13);
        uint32_t magic = (uint32_t)([self kread64:addr] & 0xFFFFFFFF);
        if (magic == 0xfeedfacf) return (i * PAGE_SIZE_A13);
    }
    return 0;
}

// 3. HANDLER DA PONTE (Onde o JS se conecta)
- (void)userContentController:(WKUserContentController *)userContentController 
      didReceiveScriptMessage:(WKScriptMessage *)message 
                 replyHandler:(void (^)(id _Nullable, NSString * _Nullable))replyHandler {
    
    NSDictionary *body = message.body;
    NSString *action = body[@"action"];

    // IMPORTANTE: Executar em background para o botão do HTML não "travar"
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        
        id response = nil;

        // AÇÃO 1: TESTE DE CONEXÃO (Resolve o erro "A ponte falhou")
        if ([action isEqualToString:@"test_bridge"]) {
            response = @{@"status": @"SUCCESS", @"info": @"Ponte Nativa OK!"};
        } 
        
        // AÇÃO 2: SCAN DE KERNEL (PTE PATCH)
        else if ([action isEqualToString:@"pte_patch"]) {
            uint64_t slide = [self getKernelSlide];
            if (slide > 0) {
                response = @{@"status": @"SUCCESS", @"slide": [NSString stringWithFormat:@"0x%llx", slide]};
            } else {
                response = @{@"status": @"SANDBOX_LOCK", @"info": @"Leitura negada pelo Kernel."};
            }
        } 
        
        else {
            response = @{@"status": @"UNKNOWN_ACTION"};
        }

        // Devolve a resposta para o Thread Principal (WebKit exige isso)
        dispatch_async(dispatch_get_main_queue(), ^{
            replyHandler(response, nil);
        });
    });
}

@end
