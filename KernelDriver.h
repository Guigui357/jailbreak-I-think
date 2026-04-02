#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

#define ARM_TTE_PTE_MASK            0x0000FFFFFFFFF000ULL
#define ARM_PTE_AP_RO               (1ULL << 6)   // Bit de Read-Only
#define ARM_PTE_NX                  (1ULL << 54)  // Execute Never
#define ARM_PTE_PNX                 (1ULL << 53)  // Privileged Execute Never

@interface KernelBridge : NSObject <WKScriptMessageHandlerWithReply>
- (uint64_t)kread64:(uint64_t)addr;
- (void)kwrite64:(uint64_t)addr value:(uint64_t)val;
- (uint64_t)get_pte_for_address:(uint64_t)vaddr;
- (void)patch_pte_make_writable:(uint64_t)vaddr;
@end
