#ifndef KernelDriver_h
#define KernelDriver_h

#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#include <mach/mach.h>
#include <spawn.h>

// --- OFFSETS E FLAGS iOS 26.4 (A13) ---
#define KERNEL_BASE             0xfffffff007004000
#define OFF_TRUSTCACHE_CHAIN    0x24F8010  // Offset para a TrustChain no iOS 26.4
#define OFF_PROC_UCRED          0x100
#define OFF_UCRED_CR_UID        0x18
#define POSIX_SPAWN_FOR_SANDBOX 0x4000

// --- ESTRUTURA DO TRUSTCACHE ---
struct trustcache_entry {
    uint8_t cdhash[20];
    uint8_t flags;
} __attribute__((packed));

struct trustcache_page {
    uint32_t version;
    uint32_t entry_count;
    struct trustcache_entry entries[0];
};

@interface KernelBridge : NSObject <WKScriptMessageHandler>

@property (nonatomic, strong) WKWebView *webView;

// Métodos de Log e Kernel
- (void)log:(NSString *)text;
- (uint64_t)getKernelBase;
- (uint64_t)getKernelSlide;
- (void)kwrite64:(uint64_t)addr value:(uint64_t)val;
- (uint64_t)kread64:(uint64_t)addr;

// Métodos de Exploit
- (void)injectToTrustCache:(NSString *)path;
- (void)launchSshdFinal;

@end

#endif /* KernelDriver_h */
