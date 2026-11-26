//go:build darwin && cgo && !nogui
#import <Foundation/Foundation.h>
#import <Vision/Vision.h>
#import <PDFKit/PDFKit.h>
#import <ImageIO/ImageIO.h>
#include <string.h>

static NSString *RecognizeImageData(NSData *data, size_t maxPixels) {
    @autoreleasepool {
        CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
        if (!source) return @"";
        NSDictionary *props = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL));
        NSNumber *w = props[(NSString *)kCGImagePropertyPixelWidth];
        NSNumber *h = props[(NSString *)kCGImagePropertyPixelHeight];
        size_t width = w.unsignedLongValue, height = h.unsignedLongValue;
        if (!width || !height || width > maxPixels / height) { CFRelease(source); return @""; }
        CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
        CFRelease(source);
        if (!image) return @"";
        VNRecognizeTextRequest *request = [VNRecognizeTextRequest new];
        request.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
        request.usesLanguageCorrection = YES;
        request.recognitionLanguages = @[@"zh-Hans", @"zh-Hant", @"en-US"];
        VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:image options:@{}];
        NSError *error = nil;
        BOOL ok = [handler performRequests:@[request] error:&error];
        CGImageRelease(image);
        if (!ok) return @"";
        NSMutableArray *lines = [NSMutableArray new];
        for (VNRecognizedTextObservation *o in request.results) {
            VNRecognizedText *candidate = [[o topCandidates:1] firstObject];
            if (candidate.string.length) [lines addObject:candidate.string];
        }
        return [lines componentsJoinedByString:@"\n"];
    }
}

static NSString *RecognizeCGImage(CGImageRef image) {
    if (!image) return @"";
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:image];
    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    return RecognizeImageData(png, 20000000);
}

char *rt_extract_visual_excerpt(const char *path, int is_pdf, int max_pages, int max_pixels) {
    @autoreleasepool {
        NSString *p = [NSString stringWithUTF8String:path];
        NSData *data = [NSData dataWithContentsOfFile:p options:NSDataReadingMappedIfSafe error:nil];
        if (!data || data.length > 24 * 1024 * 1024) return NULL;
        NSMutableString *result = [NSMutableString new];
        if (is_pdf) {
            PDFDocument *doc = [[PDFDocument alloc] initWithData:data];
            if (!doc) return NULL;
            NSInteger pages = MIN((NSInteger)max_pages, doc.pageCount);
            for (NSInteger i=0; i<pages && result.length<24576; i++) {
                @autoreleasepool {
                    PDFPage *page = [doc pageAtIndex:i];
                    NSString *text = page.string ?: @"";
                    if (text.length < 24) {
                        NSImage *thumbnail = [page thumbnailOfSize:NSMakeSize(1800, 1800) forBox:kPDFDisplayBoxCropBox];
                        CGImageRef cg = [thumbnail CGImageForProposedRect:NULL context:nil hints:nil];
                        if (cg && CGImageGetWidth(cg) <= max_pixels / MAX((size_t)1, CGImageGetHeight(cg))) {
                            NSString *ocr = RecognizeCGImage(cg);
                            if (ocr.length) text = ocr;
                        }
                    }
                    if (text.length) [result appendFormat:@"\n[Page %ld]\n%@", (long)i+1, text];
                }
            }
        } else {
            NSString *text = RecognizeImageData(data, (size_t)max_pixels);
            if (text.length) [result appendString:text];
        }
        if (!result.length) return NULL;
        return strdup(result.UTF8String);
    }
}
