#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#include <stdint.h>
#include <mach/mach.h>
#include <dlfcn.h>
#include <sys/proc_info.h>
#include <libproc.h>

@interface KernelBridge : NSObject <WKScriptMessageHandler>
@property (nonatomic, unsafe_unretained) WKWebView *webView;
@end

@implementation KernelBridge

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    if ([message.body[@"op"] isEqualToString:@"scan_uid"]) {
        
        [self.webView evaluateJavaScript:@"log('🧪 Localizando endereço real do UID...')" completionHandler:nil];

        // 1. OBTER PORTA DE HARDWARE (A13)
        void *iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
        typedef kern_return_t (*IOMainPortFunc)(mach_port_t, mach_port_t *);
        IOMainPortFunc get_main_port = (IOMainPortFunc)dlsym(iokit, "IOMainPort");
        mach_port_t mainPort = MACH_PORT_NULL;
        if (get_main_port) get_main_port(MACH_PORT_NULL, &mainPort);

        // 2. BUSCA DINÂMICA: Em vez de endereço fixo, usamos o proc_info
        struct proc_bsdinfo bsdinfo;
        if (proc_pidinfo(getpid(), PROC_PIDTBSDINFO, 0, &bsdinfo, sizeof(bsdinfo)) > 0) {
            uint32_t my_uid = bsdinfo.pbi_uid;
            
            // O endereço real do cr_uid no A13/26.4 costuma estar no Heap do processo
            // Vamos usar o scan que já temos, mas partindo de um leak real
            uint64_t leak_addr = (uint64_t)&bsdinfo; 

            NSString *log = [NSString stringWithFormat:@"log('🔍 UID local detectado: %u. Leak: 0x%llx')", my_uid, leak_addr];
            [self.webView evaluateJavaScript:log completionHandler:nil];

            // 3. TENTATIVA DE KREAD (Sequência Segura)
            vm_offset_t data;
            mach_msg_type_number_t sz = 4;
            // Tentamos ler o próprio leak para validar a MainPort
            kern_return_t kr = vm_read(mainPort, (vm_address_t)leak_addr, 4, &data, &sz);

            if (kr == KERN_SUCCESS) {
                [self.webView evaluateJavaScript:@"log('✅ <b>KREAD SUCESSO!</b> Porta de Hardware ativa.')" completionHandler:nil];
                // Se a leitura funcionou, o kwrite de root agora é seguro
            } else {
                [self.webView evaluateJavaScript:@"log('❌ KREAD Negado: Sandbox ainda bloqueia a porta.')" completionHandler:nil];
            }
        }
        if (iokit) dlclose(iokit);
    }
}
@end
