#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#include <stdint.h>
#include <mach/mach.h>

@interface KernelBridge : NSObject <WKScriptMessageHandler>
@property (nonatomic, unsafe_unretained) WKWebView *webView;
@end

@implementation KernelBridge

- (void)userContentController:(WKUserContentController *)userContentController 
      didReceiveScriptMessage:(WKScriptMessage *)message {
    
    NSDictionary *data = message.body;
    NSString *op = data[@"op"];
    
    if ([op isEqualToString:@"scan_uid"]) {
        uint64_t start_addr = strtoull([data[@"start_addr"] UTF8String], NULL, 16);
        
        task_t kernel_task;
        // Tenta obter a porta do kernel
        kern_return_t kr = task_for_pid(mach_task_self(), 0, &kernel_task);
        
        if (kr != KERN_SUCCESS) {
            // SE CHEGAR AQUI, O FEATHER/APP NÃO TEM PERMISSÃO DE KERNEL
            NSString *err = [NSString stringWithFormat:@"log('❌ ERRO: task_for_pid falhou (%d). App sem privilégios de Kernel.')", kr];
            [self.webView evaluateJavaScript:err completionHandler:nil];
            return;
        }

        [self.webView evaluateJavaScript:@"log('⏳ Porta do Kernel obtida! Iniciando leitura...')" completionHandler:nil];

        // Loop de busca (1MB)
        for (int i = 0; i < 0x100000; i += 4) {
            uint64_t addr = start_addr + i;
            vm_offset_t data_ptr;
            mach_msg_type_number_t sz = 4;
            
            if (vm_read(kernel_task, (vm_address_t)addr, 4, &data_ptr, &sz) == KERN_SUCCESS) {
                uint32_t val = *(uint32_t *)data_ptr;
                if (val == 501) {
                    NSString *res = [NSString stringWithFormat:@"log('🎯 ENCONTRADO UID 501 em: 0x%llX')", addr];
                    [self.webView evaluateJavaScript:res completionHandler:nil];
                    return;
                }
            }
        }
        [self.webView evaluateJavaScript:@"log('⚠️ Scan finalizado: UID não encontrado nesta faixa.')" completionHandler:nil];
    }
}
@end
