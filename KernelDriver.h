#import <Foundation/Foundation.h>

@interface KernelDriver : NSObject

// Primitiva de escrita física (Bypass PPL/AMCC)
- (void)kwrite64:(uint64_t)addr value:(uint64_t)val;

// Executa comandos genéricos do sistema via posix_spawn
- (NSString *)executeShell:(NSString *)cmd;

// Geração de chaves de Host para o Dropbear (RSA/ECDSA)
- (NSString *)generateSSHKeys;

// Inicializa o daemon SSHD (Dropbear) na porta 2222
- (NSString *)executeSSHD;

@end
