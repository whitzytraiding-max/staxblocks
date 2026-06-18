// CleanExit.m — STAX
// Godot 4.x crashes on iOS termination tearing down GDScript lambdas
// (applicationWillTerminate -> Main::cleanup -> ~UpdatableFuncPtr mutex -> SIGABRT),
// logging a crash report every close. App is terminating anyway and state is saved
// eagerly during play, so swizzle applicationWillTerminate: to exit cleanly.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <stdlib.h>

@interface StaxCleanExit : NSObject
@end
@implementation StaxCleanExit
+ (void)load {
    Class cls = NSClassFromString(@"GDTApplicationDelegate");
    if (cls == Nil) { return; }
    SEL sel = @selector(applicationWillTerminate:);
    IMP cleanExit = imp_implementationWithBlock(^(id _self, UIApplication *app) { _Exit(0); });
    Method m = class_getInstanceMethod(cls, sel);
    if (m != NULL) { method_setImplementation(m, cleanExit); }
    else { class_addMethod(cls, sel, cleanExit, "v@:@"); }
}
@end
