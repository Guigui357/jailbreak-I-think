#import "KernelDriver.h"
#import <mach/mach.h>
#import <unistd.h>

#define KERN_BASE_STATIC 0xFFFFFFF007004000
#define PAGE_SIZE_A13 0x4000

@implementation KernelBridge

// 1. LEITURA ULTRA-SEGURA
- (uint64_t)kread64:(uint64_t)addr {
    uint64_t val = 0;
    vm_size_t size = sizeof(uint64_t);
    
    // Tentativa de leitura física
    kern_return_t kr = vm_read_overwrite(mach_task_self(), (vm_address_t)addr, size, (vm_address_t)&val, &size);
    
    if (kr != KERN_SUCCESS) {
        return 0xDEADBEEF; // Sandbox bloqueou
    }
    return val;
}

// 2. BUSCA DE SLIDE (Com limite de tempo para não crashar)
- (uint64_t)getKernelSlide {
    // Varredura menor (0x5000 iterações) para teste de estabilidade
    for (uint64_t i = 0; i < 0x5000; i++) {
        uint64_t addr = KERN_BASE_STATIC + (i * PAGE_SIZE_A13);
        uint64_t val = [self kread64:addr];
        
        if (val == 0xDEADBEEF) return 0; // Para se a sandbox barrar

        if ((uint32_t)(val & 0xFFFFFFFF) == 0xfeedfacf) {
            return (i * PAGE_SIZE_A13);
        }
    }
    return 0;
}

// 3. PONTE COM JAVASCRIPT (ASSÍNCRONA)
- (void)userContentController:(WKUserContentController *)userContentController 
      didReceiveScriptMessage:(WKScriptMessage *)message 
                 replyHandler:(void (^)(id _Nullable, NSString * _Nullable))replyHandler {
    
    NSDictionary *body = message.body;
    NSString *action = body[@"action"];

    // O SEGREDO: Rodar o exploit em uma fila separada para não travar a UI
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        
        if ([action isEqualToString:@"scan"]) {
            uint64_t slide = [self getKernelSlide];
            
            // Devolve a resposta para o thread principal e para o JS
            dispatch_async(dispatch_get_main_queue(), ^{
                if (slide > 0) {
                    replyHandler(@{@"value": [NSString stringWithFormat:@"0x%llx", slide]}, nil);
                } else {
                    replyHandler(@{@"value": @"SANDBOX_BLOCK_OR_NOT_FOUND"}, nil);
                }
            });
        } 
        else if ([action isEqualToString:@"root"]) {
            setuid(0);
            NSString *res = (getuid() == 0) ? @"ROOT_SUCCESS" : @"FAILED";
            dispatch_async(dispatch_get_main_queue(), ^{
                replyHandler(@{@"status": res}, nil);
            });
        }
        else {
            dispatch_async(dispatch_get_main_queue(), ^{
                replyHandler(@{@"error": @"unknown"}, nil);
            });
        }
    });
}

@end
