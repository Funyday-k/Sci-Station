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
static BOOL isSplash(NSWindow *window) {
    return [window.contentView isKindOfClass:NSClassFromString(@"SciLiquidLaunchView")];
}

static BOOL isWorkstation(NSWindow *window) {
    return ![window isKindOfClass:NSPanel.class] && [window standardWindowButton:NSWindowCloseButton] != nil;
}

// Position only windows in this dedicated test executable. The first screen
// is the menu-bar display even when another display currently has focus.
static void placeWindow(NSWindow *window, NSScreen *screen) {
    if (window.screen == screen) return;
    NSRect area = screen.visibleFrame;
    NSRect frame = window.frame;
    frame.origin = NSMakePoint(NSMidX(area) - NSWidth(frame)/2, NSMidY(area) - NSHeight(frame)/2);
    [window setFrame:frame display:YES];
}

static void checkWindow(NSString *gesture, int retries) {
    BOOL launching = [gesture isEqualToString:@"launch-q"];
    BOOL picking = [gesture isEqualToString:@"picker-q"];
    NSArray<NSScreen *> *screens = NSScreen.screens;
    const char *requested = getenv("SCI_STATION_TEST_DISPLAY");
    BOOL preferSecondary = !requested || strcmp(requested, "primary") != 0;
    NSScreen *display = screens.count > 1 && preferSecondary ? screens[1] : screens.firstObject;
    NSWindow *window = nil;
    for (NSWindow *candidate in NSApp.windows) {
        if (!candidate.visible || (!isSplash(candidate) && !isWorkstation(candidate))) continue;
        if (display) placeWindow(candidate, display);
        if (launching ? isSplash(candidate) : (isWorkstation(candidate) && candidate.alphaValue >= .999)) {
            window = candidate;
        }
    }
    if (!launching && window && !window.keyWindow && !window.attachedSheet) {
        [NSApp activateIgnoringOtherApps:YES];
        [window makeKeyAndOrderFront:nil];
        if (!window.keyWindow) window = nil;
    }
    NSString *marker = [NSString stringWithUTF8String:getenv("SCI_STATION_TEST_GESTURE_MARKER")];
    NSFileManager *files = NSFileManager.defaultManager;
    if (window) {
        NSString *ready = [marker stringByAppendingString:@".ready"];
        if (![files fileExistsAtPath:ready]) [files createFileAtPath:ready contents:nil attributes:nil];
    }
    if (!window || (picking && !window.attachedSheet) ||
        ![files fileExistsAtPath:[marker stringByAppendingString:@".go"]]) {
        if (retries == 0) {
            fprintf(stderr, "No matching window, sheet, or test driver signal for %s\n", gesture.UTF8String);
            exit(3);
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            checkWindow(gesture, retries - 1);
        });
        return;
    }
    if (![gesture writeToFile:marker atomically:YES encoding:NSUTF8StringEncoding error:NULL]) {
        fprintf(stderr, "Failed to record the native gesture\n");
        exit(5);
    }
    NSUInteger index = [screens indexOfObject:window.screen];
    if (index == NSNotFound || window.screen != display) {
        fprintf(stderr, "The test window is not on its selected display\n");
        exit(6);
    }
    fprintf(stderr, "Invoking %s on screen %lu/%lu\n", gesture.UTF8String,
            (unsigned long)index + 1, (unsigned long)screens.count);
    if ([gesture isEqualToString:@"red"]) {
        NSButton *close = [window standardWindowButton:NSWindowCloseButton];
        if (!close.enabled) exit(4);
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
        checkWindow([NSString stringWithUTF8String:name], 900);
    });
}
#endif
