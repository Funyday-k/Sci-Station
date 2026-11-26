//go:build !darwin || !cgo

package research

import "errors"

func documentMarkdown(path string) ([]byte, error) {
	return nil, errors.New("本地 PDF 正文导出需要 macOS 版 Sci-Station")
}

func documentMarkdownBytes(_ []byte) ([]byte, error) { return documentMarkdown("") }
