#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

@interface ViewController : UIViewController

// Definimos a webView aqui para que possamos acessá-la no .m
@property (nonatomic, strong) WKWebView *webView;

@end
