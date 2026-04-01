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
        uint64_t current_addr = strtoull([data[@"start_addr"] UTF8String], NULL, 16);
        uint32_t range = [data[@"range"] unsignedIntValue];
        
        // Target: UID 501 (usuário padrão iOS)
        uint32_t target_uid = 501;
        BOOL found = NO;

        task_t kernel_task;
        task_for_pid(mach_task_self(), 0, &kernel_task);

        for (uint32_t i = 0; i < range; i += 4) {
            uint64_t check_addr = current_addr + i;
            vm_offset_t data_ptr;
            mach_msg_type_number_t sz = 4;
            
            // Leitura segura (Não crasha se falhar)
            if (vm_read(kernel_task, (vm_address_t)check_addr, 4, &data_ptr, &sz) == KERN_SUCCESS) {
                uint32_t val = *(uint32_t *)data_ptr;
                if (val == target_uid) {
                    NSString *js = [NSString stringWithFormat:@"log('🎯 <b>ENCONTRADO!</b> UID 501 em: <span class=\"addr\">0x%llX</span>')", check_addr];
                    [self.webView evaluateJavaScript:js completionHandler:nil];
                    found = YES;
                    break;
                }
                vm_deallocate(mach_task_self(), data_ptr, sz);
            }
        }

        if (!found) {
            [self.webView evaluateJavaScript:@"log('❌ UID 501 não localizado nesta faixa.')" completionHandler:nil];
        }
    }
}
@end
