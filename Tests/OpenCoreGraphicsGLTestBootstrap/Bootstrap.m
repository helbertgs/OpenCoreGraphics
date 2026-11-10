#if defined(__APPLE__)
#import <AppKit/AppKit.h>
#include <stdlib.h>
#include <string.h>

/// Stops the initial AppKit launch loop before Swift Testing starts its async main.
@interface OCGTestBootstrapDelegate : NSObject <NSApplicationDelegate>
@end

@implementation OCGTestBootstrapDelegate
/// Stops the launch loop and posts an event so the loop wakes up.
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp stop:nil];
    NSEvent *event = [NSEvent otherEventWithType:NSEventTypeApplicationDefined
                                        location:NSZeroPoint
                                   modifierFlags:0
                                       timestamp:0
                                    windowNumber:0
                                         context:nil
                                         subtype:0
                                           data1:0
                                           data2:0];
    [NSApp postEvent:event atStart:YES];
}
@end

/// Launches AppKit only in opt-in graphics tests and only before the test runner starts.
__attribute__((constructor)) static void OCGPrepareAppKitForGraphicsTests(void) {
    const char *enabled = getenv("OPENCOREGRAPHICS_RUN_GL_COMPARISON");
    if (enabled == NULL || strcmp(enabled, "1") != 0) {
        return;
    }

    @autoreleasepool {
        NSApplication *application = [NSApplication sharedApplication];
        if ([[NSRunningApplication currentApplication] isFinishedLaunching]) {
            return;
        }
        id<NSApplicationDelegate> previousDelegate = [application delegate];
        OCGTestBootstrapDelegate *delegate = [OCGTestBootstrapDelegate new];
        [application setDelegate:delegate];
        [application run];
        [application setDelegate:previousDelegate];
    }
}
#endif
