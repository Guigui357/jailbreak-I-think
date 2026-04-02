#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import <mach/mach.h>

/**
 * DEFINIÇÕES DE ARQUITETURA ARM64e (A13)
 * O alinhamento de 16KB é crítico. Qualquer tentativa de leitura/escrita 
 * fora desse alinhamento em áreas sensíveis resultará em Kernel Panic.
 */
#define PAGE_SIZE_A13 0x4000
#define PAGE_MASK_A13 ~(PAGE_SIZE_A13 - 1)
#define KERNEL_BASE_STATIC 0xFFFFFFF007004000

@interface KernelBridge : NSObject <WKScriptMessageHandlerWithReply>

/**
 * g_host_priv: A porta privilegiada do host. 
 * É a "chave mestra" necessária para que vm_read_overwrite e vm_write funcionem.
 */
@property (nonatomic, assign) mach_port_t g_host_priv;

/**
 * webView: Referência fraca para a interface, permitindo que o driver 
 * envie logs de volta para o console HTML se necessário.
 */
@property (nonatomic, weak) WKWebView *webView;


// --- PRIMITIVAS DE ACESSO AO KERNEL ---

/**
 * Tenta capturar a host_priv_port. No iOS 26.4, isso exige 
 * que o processo já tenha escapado do Sandbox de usuário.
 */
- (void)prepareHostPriv;

/**
 * kread64: Lê 8 bytes (uint64_t) de um endereço arbitrário do kernel.
 */
- (uint64_t)kread64:(uint64_t)addr;

/**
 * kwrite64: Escreve 8 bytes no kernel. 
 * Nota: No A13, escritas em TrustCache ou tabelas de página exigem PPL Bypass.
 */
- (void)kwrite64:(uint64_t)addr value:(uint64_t)val;

/**
 * getKernelSlide: Varre a memória em busca do Magic Number Mach-O (0xfeedfacf)
 * para calcular o deslocamento do KASLR nesta sessão.
 */
- (uint64_t)getKernelSlide;


// --- OPERAÇÕES DE PÓS-EXPLOIT (SSHD) ---

/**
 * injectToTrustCache: Localiza a cadeia de confiança do Kernel e insere 
 * o CDHash do binário sshd para autorizar sua execução.
 */
- (void)injectToTrustCache:(NSString *)path;

/**
 * launchSshdFinal: Realiza o spawn do processo SSHD com privilégios 
 * de plataforma (CS_PLATFORM_BINARY / 0x4000).
 */
- (void)launchSshdFinal;

@end
