//go:build darwin && cgo && !nogui

// Port of Sci-Station's original liquid-glass launch window and layer sequence.
// Copyright (c) 2025-2026 Xia Lingyu (Funyday-k), MIT.
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>

@interface SciLiquidLaunchView : NSView
@end

static CAGradientLayer *sciGradient(NSArray<NSColor *> *colors, NSArray<NSNumber *> *locations,
                                    CGPoint start, CGPoint end, float opacity) {
    CAGradientLayer *layer = [CAGradientLayer layer];
    NSMutableArray *values = [NSMutableArray arrayWithCapacity:colors.count];
    for (NSColor *color in colors) [values addObject:(__bridge id)color.CGColor];
    layer.colors = values;
    layer.locations = locations;
    layer.startPoint = start;
    layer.endPoint = end;
    layer.opacity = opacity;
    layer.allowsEdgeAntialiasing = YES;
    return layer;
}

static void sciRoundedPath(CAShapeLayer *layer, CGRect rect, CGFloat radius) {
    CGPathRef path = CGPathCreateWithRoundedRect(rect, radius, radius, NULL);
    layer.path = path;
    CGPathRelease(path);
}

static void sciAnimate(CALayer *layer, NSString *key, id start, id end,
                       CFTimeInterval duration, CFTimeInterval delay, CAMediaTimingFunction *timing) {
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:key];
    animation.fromValue = start;
    animation.toValue = end;
    animation.duration = duration;
    animation.beginTime = CACurrentMediaTime() + delay;
    animation.timingFunction = timing;
    animation.fillMode = kCAFillModeBackwards;
    animation.removedOnCompletion = YES;
    [layer addAnimation:animation forKey:key];
}

static void sciAnimateFrame(CALayer *layer, CGRect from, CGRect to, CGFloat fromRadius,
                            CGFloat toRadius, CAMediaTimingFunction *timing) {
    [layer setFrame:to];
    layer.cornerRadius = toRadius;
    sciAnimate(layer, @"bounds", [NSValue valueWithRect:(CGRect){CGPointZero, from.size}],
               [NSValue valueWithRect:(CGRect){CGPointZero, to.size}], 0.86, 0, timing);
    sciAnimate(layer, @"position", [NSValue valueWithPoint:CGPointMake(CGRectGetMidX(from), CGRectGetMidY(from))],
               [NSValue valueWithPoint:CGPointMake(CGRectGetMidX(to), CGRectGetMidY(to))], 0.86, 0, timing);
    sciAnimate(layer, @"cornerRadius", @(fromRadius), @(toRadius), 0.86, 0, timing);
}

