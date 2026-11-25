//go:build darwin && cgo

package research

/*
#cgo CFLAGS: -fobjc-arc
#cgo LDFLAGS: -framework Foundation -framework AppKit -framework CoreGraphics -framework ImageIO -framework PDFKit -framework Vision
#include <stdlib.h>
void *sci_reader_page(const char *path, const void *pdf, size_t pdf_length, const char *operation, int page, const char *query, int *length, int *is_error);
*/
import "C"

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"unsafe"
)

func nativePDFPage(path, operation string, page int, query string) ([]byte, error) {
	filename := C.CString(path)
	defer C.free(unsafe.Pointer(filename))
	return readNativePDFPage(filename, nil, operation, page, query)
}

func readPDFEvidenceText(_ context.Context, pdf []byte, evidence Evidence) (string, error) {
	op := "text"
	if evidence.OCR {
		op = "ocr"
	}
	data, err := readNativePDFPage(nil, pdf, op, evidence.Page, "")
	if err != nil {
		return "", err
	}
	var page struct {
		Text string `json:"text"`
	}
	err = json.Unmarshal(data, &page)
	return page.Text, err
}

func readNativePDFPage(filename *C.char, pdf []byte, operation string, page int, query string) ([]byte, error) {
	op, q := C.CString(operation), C.CString(query)
	defer C.free(unsafe.Pointer(op))
	defer C.free(unsafe.Pointer(q))
	var length, failed C.int
	buf := C.sci_reader_page(filename, unsafe.Pointer(unsafe.SliceData(pdf)), C.size_t(len(pdf)), op, C.int(page), q, &length, &failed)
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

func validatePaperPDF(ctx context.Context, path string) error {
	select {
	case pageWorkers <- struct{}{}:
		defer func() { <-pageWorkers }()
	case <-ctx.Done():
		return ctx.Err()
	}
	if _, err := nativePDFPage(path, "info", 0, ""); err != nil {
		return fmt.Errorf("%w：%v", errInvalidPaper, err)
	}
	return ctx.Err()
}
