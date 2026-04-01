#import <UIKit/UIKit.h>
#import "ViewController.h"

// Interface simples para o ApplicationDelegate dentro do próprio main
@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

@implementation AppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    ViewController *vc = [[ViewController alloc] init];
    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];
    return YES;
}
@end

int main(int argc, char * argv[]) {
    @autoreleasepool {
        // Inicializa o app usando a classe AppDelegate definida acima
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
