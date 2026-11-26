//go:build !darwin || !cgo || nogui

package meeting

import "errors"

func nativeMaterialVisualExcerpt(path, mimeType, ext string) (string, error) {
	return "", errors.New("PDF and image extraction requires the macOS native Vision/PDFKit build; no content was extracted")
}
