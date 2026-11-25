package research

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"syscall"
	"unicode/utf16"
)

// PDFKit reports positions in UTF-16 code units, which also index the
// browser's text layer. A missing range denotes an older quote-only locator.
func validPDFSelectionRange(start, end *int) bool {
	if start == nil || end == nil {
		return start == nil && end == nil
	}
	return *start >= 0 && *end > *start
}

// VerifyPDFEvidence reads the original PDF and checks the cited excerpt.
func (s *PaperLibrary) VerifyPDFEvidence(ctx context.Context, e Evidence) error {
	p, ok := s.Snapshot(e.PaperID)
	if !ok {
		return os.ErrNotExist
	}
	return s.verifyPDFEvidence(ctx, e, p)
}

// The caller supplies a paper already resolved in this library. This also
// allows an approval to retain its read lock while checking the source bytes.
func (s *PaperLibrary) verifyPDFEvidence(ctx context.Context, e Evidence, p Paper) error {
	if strings.TrimSpace(e.Quote) == "" || len(e.Quote) > 128<<10 || !validPDFSelectionRange(e.SelectionStart, e.SelectionEnd) {
		return fmt.Errorf("%w：PDF 摘录位置无效", errInvalidPaper)
	}
	text, err := s.verifiedPageText(ctx, p, e)
	if err != nil {
		return err
	}
	if !matchesPDFQuote(text, e) {
		return fmt.Errorf("%w：指定位置的文字与摘录不同", errPaperConflict)
	}
	return ctx.Err()
}

// Parse the same bytes used to establish the source fingerprint for readers,
// AI Lab previews and approval-time replay.
func (s *PaperLibrary) verifiedPageText(ctx context.Context, p Paper, e Evidence) (string, error) {
	if p.ID != e.PaperID || !libraryIDPattern.MatchString(e.PaperID) || e.Page < 1 || e.Page > 1000000 {
		return "", fmt.Errorf("%w：PDF 摘录位置无效", errInvalidPaper)
	}
	if !p.HasPDF || len(e.SourceHash) != sha256.Size*2 || e.SourceHash != p.FileSHA256 {
		return "", fmt.Errorf("%w：来源 PDF 指纹不同", errPaperConflict)
	}
	select {
	case pageWorkers <- struct{}{}:
		defer func() { <-pageWorkers }()
	case <-ctx.Done():
		return "", ctx.Err()
	}
	root, err := os.OpenRoot(s.dir)
	if err != nil {
		return "", err
	}
	defer root.Close()
	f, err := root.OpenFile(filepath.Join("pdf", p.ID+".pdf"), os.O_RDONLY|syscall.O_NONBLOCK, 0)
	if err != nil {
		return "", err
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil {
		return "", err
	}
	if !info.Mode().IsRegular() || info.Size() < 1 || info.Size() > maxPaperPDF {
		return "", fmt.Errorf("%w：来源 PDF 不可读取", errInvalidPaper)
	}
	// Parse exactly the bytes that were hashed, even when an external process
	// replaces the path during verification.
	pdf := make([]byte, info.Size())
	if _, err := io.ReadFull(f, pdf); err != nil {
		return "", err
	}
	var extra [1]byte
	n, readErr := f.Read(extra[:])
	if readErr != nil && readErr != io.EOF {
		return "", readErr
	}
	digest := sha256.Sum256(pdf)
	if n != 0 || hex.EncodeToString(digest[:]) != e.SourceHash {
		return "", fmt.Errorf("%w：来源 PDF 指纹不同", errPaperConflict)
	}
	if err := ctx.Err(); err != nil {
		return "", err
	}
	text, err := readPDFEvidenceText(ctx, pdf, e)
	if err != nil {
		return "", fmt.Errorf("无法核对 PDF 摘录：%w", err)
	}
	return text, ctx.Err()
}

func matchesPDFQuote(text string, e Evidence) bool {
	if e.SelectionStart == nil {
		return strings.Contains(text, e.Quote)
	}
	units := utf16.Encode([]rune(text))
	quote := utf16.Encode([]rune(e.Quote))
	start, end := *e.SelectionStart, *e.SelectionEnd
	return end <= len(units) && slices.Equal(units[start:end], quote)
}

func (s *PaperLibrary) verifyPDFEvidenceHTTP(w http.ResponseWriter, r *http.Request, p Paper) {
	if r.Method != http.MethodPost {
		paperMethod(w, "POST")
		return
	}
	var evidence Evidence
	if err := paperDecode(http.MaxBytesReader(w, r.Body, 768<<10), &evidence); err != nil {
		paperError(w, err)
		return
	}
	evidence.PaperID = p.ID
	if err := s.verifyPDFEvidence(r.Context(), evidence, p); err != nil {
		paperError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
