// Linked only into the re-signed WKWebView test copy. The application passed to
// the smoke runner and the production build do not contain this driver.
#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>
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

static NSButton *storageConfirmButton(NSView *view) {
    if ([view isKindOfClass:NSButton.class]) {
        NSButton *button = (NSButton *)view;
        if ([button.title isEqualToString:@"Use default location"] || [button.title isEqualToString:@"使用默认位置"]) return button;
    }
    for (NSView *child in view.subviews) {
        NSButton *found = storageConfirmButton(child);
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

// These commands are linked into the smoke copy only. Keep the old proof
// inside this process and return only the HTTP result of the negative test.
static NSString *priorWindowProof;
static NSNumber *priorWindowPort;
static BOOL trustedStudio(NSURL *url) {
    return [url.scheme isEqualToString:@"http"] && [url.host isEqualToString:@"127.0.0.1"] &&
        url.port != nil && [url.path isEqualToString:@"/studio"];
}
// Supply the selection to the actual Wails picker completion for this one
// menu action. AppKit's remote file panel needs no accessibility privileges;
// the production root validation, publication and navigation all run normally.
static NSURL *fixtureSelection;
static __weak NSWindow *fixtureParent;
static char selectionKey;
static void (*originalOpenSheet)(id, SEL, NSWindow *, void (^)(NSModalResponse));
static NSArray *(*originalURLs)(id, SEL);
static NSArray *workflowURLs(id panel, SEL selector) {
    NSURL *selected=objc_getAssociatedObject(panel,&selectionKey);
    return selected ? @[selected] : originalURLs(panel,selector);
}
static void workflowOpenSheet(id panel,SEL selector,NSWindow *parent,void (^done)(NSModalResponse)) {
    if (!fixtureSelection || parent!=fixtureParent || ![(NSOpenPanel *)panel canChooseDirectories]) {
        originalOpenSheet(panel,selector,parent,done);return;
    }
    objc_setAssociatedObject(panel,&selectionKey,fixtureSelection,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    fixtureSelection=nil; fixtureParent=nil;
    dispatch_async(dispatch_get_main_queue(),^{done(NSModalResponseOK);});
}
static void selectFixtureRoot(NSWindow *parent,NSURL *root) {
    static dispatch_once_t once;
    dispatch_once(&once,^{
        Class cls=NSOpenPanel.class;SEL begin=@selector(beginSheetModalForWindow:completionHandler:);
        Method beginMethod=class_getInstanceMethod(cls,begin);
        originalOpenSheet=(void *)method_getImplementation(beginMethod);
        class_replaceMethod(cls,begin,(IMP)workflowOpenSheet,method_getTypeEncoding(beginMethod));
        Method urls=class_getInstanceMethod(cls,@selector(URLs));
        originalURLs=(void *)method_getImplementation(urls);
        class_replaceMethod(cls,@selector(URLs),(IMP)workflowURLs,method_getTypeEncoding(urls));
    });
    fixtureSelection=root;fixtureParent=parent;
}
static BOOL menuKey(NSWindow *window, NSString *key, unsigned short code) {
    NSEvent *event=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagCommand
        timestamp:0 windowNumber:window.windowNumber context:nil characters:key charactersIgnoringModifiers:key isARepeat:NO keyCode:code];
    return [NSApp.mainMenu performKeyEquivalent:event];
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
            // Keep the disposable window visible while the smoke host runs.
            // WebKit suspends the Studio refresh when another window covers it.
            positioned.level = NSFloatingWindowLevel;
            [NSApp activateIgnoringOtherApps:YES];
            [positioned makeKeyAndOrderFront:nil];
        }
        NSData *input = [NSData dataWithContentsOfFile:requestFile];
        if (!input) return;
        id object = [NSJSONSerialization JSONObjectWithData:input options:0 error:NULL];
        if (![object isKindOfClass:NSDictionary.class]) return;
        NSDictionary *request = object;
        id requestID = request[@"id"];
        if ((![requestID isKindOfClass:NSString.class] && ![requestID isKindOfClass:NSNumber.class]) ||
            [requestID isEqual:lastID]) return;
        NSString *script = request[@"script"];
        if (([script isKindOfClass:NSString.class] || [request[@"capture"] isEqual:@YES]) &&
            !(positioned.occlusionState & NSWindowOcclusionStateVisible)) {
            // Restore the test window after another application covers it.
            [positioned orderFrontRegardless];
            return;
        }
        lastID = requestID;
        if ([script isKindOfClass:NSString.class]) {
            working = YES;
            [webView evaluateJavaScript:script completionHandler:^(id value, NSError *error) {
                respond(responseFile, requestID, value, error.localizedDescription);
                working = NO;
            }];
        } else if ([request[@"viewport"] isKindOfClass:NSDictionary.class]) {
            NSDictionary *viewport = request[@"viewport"];
            id width = viewport[@"width"], height = viewport[@"height"];
            if (![width isKindOfClass:NSNumber.class] || ![height isKindOfClass:NSNumber.class] ||
                [width doubleValue] < 1 || [height doubleValue] < 1 ||
                [width doubleValue] > 4000 || [height doubleValue] > 3000) {
                respond(responseFile, requestID, nil, @"Expected a positive viewport in points");
                return;
            }
            NSArray<NSScreen *> *screens = NSScreen.screens;
            NSWindow *window = webView.window;
            NSScreen *screen = screens.count > 1 ? screens[1] : (window.screen ?: screens.firstObject);
            if (!screen) {
                respond(responseFile, requestID, nil, @"No display is available for the WKWebView fixture");
                return;
            }
            NSRect frame = window.frame;
            frame.size.width += [width doubleValue] - NSWidth(webView.bounds);
            frame.size.height += [height doubleValue] - NSHeight(webView.bounds);
            NSRect display = screen.visibleFrame;
            frame.origin = NSMakePoint(floor(NSMidX(display) - NSWidth(frame) / 2),
                floor(NSMidY(display) - NSHeight(frame) / 2));
            [window setFrame:frame display:YES];
            respond(responseFile, requestID, @{@"displays": @(screens.count), @"display": @([screens indexOfObject:screen] + 1),
                @"viewWidth": @(NSWidth(webView.bounds)), @"viewHeight": @(NSHeight(webView.bounds))}, nil);
        } else if ([request[@"capture"] isEqual:@YES]) {
            working = YES;
            [webView takeSnapshotWithConfiguration:nil completionHandler:^(NSImage *image, NSError *error) {
                NSBitmapImageRep *bitmap = image ? [NSBitmapImageRep imageRepWithData:image.TIFFRepresentation] : nil;
                NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
                respond(responseFile, requestID, [png base64EncodedStringWithOptions:0],
                    error.localizedDescription ?: (png ? nil : @"WKWebView did not return a PNG snapshot"));
                working = NO;
            }];
        } else if ([request[@"homeMenu"] isEqual:@YES]) {
            respond(responseFile, requestID, @(menuKey(webView.window,@"1",18)), nil);
        } else if ([request[@"openSecondRoot"] isEqual:@YES] || [request[@"armSecondRoot"] isEqual:@YES]) {
            const char *folder=getenv("SCI_STATION_WORKFLOW_SECOND_ROOT");
            if (!folder) { respond(responseFile,requestID,nil,@"Missing fixture root"); return; }
            selectFixtureRoot(webView.window,[NSURL fileURLWithPath:[NSString stringWithUTF8String:folder] isDirectory:YES]);
            respond(responseFile, requestID, @([request[@"armSecondRoot"] isEqual:@YES] || menuKey(webView.window,@"o",31)), nil);
        } else if ([request[@"windowTitle"] isEqual:@YES]) {
            respond(responseFile, requestID, webView.window.title, nil);
        } else if ([request[@"confirmDefaultLocation"] isEqual:@YES]) {
            NSButton *accept = storageConfirmButton(webView.window.attachedSheet.contentView);
            if (accept) [accept performClick:nil];
            respond(responseFile, requestID, @(accept != nil), nil);
        } else if ([request[@"captureProof"] isEqual:@YES]) {
            if (!trustedStudio(webView.URL)) { respond(responseFile, requestID, nil, @"Expected the fixture Studio"); return; }
            priorWindowPort = webView.URL.port;
            working=YES;
            [webView evaluateJavaScript:@"window.sciStationCLIEditSession" completionHandler:^(id value,NSError *error){
                priorWindowProof=[value isKindOfClass:NSString.class]?value:nil;
                respond(responseFile,requestID,@(priorWindowProof.length>0),error.localizedDescription);working=NO;
            }];
        } else if ([request[@"checkOldProof"] isEqual:@YES]) {
            if (!priorWindowProof || !trustedStudio(webView.URL) || [priorWindowPort isEqual:webView.URL.port]) {
                respond(responseFile, requestID, nil, @"Expected the second fixture Studio"); return;
            }
            NSURL *endpoint=[NSURL URLWithString:@"/api/studio/sessions/missing/cli-edits" relativeToURL:webView.URL];
            NSMutableURLRequest *probe=[NSMutableURLRequest requestWithURL:endpoint];
            [probe setValue:priorWindowProof forHTTPHeaderField:@"X-Sci-Station-CLI-Session"];
            priorWindowProof=nil;working=YES;
            [[[NSURLSession sharedSession] dataTaskWithRequest:probe completionHandler:^(NSData *bytes,NSURLResponse *response,NSError *error){
                dispatch_async(dispatch_get_main_queue(),^{respond(responseFile,requestID,@(((NSHTTPURLResponse *)response).statusCode),error.localizedDescription);working=NO;});
            }] resume];
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
