//go:build !darwin || !cgo

package research

import (
	"context"
	"errors"
	"fmt"
	"os/exec"
	"strconv"
	"strings"
)

func nativePDFPage(path, operation string, page int, query string) ([]byte, error) {
	return nil, errors.New("当前构建未启用 macOS PDFKit；仍可打开 PDF 原件")
}

// Headless builds without PDFKit can validate with Poppler's PDF parser.
func validatePaperPDF(ctx context.Context, path string) error {
	executable, err := exec.LookPath("pdfinfo")
	if err != nil {
		return fmt.Errorf("%w：请安装 Poppler 的 pdfinfo", errPDFReaderUnavailable)
	}
	cmd := exec.CommandContext(ctx, executable, "-f", "1", "-l", "1", path)
	cmd.Env = append(cmd.Environ(), "LC_ALL=C")
	output, err := cmd.Output()
	if ctx.Err() != nil {
		return ctx.Err()
	}
	if err == nil {
		for _, line := range strings.Split(string(output), "\n") {
			if pages, ok := strings.CutPrefix(line, "Pages:"); ok {
				if n, e := strconv.Atoi(strings.TrimSpace(pages)); e == nil && n > 0 {
					return nil
				}
			}
		}
	}
	return fmt.Errorf("%w：PDF 无法打开或没有可读页面", errInvalidPaper)
}