@implementation SciLiquidLaunchView {
    CAGradientLayer *_backlight, *_bloom, *_tint, *_sheen;
    CALayer *_panel;
    NSView *_materialHost, *_overlay;
    NSVisualEffectView *_material;
    CAShapeLayer *_mask, *_rim;
    NSArray<CATextLayer *> *_titles;
    BOOL _started;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.wantsLayer = YES;
    self.layer.backgroundColor = NSColor.clearColor.CGColor;
    self.layer.masksToBounds = NO;

    _backlight = sciGradient(@[[NSColor.systemBlueColor colorWithAlphaComponent:0.18],
                               [NSColor.systemPurpleColor colorWithAlphaComponent:0.12],
                               [NSColor.systemTealColor colorWithAlphaComponent:0.08], NSColor.clearColor],
                             @[@0, @0.34, @0.64, @1],
                             CGPointMake(0.05, 1), CGPointMake(1, 0), 0.42);
    _bloom = sciGradient(@[[NSColor.systemCyanColor colorWithAlphaComponent:0.14],
                           [NSColor.systemPinkColor colorWithAlphaComponent:0.08], NSColor.clearColor],
                         @[@0, @0.42, @1], CGPointMake(0, 0.18), CGPointMake(1, 0.86), 0.26);
    [self.layer addSublayer:_backlight];
    [self.layer addSublayer:_bloom];

    _panel = [CALayer layer];
    _panel.backgroundColor = [NSColor.whiteColor colorWithAlphaComponent:0.004].CGColor;
    _panel.shadowColor = NSColor.blackColor.CGColor;
    _panel.shadowOpacity = 0.16;
    _panel.shadowRadius = 14;
    _panel.shadowOffset = CGSizeMake(0, -3);
    _panel.allowsEdgeAntialiasing = YES;
    _panel.drawsAsynchronously = YES;
    [self.layer addSublayer:_panel];

    _materialHost = [[NSView alloc] initWithFrame:self.bounds];
    _materialHost.wantsLayer = YES;
    _materialHost.alphaValue = 0.52;
    _materialHost.layer.backgroundColor = NSColor.clearColor.CGColor;
    _materialHost.layer.allowsEdgeAntialiasing = YES;
    _mask = [CAShapeLayer layer];
    _mask.fillColor = NSColor.blackColor.CGColor;
    _mask.actions = @{@"path": NSNull.null, @"bounds": NSNull.null, @"position": NSNull.null};
    _materialHost.layer.mask = _mask;
    [self addSubview:_materialHost];

    _material = [[NSVisualEffectView alloc] initWithFrame:_materialHost.bounds];
    _material.material = NSVisualEffectMaterialPopover;
    _material.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    _material.state = NSVisualEffectStateActive;
    _material.emphasized = YES;
    _material.wantsLayer = YES;
    _material.layer.backgroundColor = NSColor.clearColor.CGColor;
    _material.layer.allowsEdgeAntialiasing = YES;
    [_materialHost addSubview:_material];

    _overlay = [[NSView alloc] initWithFrame:self.bounds];
    _overlay.wantsLayer = YES;
    _overlay.layer.backgroundColor = NSColor.clearColor.CGColor;
    _overlay.layer.masksToBounds = NO;
    [self addSubview:_overlay];

    _tint = sciGradient(@[[NSColor.whiteColor colorWithAlphaComponent:0.08],
                          [NSColor.systemCyanColor colorWithAlphaComponent:0.08],
                          [NSColor.systemBlueColor colorWithAlphaComponent:0.05],
                          [NSColor.systemPurpleColor colorWithAlphaComponent:0.045]],
                        @[@0, @0.32, @0.72, @1], CGPointMake(0.08, 1), CGPointMake(0.95, 0), 0.32);
    _sheen = sciGradient(@[[NSColor.whiteColor colorWithAlphaComponent:0.16],
                           [NSColor.whiteColor colorWithAlphaComponent:0.035],
                           [NSColor.whiteColor colorWithAlphaComponent:0.012]],
                         @[@0, @0.45, @1], CGPointMake(0.12, 1), CGPointMake(0.92, 0), 0.4);
    _tint.masksToBounds = YES;
    _sheen.masksToBounds = YES;
    [_overlay.layer addSublayer:_tint];
    [_overlay.layer addSublayer:_sheen];
    _rim = [CAShapeLayer layer];
    _rim.fillColor = NSColor.clearColor.CGColor;
    _rim.strokeColor = [NSColor.whiteColor colorWithAlphaComponent:0.42].CGColor;
    _rim.lineWidth = 1.15;
    _rim.allowsEdgeAntialiasing = YES;
    [_overlay.layer addSublayer:_rim];

    _titles = @[[self title:[NSColor.systemCyanColor colorWithAlphaComponent:0.58] offset:CGPointMake(-4, 3) front:NO],
                [self title:[NSColor.systemPurpleColor colorWithAlphaComponent:0.48] offset:CGPointMake(4, -3) front:NO],
                [self title:NSColor.whiteColor offset:CGPointZero front:YES]];
    return self;
}

