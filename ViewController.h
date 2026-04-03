//
//  ViewController.h
//  JailbreakApp
//

#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

@interface ViewController : UIViewController

@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) UITextView *consoleView;
@property (nonatomic, strong) UITextField *commandField;

- (void)log:(NSString *)message;
- (void)executeCommand;
- (void)runExploit;

@end
