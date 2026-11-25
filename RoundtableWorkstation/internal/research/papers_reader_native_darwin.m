// go:build darwin && cgo
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <PDFKit/PDFKit.h>
#import <Vision/Vision.h>
#include <limits.h>
#include <string.h>

static NSData *jsonData(id object) {
    return [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
}

// Use the very same PDF-to-display transform for raster and all text geometry.
// Display coordinates have top-left origin and include the PDF crop/rotation.
static NSDictionary *normalizedBounds(CGRect rect, CGAffineTransform transform, CGSize size) {
    CGRect bounded =
        CGRectIntersection(CGRectApplyAffineTransform(rect, transform), (CGRect){CGPointZero, size});
    if (CGRectIsEmpty(bounded) || CGRectIsNull(bounded))
        return nil;
    return @{
        @"x" : @(CGRectGetMinX(bounded) / size.width),
        @"y" : @(1 - CGRectGetMaxY(bounded) / size.height),
        @"width" : @(bounded.size.width / size.width),
        @"height" : @(bounded.size.height / size.height)
    };
}

static NSData *rasterPage(CGPDFPageRef page, CGSize display) {
    CGFloat factor = MIN(1920.0 / display.width, 2500.0 / display.height);
    size_t w = MAX(1, (size_t)llround(display.width * factor));
    size_t h = MAX(1, (size_t)llround(display.height * factor));
    CGRect target = CGRectMake(0, 0, w, h);
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx =
        CGBitmapContextCreate(NULL, w, h, 8, w * 4, rgb, (CGBitmapInfo)kCGImageAlphaNoneSkipLast);
    CGColorSpaceRelease(rgb);
    if (!ctx)
        return nil;
    CGContextSetRGBFillColor(ctx, 1, 1, 1, 1);
    CGContextFillRect(ctx, target);
    CGContextScaleCTM(ctx, w / display.width, h / display.height);
    CGContextConcatCTM(
        ctx, CGPDFPageGetDrawingTransform(page, kCGPDFCropBox, (CGRect){CGPointZero, display}, 0, true));
    CGContextDrawPDFPage(ctx, page);
    CGImageRef im = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    if (!im)
        return nil;
    NSMutableData *out = [NSMutableData data];
    CGImageDestinationRef dest =
        CGImageDestinationCreateWithData((__bridge CFMutableDataRef)out, CFSTR("public.png"), 1, NULL);
    BOOL ok = NO;
    if (dest) {
        CGImageDestinationAddImage(dest, im, NULL);
        ok = CGImageDestinationFinalize(dest);
        CFRelease(dest);
    }
    CGImageRelease(im);
    return ok ? out : nil;
}

static NSData *ocrPage(CGPDFPageRef page, CGSize size, int index, NSString *label) {
    NSData *raster = rasterPage(page, size);
    if (!raster)
        return nil;
    VNRecognizeTextRequest *request = [[VNRecognizeTextRequest alloc] init];
    request.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
    request.usesLanguageCorrection = YES;
    request.recognitionLanguages = @[ @"zh-Hans", @"zh-Hant", @"en-US" ];
    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithData:raster options:@{}];
    NSError *error = nil;
    if (![handler performRequests:@[ request ] error:&error])
        return nil;
    NSMutableString *body = [NSMutableString string];
    NSMutableArray *words = [NSMutableArray array];
    NSRegularExpression *token = [NSRegularExpression regularExpressionWithPattern:@"\\S+"
                                                                           options:0
                                                                             error:nil];
    for (VNRecognizedTextObservation *item in request.results) {
        VNRecognizedText *candidate = [item topCandidates:1].firstObject;
        NSString *line = candidate.string;
        if (!line.length)
            continue;
        if (body.length)
            [body appendString:@"\n"];
        NSUInteger offset = body.length;
        [body appendString:line];
        [token enumerateMatchesInString:line
                                options:0
                                  range:NSMakeRange(0, line.length)
                             usingBlock:^(NSTextCheckingResult *match, NSMatchingFlags flags, BOOL *stop) {
                               NSRange r = match.range;
                               VNRectangleObservation *location = [candidate boundingBoxForRange:r error:nil];
                               CGRect b = location ? location.boundingBox : item.boundingBox;
                               NSDictionary *box = @{
                                   @"x" : @(b.origin.x),
                                   @"y" : @(1 - CGRectGetMaxY(b)),
                                   @"width" : @(b.size.width),
                                   @"height" : @(b.size.height)
                               };
                               [words addObject:@{
                                   @"text" : [line substringWithRange:r],
                                   @"start" : @(offset + r.location),
                                   @"end" : @(offset + NSMaxRange(r)),
                                   @"box" : box
                               }];
                             }];
    }
    return jsonData(@{
        @"page" : @(index),
        @"label" : label ?: @"",
        @"width" : @(size.width),
        @"height" : @(size.height),
        @"words" : words,
        @"text" : body,
        @"ocr" : @YES
    });
}

