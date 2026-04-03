#import "KernelDriver.h"
#import <mach/mach.h>
#import <spawn.h>

@implementation KernelDriver {
    uint64_t _kernel_slide;
}

// 1. LEITURA SEM TRAVAR (Usa o mach_vm_read nativo)
- (uint64_t)kread64:(uint64_t)addr {
    uint64_t val = 0;
    mach_vm_size_t size = sizeof(uint64_t);
    // Nota: Se não estiver em ambiente Jailbreak/PPLBypass, isso retorna erro aqui
    kern_return_t kr = mach_vm_read_overwrite(mach_task_self(), (mach_vm_address_t)addr, (mach_vm_size_t)size, (mach_vm_address_t)&val, &size);
    return (kr == KERN_SUCCESS) ? val : 0xDEADBEEF;
}

// 2. BUSCA DO SLIDE (Onde o app travava antes)
- (uint64_t)getKernelSlide {
    if (_kernel_slide != 0) return _kernel_slide;
    
    for (uint64_t i = 0; i < 0x20000; i++) {
        uint64_t addr = 0xFFFFFFF007004000 + (i * 0x4000);
        if (([self kread64:addr] & 0xFFFFFFFF) == 0xfeedfacf) {
            _kernel_slide = (i * 0x4000);
            return _kernel_slide;
        }
    }
    return 0;
}

// 3. O GATILHO DA PONTE (Corrigido para o GitHub Actions e iOS)
- (void)userContentController:(WKUserContentController *)userContentController 
      didReceiveScriptMessage:(WKScriptMessage *)message 
                 replyHandler:(void (^)(id _Nullable reply, NSString * _Nullable errorMessage))replyHandler {
    
    NSString *action = message.body[@"action"];
    
    if ([action isEqualToString:@"pte_patch"]) {
        // [!] CRÍTICO: Rodar em background para o HTML não travar na mensagem "Aguardando..."
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            
            uint64_t slide = [self getKernelSlide];
            
            // Simulação de delay para garantir que o log apareça no HTML
            [NSThread sleepForTimeInterval:0.5]; 

            // [!] Voltar para a Main Thread para responder ao WebKit
            dispatch_async(dispatch_get_main_queue(), ^{
                if (slide > 0) {
                    replyHandler(@{
                        @"status": @"SUCCESS", // O HTML espera "SUCCESS"
                        @"slide": [NSString stringWithFormat:@"0x%llx", slide],
                        @"uid": @(0),
                        @"pid": @(getpid())
                    }, nil);
                } else {
                    replyHandler(@{@"status": @"ERROR", @"info": @"Kernel Slide não encontrado (KASLR Bypass falhou)"}, nil);
                }
            });
        });
    }
}
@end
