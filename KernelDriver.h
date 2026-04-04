#import <Foundation/Foundation.h>

@interface KernelDriver : NSObject
- (void)kwrite64:(uint64_t)addr value:(uint64_t)val;
- (void)executeShell:(NSString *)cmd;
@end
