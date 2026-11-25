// Linked only into the re-signed WKWebView test copy. The application passed to
// the smoke runner and the production build do not contain this driver.
#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static WKWebView *findWebView(NSView *view) {
    if ([view isKindOfClass:WKWebView.class]) return (WKWebView *)view;
    for (NSView *child in view.subviews) {
        WKWebView *found = findWebView(child);
        if (found) return found;
    }
    return nil;
}

static WKWebView *visibleWebView(void) {
    for (NSWindow *window in NSApp.orderedWindows) {
        if (!window.visible || window.alphaValue < 0.999) continue;
        WKWebView *view = findWebView(window.contentView);
        if (view) return view;
    }
    return nil;
}

static void steerToSecondaryScreen(NSWindow *window) {
    const char *requested = getenv("SCI_STATION_WORKFLOW_SECONDARY");
    if (requested == NULL || strcmp(requested, "1") != 0) return;
    NSArray<NSScreen *> *screens = NSScreen.screens;
    if (screens.count < 2) {
        fprintf(stderr, "The WKWebView smoke test requested a secondary screen\n");
        exit(6);
    }
    NSRect display = screens[1].visibleFrame;
    NSRect frame = window.frame;
    frame.size.width = MIN(frame.size.width, NSWidth(display));
    frame.size.height = MIN(frame.size.height, NSHeight(display));
    frame.origin = NSMakePoint(NSMidX(display) - NSWidth(frame) / 2, NSMidY(display) - NSHeight(frame) / 2);
    [window setFrame:frame display:YES];
}

static void respond(NSString *file, id requestID, id value, NSString *error) {
    id null = NSNull.null;
    NSDictionary *response = @{@"id": requestID, @"value": value ?: null, @"error": error ?: null};
    if (![NSJSONSerialization isValidJSONObject:response]) {
        response = @{@"id": requestID, @"value": null, @"error": @"WKWebView value is not JSON-compatible"};
    }
    NSError *issue = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:response options:0 error:&issue];
    if (!data || ![data writeToFile:file options:NSDataWritingAtomic error:&issue]) {
        fprintf(stderr, "Cannot publish WKWebView smoke result: %s\n",
            issue.localizedDescription.UTF8String ?: "unknown write error");
        exit(7);
    }
}

static void pollRequest(NSString *mailbox) {
    NSString *requestFile = [mailbox stringByAppendingPathComponent:@"request.json"];
    NSString *responseFile = [mailbox stringByAppendingPathComponent:@"response.json"];
    __block BOOL working = NO;
    __block id lastID = nil;
    __block __weak NSWindow *positioned = nil;
    [NSTimer scheduledTimerWithTimeInterval:0.08 repeats:YES block:^(NSTimer *unused __unused) {
        if (working) return;
        WKWebView *webView = visibleWebView();
        if (!webView || !webView.URL || webView.loading) return;
        if (webView.window != positioned) {
            positioned = webView.window;
            steerToSecondaryScreen(positioned);
        }
        NSData *input = [NSData dataWithContentsOfFile:requestFile];
        if (!input) return;
        id object = [NSJSONSerialization JSONObjectWithData:input options:0 error:NULL];
        if (![object isKindOfClass:NSDictionary.class]) return;
        NSDictionary *request = object;
        id requestID = request[@"id"];
        if ((![requestID isKindOfClass:NSString.class] && ![requestID isKindOfClass:NSNumber.class]) ||
            [requestID isEqual:lastID]) return;
        lastID = requestID;
        NSString *script = request[@"script"];
        if ([script isKindOfClass:NSString.class]) {
            working = YES;
            [webView evaluateJavaScript:script completionHandler:^(id value, NSError *error) {
                respond(responseFile, requestID, value, error.localizedDescription);
                working = NO;
            }];
        } else if ([request[@"capture"] isEqual:@YES]) {
            working = YES;
            [webView takeSnapshotWithConfiguration:nil completionHandler:^(NSImage *image, NSError *error) {
                NSBitmapImageRep *bitmap = image ? [NSBitmapImageRep imageRepWithData:image.TIFFRepresentation] : nil;
                NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
                respond(responseFile, requestID, [png base64EncodedStringWithOptions:0],
                    error.localizedDescription ?: (png ? nil : @"WKWebView did not return a PNG snapshot"));
                working = NO;
            }];
        } else if ([request[@"quit"] isEqual:@YES]) {
            working = YES;
            respond(responseFile, requestID, @YES, nil);
            dispatch_async(dispatch_get_main_queue(), ^{
                [NSApp terminate:nil];
            });
        } else {
            respond(responseFile, requestID, nil, @"Expected a JavaScript expression, capture:true, or quit:true");
        }
    }];
}

__attribute__((constructor)) static void armWorkflow(void) {
    const char *directory = getenv("SCI_STATION_WORKFLOW_DRIVER_DIR");
    if (!directory) return;
    struct stat info;
    if (directory[0] != '/' || lstat(directory, &info) != 0 || !S_ISDIR(info.st_mode) ||
        info.st_uid != getuid() || (info.st_mode & 0777) != 0700) {
        fprintf(stderr, "The WKWebView smoke mailbox must be an absolute, owned 0700 directory\n");
        exit(5);
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        pollRequest([NSString stringWithUTF8String:directory]);
    });
}
