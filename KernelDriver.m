#import "KernelDriver.h"
#import <mach/mach.h>

@implementation KernelBridge

// 1. LEITURA SEGURA (Anti-Freeze)
- (uint64_t)kread64:(uint64_t)addr {
    uint64_t val = 0;
    vm_size_t size = sizeof(uint64_t);
    // Tenta ler, mas não deixa o app travar se falhar
    kern_return_t kr = vm_read_overwrite(mach_task_self(), (vm_address_t)addr, size, (vm_address_t)&val, &size);
    if (kr != KERN_SUCCESS) return 0xDEADBEEF;
    return val;
}

// 2. OBRIGATÓRIO: Handler que SEMPRE responde ao JS
- (void)userContentController:(WKUserContentController *)userContentController 
      didReceiveScriptMessage:(WKScriptMessage *)message 
                 replyHandler:(void (^)(id _Nullable, NSString * _Nullable))replyHandler {
    
    // Captura a ação vinda do HTML
    NSString *action = message.body[@"action"];
    
    // EXTREMAMENTE IMPORTANTE: Executar em background para não travar a UI
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        
        id response = nil;
        
        if ([action isEqualToString:@"pte_patch"]) {
            // Tenta o scan do kernel antes do patch
            uint64_t slide = 0;
            for (uint64_t i = 0; i < 0x5000; i++) {
                uint64_t addr = 0xFFFFFFF007004000 + (i * 0x4000);
                if ((uint32_t)([self kread64:addr] & 0xFFFFFFFF) == 0xfeedfacf) {
                    slide = i * 0x4000;
                    break;
                }
            }
            
            if (slide > 0) {
                response = @{@"status": @"SUCCESS", @"slide": [NSString stringWithFormat:@"0x%llx", slide]};
            } else {
                response = @{@"status": @"SANDBOX_LOCK", @"info": @"O iOS impediu a leitura da memória."};
            }
        } else {
            response = @{@"status": @"UNKNOWN_CMD"};
        }

        // Volta para a Main Thread para entregar a resposta ao WebKit
        dispatch_async(dispatch_get_main_queue(), ^{
            replyHandler(response, nil);
        });
    });
}

@end
