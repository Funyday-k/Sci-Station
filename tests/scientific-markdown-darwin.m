#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>

@interface ScientificFixture : NSObject <WKScriptMessageHandler, WKNavigationDelegate>
@property(nonatomic) BOOL completed;
@property(nonatomic, copy) NSString *failure;
@end

@implementation ScientificFixture
- (void)userContentController:(WKUserContentController *)controller
      didReceiveScriptMessage:(WKScriptMessage *)message {
    if (![message.body isEqual:@"ok"])
        self.failure = [message.body description];
    self.completed = YES;
}

- (void)webView:(WKWebView *)view didFailProvisionalNavigation:(WKNavigation *)navigation
      withError:(NSError *)error {
    self.failure = error.localizedDescription;
    self.completed = YES;
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2)
            return 2;

        [NSApplication sharedApplication];
        ScientificFixture *fixture = [ScientificFixture new];
        WKWebViewConfiguration *config = [WKWebViewConfiguration new];
        config.websiteDataStore = WKWebsiteDataStore.nonPersistentDataStore;
        [config.userContentController addScriptMessageHandler:fixture name:@"scientificFixture"];
        WKWebView *view = [[WKWebView alloc] initWithFrame:NSMakeRect(0, 0, 820, 560) configuration:config];
        view.navigationDelegate = fixture;
        NSURL *page = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
        [view loadFileURL:page allowingReadAccessToURL:page.URLByDeletingLastPathComponent];

        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:15];
        while (!fixture.completed && [deadline timeIntervalSinceNow] > 0)
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]];
        if (!fixture.completed || fixture.failure) {
            fprintf(stderr, "%s\n", (fixture.failure ?: @"WK scientific Markdown fixture timed out").UTF8String);
            return 1;
        }
        return 0;
    }
}
