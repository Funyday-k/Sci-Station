// Linked only into the CI smoke executable. AppKit delivers the gesture within
// the test process, so it never needs Accessibility access to other apps.
#import <AppKit/AppKit.h>
#include <stdlib.h>

#ifdef SCI_REQUEST_QUIT
int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc != 2) return 2;
        NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:atoi(argv[1])];
        return app.finishedLaunching && [app terminate] ? 0 : 1;
    }
}
#else
static void checkWindow(NSString *gesture, int retries) {
    NSWindow *window = NSApp.keyWindow;
    NSButton *close = [window standardWindowButton:NSWindowCloseButton];
    if (!window.visible || !close || window.alphaValue < 0.999) {
        if (retries == 0) {
            fprintf(stderr, "No visible main window after the launch animation\n");
            exit(3);
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            checkWindow(gesture, retries - 1);
        });
        return;
    }
    NSString *marker = [NSString stringWithUTF8String:getenv("SCI_STATION_TEST_GESTURE_MARKER")];
    if (![gesture writeToFile:marker atomically:YES encoding:NSUTF8StringEncoding error:NULL]) {
        fprintf(stderr, "Failed to record the native gesture\n");
        exit(5);
    }
    fprintf(stderr, "Invoking native gesture: %s\n", gesture.UTF8String);
    if ([gesture isEqualToString:@"red"]) {
        [close performClick:nil];
        return;
    }
    BOOL closeWindow = [gesture isEqualToString:@"cmd-w"];
    NSString *key = closeWindow ? @"w" : @"q";
    NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
        modifierFlags:NSEventModifierFlagCommand timestamp:0 windowNumber:window.windowNumber context:nil
        characters:key charactersIgnoringModifiers:key isARepeat:NO keyCode:closeWindow ? 13 : 12];
    if (![NSApp.mainMenu performKeyEquivalent:event]) {
        fprintf(stderr, "Missing native menu shortcut %s\n", key.UTF8String);
        exit(4);
    }
}
__attribute__((constructor)) static void armGesture(void) {
    const char *name = getenv("SCI_STATION_TEST_GESTURE");
    if (name == NULL || getenv("SCI_STATION_TEST_GESTURE_MARKER") == NULL) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        checkWindow([NSString stringWithUTF8String:name], 200);
    });
}
#endif