- (CATextLayer *)title:(NSColor *)color offset:(CGPoint)offset front:(BOOL)front {
    CATextLayer *layer = [CATextLayer layer];
    NSString *font = @"SnellRoundhand-Bold";
    if (![NSFont fontWithName:font size:70]) {
        font = [NSFont fontWithName:@"Snell Roundhand" size:70] ? @"Snell Roundhand" : @"HelveticaNeue-Medium";
    }
    layer.string = @"Sci-Station";
    layer.font = (__bridge CFStringRef)font;
    layer.fontSize = 70;
    layer.alignmentMode = kCAAlignmentCenter;
    layer.contentsScale = NSScreen.mainScreen ? NSScreen.mainScreen.backingScaleFactor : 2;
    layer.foregroundColor = color.CGColor;
    layer.opacity = 0;
    layer.shadowColor = front ? [NSColor.blackColor colorWithAlphaComponent:0.42].CGColor : color.CGColor;
    layer.shadowOpacity = front ? 0.34 : 0.18;
    layer.shadowRadius = front ? 6 : 4;
    layer.shadowOffset = CGSizeMake(0, front ? -1 : 0);
    layer.actions = @{@"contents":NSNull.null};
    [layer setAffineTransform:CGAffineTransformMakeTranslation(offset.x, offset.y)];
    [_overlay.layer addSublayer:layer];
    return layer;
}

- (CGRect)startFrame {
    return CGRectMake(NSMidX(self.bounds) - 66, NSMidY(self.bounds) - 66, 132, 132);
}

- (CGRect)endFrame {
    CGFloat width = MIN(self.bounds.size.width * 0.82, 520);
    return CGRectMake(NSMidX(self.bounds) - width/2, NSMidY(self.bounds) - 86, width, 172);
}

- (void)applyGeometry:(CGRect)frame radius:(CGFloat)radius titleVisible:(BOOL)visible {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _panel.frame = frame;
    _panel.cornerRadius = radius;
    CGPathRef shadow = CGPathCreateWithRoundedRect(CGRectInset((CGRect){CGPointZero, frame.size}, 2, 2),
                                                  MAX(radius-2, 0), MAX(radius-2, 0), NULL);
    _panel.shadowPath = shadow;
    CGPathRelease(shadow);
    _materialHost.frame = self.bounds;
    _materialHost.layer.mask = _mask;
    _material.frame = _materialHost.bounds;
    _mask.frame = _materialHost.bounds;
    sciRoundedPath(_mask, frame, radius);
    _overlay.frame = self.bounds;
    _backlight.frame = CGRectInset(frame, -22, -16);
    _backlight.cornerRadius = radius + 18;
    _bloom.frame = CGRectInset(frame, -10, -8);
    _bloom.cornerRadius = radius + 10;
    for (CALayer *layer in @[_tint, _sheen]) {
        layer.frame = frame;
        layer.cornerRadius = radius;
    }
    _rim.frame = _overlay.bounds;
    sciRoundedPath(_rim, frame, radius);
    CGRect end = self.endFrame;
    CGRect title = CGRectMake(CGRectGetMinX(end) + 28, CGRectGetMidY(end) - 48, end.size.width - 56, 92);
    for (CATextLayer *layer in _titles) {
        layer.frame = title;
        layer.opacity = visible ? 1 : 0;
    }
    [CATransaction commit];
}

