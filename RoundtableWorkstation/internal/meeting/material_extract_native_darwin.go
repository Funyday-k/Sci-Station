//go:build darwin && cgo && !nogui

package meeting

/*
#cgo CFLAGS: -fobjc-arc
#cgo LDFLAGS: -framework Foundation -framework Vision -framework PDFKit -framework AppKit -framework ImageIO
#include <stdlib.h>
char *rt_extract_visual_excerpt(const char *path, int is_pdf, int max_pages, int max_pixels);
*/
import "C"
import (
	"errors"
	"strings"
	"unsafe"
)

func nativeMaterialVisualExcerpt(path, mimeType, ext string) (string, error) {
	cp := C.CString(path)
	defer C.free(unsafe.Pointer(cp))
	isPDF := C.int(0)
	if ext == ".pdf" || mimeType == "application/pdf" {
		isPDF = 1
	}
	p := C.rt_extract_visual_excerpt(cp, isPDF, 5, 20_000_000)
	if p == nil {
		return "", errors.New("native PDF/OCR extraction failed; material was not read")
	}
	defer C.free(unsafe.Pointer(p))
	s := strings.TrimSpace(C.GoString(p))
	if s == "" {
		return "", errors.New("no readable text was extracted")
	}
	return boundedMaterialText("[Partial local extraction; at most 5 PDF pages or one image.]\n" + s)
}
