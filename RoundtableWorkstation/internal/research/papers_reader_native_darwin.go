//go:build darwin && cgo

package research

/*
#cgo CFLAGS: -fobjc-arc
#cgo LDFLAGS: -framework Foundation -framework AppKit -framework CoreGraphics -framework ImageIO -framework PDFKit -framework Vision
#include <stdlib.h>
void *sci_reader_page(const char *path, const char *operation, int page, const char *query, int *length, int *is_error);
*/
import "C"

import (
	"errors"
	"unsafe"
)

func nativePDFPage(path, operation string, page int, query string) ([]byte, error) {
	filename, op, q := C.CString(path), C.CString(operation), C.CString(query)
	defer C.free(unsafe.Pointer(filename))
	defer C.free(unsafe.Pointer(op))
	defer C.free(unsafe.Pointer(q))
	var length, failed C.int
	buf := C.sci_reader_page(filename, op, C.int(page), q, &length, &failed)
	if buf == nil {
		return nil, errors.New("无法解析 PDF，请打开原件查看")
	}
	defer C.free(buf)
	data := C.GoBytes(buf, length)
	if failed != 0 {
		return nil, pageError(data)
	}
	return data, nil
}