- (void)layout {
    [super layout];
    if (!_titles) return;
    [self applyGeometry:_started ? self.endFrame : self.startFrame radius:_started ? 28 : 66 titleVisible:_started];
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (!self.window || _started) return;
    self.window.movableByWindowBackground = NO;
    _started = YES;
    [self layoutSubtreeIfNeeded];
    CGRect from = self.startFrame, to = self.endFrame;
    [self applyGeometry:to radius:28 titleVisible:YES];

    CAMediaTimingFunction *curve = [CAMediaTimingFunction functionWithControlPoints:0.18 :0.92 :0.18 :1];
    sciAnimateFrame(_backlight, CGRectInset(from, -16, -14), CGRectInset(to, -22, -16), 80, 46, curve);
    sciAnimateFrame(_bloom, CGRectInset(from, -8, -8), CGRectInset(to, -10, -8), 74, 38, curve);
    for (CALayer *layer in @[_panel, _tint, _sheen]) sciAnimateFrame(layer, from, to, 66, 28, curve);

    CGPathRef first = CGPathCreateWithRoundedRect(from, 66, 66, NULL);
    CGPathRef last = CGPathCreateWithRoundedRect(to, 28, 28, NULL);
    for (CAShapeLayer *shape in @[_mask, _rim]) {
        sciAnimate(shape, @"path", (__bridge id)first, (__bridge id)last, 0.86, 0, curve);
    }
    CGPathRelease(first);
    CGPathRelease(last);

    sciAnimate(_tint, @"opacity", @0.1, @0.32, 0.58, 0.14, curve);
    sciAnimate(_sheen, @"opacity", @0.1, @0.4, 0.54, 0.18, curve);
    sciAnimate(_backlight, @"opacity", @0.16, @0.42, 0.62, 0.1, curve);
    sciAnimate(_bloom, @"opacity", @0.08, @0.26, 0.62, 0.18, curve);
    CAMediaTimingFunction *titleCurve = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    [_titles enumerateObjectsUsingBlock:^(CATextLayer *layer, NSUInteger index, BOOL *stop) {
        CFTimeInterval delay = 0.66 + 0.045 * index;
        sciAnimate(layer, @"opacity", @0, @1, 0.5, delay, titleCurve);
        sciAnimate(layer, @"transform.scale", @0.965, @1, 0.58, delay, titleCurve);
    }];
}
@end

// Each function is dispatched to the native main queue by its Wails hook.
// Keep a strong owner while the otherwise independent borderless window fades.
static NSWindow *sciSplash;
static NSWindow *sciMain;
static unsigned int sciMainID;
extern void sciShowLaunchWindow(unsigned int windowID);
static BOOL sciStarted, sciMinimumElapsed, sciFinished;

static void sciRevealIfReady(void) {
    if (sciFinished || !sciMinimumElapsed || !sciMain) return;
    sciFinished = YES;
    sciMain.alphaValue = 0;
    sciShowLaunchWindow(sciMainID);
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.22;
        sciMain.animator.alphaValue = 1;
    } completionHandler:nil];
    const int splashFadeMillis = 180;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = splashFadeMillis / 1000.0;
        sciSplash.animator.alphaValue = 0;
    } completionHandler:nil];
    // Window teardown must also run when AppKit skips animation frames.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, splashFadeMillis * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        [sciSplash close];
        sciSplash = nil;
        sciMain = nil;
    });
}

void sciLaunchBegin(void) {
    if (sciStarted) return;
    sciStarted = YES;
    NSRect frame = NSMakeRect(0, 0, 620, 360);
    sciSplash = [[NSWindow alloc] initWithContentRect:frame styleMask:NSWindowStyleMaskBorderless
                                             backing:NSBackingStoreBuffered defer:NO];
    sciSplash.releasedWhenClosed = NO;
    sciSplash.title = @"Sci-Station";
    sciSplash.opaque = NO;
    sciSplash.backgroundColor = NSColor.clearColor;
    sciSplash.hasShadow = NO;
    sciSplash.level = NSFloatingWindowLevel;
    sciSplash.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
    sciSplash.contentView = [[SciLiquidLaunchView alloc] initWithFrame:frame];
    [sciSplash center];
    [sciSplash orderFrontRegardless];
    [NSApp activateIgnoringOtherApps:YES];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2250 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        sciMinimumElapsed = YES;
        sciRevealIfReady();
    });
}

void sciLaunchReady(void *window, unsigned int windowID) {
    if (sciFinished || !window) return;
    sciMain = (__bridge NSWindow *)window;
    sciMainID = windowID;
    sciRevealIfReady();
}
