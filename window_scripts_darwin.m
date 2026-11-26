//go:build darwin && cgo && !nogui

#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>

static WKWebView *sciWindowWebView(NSView *view) {
    if ([view isKindOfClass:WKWebView.class]) return (WKWebView *)view;
    for (NSView *child in view.subviews) {
        WKWebView *found = sciWindowWebView(child);
        if (found) return found;
    }
    return nil;
}

// Called on the AppKit main queue with the specific Wails window. Inspect
// its actual loaded URL; never search other app windows for a matching page.
void sciEvaluateWindowScript(void *window, const char *origin, const char *script) {
    if (!window || !origin || !script || !NSThread.isMainThread) return;
    WKWebView *web = sciWindowWebView(((__bridge NSWindow *)window).contentView);
    NSURL *current = web.URL;
    NSURL *trusted = [NSURL URLWithString:[NSString stringWithUTF8String:origin]];
    if (!current || ![current.scheme isEqualToString:@"http"] ||
        ![current.host isEqualToString:trusted.host] ||
        ![current.port isEqualToNumber:trusted.port] || current.user || current.password) return;
    NSString *source = [NSString stringWithUTF8String:script];
    if (source) [web evaluateJavaScript:source completionHandler:nil];
}
