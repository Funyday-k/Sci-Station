//go:build darwin && cgo
#import <Foundation/Foundation.h>
#import <PDFKit/PDFKit.h>

char *sci_export_pdf_markdown(const char *filename, const void *bytes, size_t count, int *length, int *status) {
    @autoreleasepool {
        @try {
            *status = 1;
            *length = 0;
            PDFDocument *doc = filename ? [[PDFDocument alloc] initWithURL:[NSURL fileURLWithPath:[NSString stringWithUTF8String:filename]]] : [[PDFDocument alloc] initWithData:[NSData dataWithBytes:bytes length:count]];
            if (!doc || doc.isLocked || !doc.pageCount) return NULL;

            NSMutableData *body = [NSMutableData data];
            NSUInteger textPages = 0;
            for (NSUInteger i = 0; i < doc.pageCount; i++) {
                @autoreleasepool {
                    PDFPage *page = [doc pageAtIndex:i];
                    NSString *text = [page.string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                    if (text.length) textPages++;
                    NSString *part = [NSString stringWithFormat:@"## 第 %lu 页\n\n%@\n\n",
                                      (unsigned long)i+1, text.length ? text : @"_此页没有可提取的文本。_"];
                    NSData *chunk = [part dataUsingEncoding:NSUTF8StringEncoding];
                    if (!chunk || chunk.length > 48*1024*1024 - body.length) { *status=2; return NULL; }
                    [body appendData:chunk];
                }
            }
            if (!textPages) { *status=3; return NULL; }
            char *result = malloc(body.length);
            if (!result) return NULL;
            memcpy(result,body.bytes,body.length);
            *length=(int)body.length;
            *status=0;
            return result;
        } @catch (NSException *ignored) { return NULL; }
    }
}
