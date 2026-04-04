#import <Foundation/Foundation.h>

@interface KernelDriver : NSObject

// Primitivas de Memória
- (uint64_t)kread64:(uint64_t)addr;
- (uint32_t)kread32:(uint64_t)addr;
- (void)kwrite64:(uint64_t)addr value:(uint64_t)val;
- (void)kwrite32:(uint64_t)addr value:(uint32_t)val;

// Escalada de Privilégios
- (uint64_t)find_self_proc;
- (void)escalatePrivileges;

// Execução de Comandos
- (NSString *)executeShell:(NSString *)cmd;
- (NSString *)generateSSHKeys;
- (NSString *)executeSSHD;

@end