static NSData *findPages(PDFDocument *doc, NSString *query) {
    NSMutableArray *items = [NSMutableArray array];
    BOOL limited = NO;
    for (NSUInteger i = 0; i < doc.pageCount; i++) {
        @autoreleasepool {
            NSString *s = [doc pageAtIndex:i].string;
            if (!s.length)
                continue;
            NSUInteger pos = 0;
            while (pos < s.length) {
                NSRange hit = [s rangeOfString:query
                                       options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch
                                         range:NSMakeRange(pos, s.length - pos)];
                if (hit.location == NSNotFound)
                    break;
                if (items.count == 120) {
                    limited = YES;
                    break;
                }
                NSUInteger start = hit.location > 35 ? hit.location - 35 : 0;
                NSUInteger end = MIN(s.length, NSMaxRange(hit) + 50);
                NSString *snippet = [s
                    substringWithRange:[s rangeOfComposedCharacterSequencesForRange:NSMakeRange(
                                                                                        start, end - start)]];
                [items addObject:@{
                    @"page" : @(i + 1),
                    @"start" : @(hit.location),
                    @"end" : @(NSMaxRange(hit)),
                    @"text" : snippet
                }];
                pos = NSMaxRange(hit);
            }
        }
        if (limited)
            break;
    }
    return jsonData(@{@"items" : items, @"limited" : @(limited)});
}

void *sci_reader_page(const char *path, const char *operation, int page, const char *query, int *length,
                      int *is_error) {
    @autoreleasepool {
        @try {
            PDFDocument *doc = [[PDFDocument alloc]
                initWithURL:[NSURL fileURLWithPath:[NSString stringWithUTF8String:path]]];
            NSString *op = [NSString stringWithUTF8String:operation];
            NSData *data = nil;
            NSString *issue = nil;
            if (!doc || doc.isLocked || doc.pageCount == 0 || ![doc pageAtIndex:0].pageRef)
                issue = @"无法访问 PDF 页面，文件可能损坏或已加密。";
            else if ([op isEqualToString:@"info"])
                data = jsonData(@{@"pages" : @(doc.pageCount)});
            else if ([op isEqualToString:@"search"])
                data = findPages(doc, [NSString stringWithUTF8String:query]);
            else if (page < 1 || (NSUInteger)page > doc.pageCount)
                issue = @"页码超出文档范围。";
            else {
                PDFPage *p = [doc pageAtIndex:page - 1];
                CGPDFPageRef pg = p.pageRef;
                if (!pg)
                    return NULL;
                CGRect crop = CGPDFPageGetBoxRect(pg, kCGPDFCropBox);
                int rot = ((CGPDFPageGetRotationAngle(pg) % 360) + 360) % 360;
                CGSize size =
                    (rot == 90 || rot == 270) ? CGSizeMake(crop.size.height, crop.size.width) : crop.size;
                if (!isfinite(size.width) || !isfinite(size.height) || size.width <= 0 || size.height <= 0)
                    return NULL;
                if ([op isEqualToString:@"image"])
                    data = rasterPage(pg, size);
                else if ([op isEqualToString:@"ocr"])
                    data = ocrPage(pg, size, page, p.label);
                else {
                    CGAffineTransform t =
                        CGPDFPageGetDrawingTransform(pg, kCGPDFCropBox, (CGRect){CGPointZero, size}, 0, true);
                    NSString *body = p.string ?: @"";
                    NSMutableArray *words = [NSMutableArray array];
                    NSRegularExpression *token = [NSRegularExpression regularExpressionWithPattern:@"\\S+"
                                                                                           options:0
                                                                                             error:nil];
                    [token enumerateMatchesInString:body
                                            options:0
                                              range:NSMakeRange(0, body.length)
                                         usingBlock:^(NSTextCheckingResult *match, NSMatchingFlags flags,
                                                      BOOL *stop) {
                                           if (words.count >= 12000) {
                                               *stop = YES;
                                               return;
                                           }
                                           NSRange r = match.range;
                                           PDFSelection *selection = [p selectionForRange:r];
                                           if (!selection)
                                               return;
                                           NSDictionary *box =
                                               normalizedBounds([selection boundsForPage:p], t, size);
                                           if (box)
                                               [words addObject:@{
                                                   @"text" : [body substringWithRange:r],
                                                   @"start" : @(r.location),
                                                   @"end" : @(NSMaxRange(r)),
                                                   @"box" : box
                                               }];
                                         }];
                    data = jsonData(@{
                        @"page" : @(page),
                        @"label" : p.label ?: @"",
                        @"width" : @(size.width),
                        @"height" : @(size.height),
                        @"words" : words,
                        @"text" : body
                    });
                }
            }
            *is_error = 0;
            if (issue) {
                *is_error = 1;
                data = jsonData(@{@"error" : issue});
            }
            if (!data.length || data.length > INT_MAX)
                return NULL;
            void *result = malloc(data.length);
            if (!result)
                return NULL;
            memcpy(result, data.bytes, data.length);
            *length = (int)data.length;
            return result;
        } @catch (NSException *exception) {
            return NULL;
        }
    }
}
