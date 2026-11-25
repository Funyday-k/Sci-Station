//go:build !darwin || !cgo

package research

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"os/exec"
	"strconv"
	"strings"
)

func nativePDFPage(path, operation string, page int, query string) ([]byte, error) {
	return nil, errors.New("当前构建未启用 macOS PDFKit；仍可打开 PDF 原件")
}

// PDFKit ranges and Vision OCR cannot be replayed against Poppler's text
// order. Older quote-only locators can still be checked against the real page.
func readPDFEvidenceText(ctx context.Context, pdf []byte, evidence Evidence) (string, error) {
	if evidence.SelectionStart != nil || evidence.OCR {
		return "", fmt.Errorf("%w：需要 macOS PDFKit", errPDFReaderUnavailable)
	}
	tool, err := exec.LookPath("pdftotext")
	if err != nil {
		return "", fmt.Errorf("%w：请安装 Poppler 的 pdftotext", errPDFReaderUnavailable)
	}
	page := strconv.Itoa(evidence.Page)
	cmd := exec.CommandContext(ctx, tool, "-f", page, "-l", page, "-enc", "UTF-8", "-", "-")
	cmd.Stdin = bytes.NewReader(pdf)
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return "", err
	}
	if err := cmd.Start(); err != nil {
		return "", err
	}
	const maxPageText = 16 << 20
	text, readErr := io.ReadAll(io.LimitReader(stdout, maxPageText+1))
	if readErr != nil || len(text) > maxPageText {
		_ = cmd.Process.Kill()
	}
	waitErr := cmd.Wait()
	if ctx.Err() != nil {
		return "", ctx.Err()
	}
	if readErr != nil || len(text) > maxPageText || waitErr != nil {
		return "", fmt.Errorf("%w：无法读取指定页的文字", errInvalidPaper)
	}
	return string(text), nil
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
