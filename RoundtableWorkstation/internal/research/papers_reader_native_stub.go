//go:build !darwin || !cgo

package research

import "errors"

func nativePDFPage(path, operation string, page int, query string) ([]byte, error) {
	return nil, errors.New("当前构建未启用 macOS PDFKit；仍可打开 PDF 原件")
}
