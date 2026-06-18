// WebAuth.m — STAX in-app sign-in (no external browser, no code paste)
// Bridges Godot's Auth.gd to ASWebAuthenticationSession via two files in Documents/:
//   _webauth_req.txt  (Godot writes the authorize URL)  -> we present the in-app sheet
//   _webauth_res.txt  (we write the stax://auth?code=... callback) -> Godot reads it
#import <UIKit/UIKit.h>
#import <AuthenticationServices/AuthenticationServices.h>

@interface StaxWebAuth : NSObject <ASWebAuthenticationPresentationContextProviding>
@property(nonatomic, strong) ASWebAuthenticationSession *session;
@end

static StaxWebAuth *gStaxWebAuth = nil;

@implementation StaxWebAuth

+ (NSString *)reqPath { return [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/_webauth_req.txt"]; }
+ (NSString *)resPath { return [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/_webauth_res.txt"]; }

- (ASPresentationAnchor)presentationAnchorForWebAuthenticationSession:(ASWebAuthenticationSession *)session {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene *ws = (UIWindowScene *)scene;
            for (UIWindow *w in ws.windows) { if (w.isKeyWindow) return w; }
            if (ws.windows.count) return ws.windows.firstObject;
        }
    }
    return UIApplication.sharedApplication.windows.firstObject;
}

- (void)start:(NSString *)urlStr {
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) return;
    self.session = [[ASWebAuthenticationSession alloc] initWithURL:url
        callbackURLScheme:@"stax"
        completionHandler:^(NSURL *callbackURL, NSError *error) {
            NSString *out = callbackURL ? callbackURL.absoluteString : @"ERR";
            [out writeToFile:[StaxWebAuth resPath] atomically:YES encoding:NSUTF8StringEncoding error:nil];
            self.session = nil;
        }];
    self.session.presentationContextProvider = self;
    self.session.prefersEphemeralWebBrowserSession = NO;
    [self.session start];
}

+ (void)load {
    dispatch_async(dispatch_get_main_queue(), ^{
        gStaxWebAuth = [StaxWebAuth new];
        [NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *t) {
            NSFileManager *fm = [NSFileManager defaultManager];
            NSString *req = [StaxWebAuth reqPath];
            if (![fm fileExistsAtPath:req]) return;
            NSString *url = [NSString stringWithContentsOfFile:req encoding:NSUTF8StringEncoding error:nil];
            [fm removeItemAtPath:req error:nil];
            if (url.length == 0) return;
            [gStaxWebAuth start:[url stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
        }];
    });
}
@end
