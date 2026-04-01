#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#include <stdint.h>
#include <mach/mach.h>
#include <dlfcn.h>

@implementation KernelBridge

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    NSDictionary *data = message.body;
    
    if ([data[@"op"] isEqualToString:@"scan_uid"]) {
        [self.webView evaluateJavaScript:@"log('⚡ Iniciando Scan Inteligente (A13)...')" completionHandler:nil];

        void *iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
        typedef kern_return_t (*IOMainPortFunc)(mach_port_t, mach_port_t *);
        IOMainPortFunc get_main_port = (IOMainPortFunc)dlsym(iokit, "IOMainPort");
        mach_port_t mainPort;
        get_main_port(MACH_PORT_NULL, &mainPort);

        uint64_t addr = 0xfffffff007004000ULL; 
        int found = 0;

        // Varredura segura: Verificamos a região antes de ler
        for (int i = 0; i < 500; i++) { // Testa 500 blocos de memória
            vm_size_t size = 0;
            vm_region_basic_info_data_64_t info;
            mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
            mach_port_t object_name;

            // 1. Verifica se a região de memória permite LEITURA
            kern_return_t kr = vm_region_64(mainPort, (vm_address_t *)&addr, &size, VM_REGION_BASIC_INFO_64, (uintptr_t)&info, &count, &object_name);
            
            if (kr == KERN_SUCCESS && (info.protection & VM_PROT_READ)) {
                // 2. Se for legível, buscamos o UID 501
                for (uint64_t j = 0; j < size; j += 4) {
                    vm_offset_t read_data;
                    mach_msg_type_number_t sz = 4;
                    if (vm_read(mainPort, addr + j, 4, &read_data, &sz) == KERN_SUCCESS) {
                        if (*(uint32_t *)read_data == 501) {
                            NSString *msg = [NSString stringWithFormat:@"log('🎯 <b>ACHADO!</b> Endereço: 0x%llX')", addr + j];
                            [self.webView evaluateJavaScript:msg completionHandler:nil];
                            found = 1; break;
                        }
                    }
                }
            }
            if (found) break;
            addr += size; // Pula para a próxima região se não achou
        }
        if (!found) [self.webView evaluateJavaScript:@"log('⚠️ Varredura limpa. UID não encontrado.')" completionHandler:nil];
        dlclose(iokit);
    }
}
@end
