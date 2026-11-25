//go:build darwin && cgo

package research

/*
#cgo CFLAGS: -fobjc-arc
#cgo LDFLAGS: -framework Foundation -framework PDFKit
#include <stdlib.h>
char *sci_export_pdf_markdown(const char *, int *, int *);
*/
import "C"
import (
	"errors"
	"unsafe"
)

func documentMarkdown(path string) ([]byte, error) {
	name := C.CString(path)
	defer C.free(unsafe.Pointer(name))
	var n, status C.int
	buf := C.sci_export_pdf_markdown(name, &n, &status)
	if buf == nil {
		switch status {
		case 2:
			return nil, errors.New("正文超过 48 MiB，无法整篇导出")
		case 3:
			return nil, errors.New("此 PDF 没有可提取的文字层，请先进行 OCR")
		default:
			return nil, errors.New("PDF 无法打开或需要密码")
		}
	}
	defer C.free(unsafe.Pointer(buf))
	return C.GoBytes(unsafe.Pointer(buf), n), nil
}
