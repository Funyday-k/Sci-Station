// Exercises the launch layer tree offscreen; no desktop screenshot or screen permission is used.
#import "../native_launch_darwin.m"
#import <math.h>

static unsigned int shownID;
static int showCalls, splashCloseCalls;

// Stand in for the Wails callback so this test runs without a WKWebView.
void sciShowLaunchWindow(unsigned int windowID) {
    shownID = windowID;
    showCalls++;
}

@interface ClosingSplash : NSWindow
@end
@implementation ClosingSplash
- (void)close {
    splashCloseCalls++;
    [super close];
}
@end

static void require(BOOL value, NSString *message) {
    if (!value) {
        fprintf(stderr, "%s\n", message.UTF8String);
        exit(1);
    }
}
static BOOL closeEnough(CGFloat a, CGFloat b) { return fabs(a-b) < 0.001; }
int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSRect frame = NSMakeRect(0, 0, 620, 360);
        SciLiquidLaunchView *view = [[SciLiquidLaunchView alloc] initWithFrame:frame];
        NSWindow *window = [[NSWindow alloc] initWithContentRect:frame styleMask:NSWindowStyleMaskBorderless
                                                        backing:NSBackingStoreBuffered defer:YES];
        window.contentView = view;
        NSArray<CALayer *> *layers = view.subviews.lastObject.layer.sublayers;
        CAGradientLayer *tint = (CAGradientLayer *)layers.firstObject;
        CABasicAnimation *bounds = (CABasicAnimation *)[tint animationForKey:@"bounds"];
        CABasicAnimation *radius = (CABasicAnimation *)[tint animationForKey:@"cornerRadius"];
        require(bounds != nil && closeEnough(bounds.duration, .86), @"missing panel morph");
        require(closeEnough([(NSValue *)bounds.fromValue rectValue].size.width, 132), @"start width");
        require(closeEnough([(NSValue *)bounds.toValue rectValue].size.width, 508.4), @"end width");
        require(closeEnough([(NSValue *)bounds.toValue rectValue].size.height, 172), @"end height");
        require(closeEnough([radius.fromValue doubleValue], 66) && closeEnough([radius.toValue doubleValue], 28), @"corner radius");
        NSVisualEffectView *material = view.subviews.firstObject.subviews.firstObject;
        require(material.material == NSVisualEffectMaterialPopover &&
                material.blendingMode == NSVisualEffectBlendingModeBehindWindow, @"native popover material");
        CGFloat previous = 0;
        int titles = 0;
        for (CALayer *layer in layers) {
            if (![layer isKindOfClass:CATextLayer.class]) continue;
            CATextLayer *title = (CATextLayer *)layer;
            CABasicAnimation *opacity = (CABasicAnimation *)[title animationForKey:@"opacity"];
            require([title.string isEqualToString:@"Sci-Station"] && closeEnough(title.fontSize, 70), @"title");
            require(closeEnough(opacity.duration, .5), @"title fade");
            if (titles) require(fabs(opacity.beginTime - previous - .045) < .01, @"stagger delay");
            previous = opacity.beginTime;
            ++titles;
        }
        require(titles == 3, @"three title layers");
        sciLaunchReady((__bridge void *)window, 41);
        require(!sciFinished && !window.visible, @"main window must wait for the full launch interval");
        sciMain = nil;
        sciMinimumElapsed = YES;
        sciRevealIfReady();
        require(!sciFinished && showCalls == 0, @"ready and timer are independent gates");
        sciSplash = [[ClosingSplash alloc] initWithContentRect:frame styleMask:NSWindowStyleMaskBorderless
                                                       backing:NSBackingStoreBuffered defer:YES];
        sciSplash.releasedWhenClosed = NO;
        sciLaunchReady((__bridge void *)window, 41);
        sciLaunchReady((__bridge void *)window, 41);
        require(sciFinished && showCalls == 1 && shownID == 41, @"reveal the Wails window exactly once");
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
        while (!splashCloseCalls && [deadline timeIntervalSinceNow] > 0) {
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
        }
        require(splashCloseCalls == 1 && !sciSplash && !sciMain, @"the splash must close and release its window");
    }
    return 0;
}
