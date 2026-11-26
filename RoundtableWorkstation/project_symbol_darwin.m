//go:build darwin && cgo && !nogui

#import <AppKit/AppKit.h>
void *sciProjectSymbol(const char *name,int *length) {
    @autoreleasepool {
        NSImage *image=[NSImage imageWithSystemSymbolName:[NSString stringWithUTF8String:name] accessibilityDescription:nil];
        if (!image) return NULL;
        NSImageSymbolConfiguration *cfg=[NSImageSymbolConfiguration configurationWithPointSize:28 weight:NSFontWeightRegular];
        NSData *tiff=[[image imageWithSymbolConfiguration:cfg] TIFFRepresentation];
        if (!tiff) return NULL;
        NSData *data=[[NSBitmapImageRep imageRepWithData:tiff] representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        if (!data || data.length>65536) return NULL;
        void *copy=malloc(data.length);
        if (!copy)return NULL;
        memcpy(copy,data.bytes,data.length);*length=(int)data.length;return copy;
    }
}
