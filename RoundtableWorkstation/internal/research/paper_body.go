package research

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"unicode"
	"unicode/utf8"

	"scistation.local/desktop/internal/workspace"
)

const maxPaperBody = 48 << 20

// Old paper records have no markdown_source. Its absence means no source text
// has been imported or adopted, independently of PDF, notes and metadata.
type PaperMarkdown struct {
	Version  int    `json:"version"`
	Revision int    `json:"revision"`
	BlobID   string `json:"blob_id"`
	Hash     string `json:"sha256"`
	Origin   string `json:"origin"`
	PDFHash  string `json:"pdf_sha256,omitempty"`
	Bytes    int    `json:"bytes"`
}

func (s *PaperLibrary) bodyPath(paperID, id string) string {
	return filepath.Join(s.dir, "markdown", paperID+"-"+id+".md")
}

func (m PaperMarkdown) valid() bool {
	if m.Origin == "import" {
		if m.PDFHash != "" {
			return false
		}
	} else {
		if m.Origin != "pdfkit" && m.Origin != "mineru" {
			return false
		}
		if _, err := hex.DecodeString(m.PDFHash); err != nil || len(m.PDFHash) != 64 {
			return false
		}
	}
	_, err := hex.DecodeString(m.Hash)
	return m.Version == 1 && m.Revision > 0 && validID(m.BlobID) && err == nil && len(m.Hash) == 64 && m.Bytes > 0 && m.Bytes <= maxPaperBody
}

func realMarkdownBody(data []byte) bool {
	if len(data) == 0 || len(data) > maxPaperBody || !utf8.Valid(data) || bytes.IndexByte(data, 0) >= 0 {
		return false
	}
	text := strings.TrimPrefix(string(data), "\ufeff")
	lower := strings.ToLower(text)
	if strings.Contains(lower, "status: not_extracted") || strings.Contains(lower, "pdf text has not been extracted yet") || strings.Contains(lower, "not_performed_template_only") || strings.Contains(lower, "is ready for an evidence-backed structured note.") {
		return false
	}
	front, comment := false, false
	for i, line := range strings.Split(strings.ReplaceAll(text, "\r\n", "\n"), "\n") {
		line = strings.TrimSpace(line)
		if comment {
			if strings.Contains(line, "-->") {
				comment = false
			}
			continue
		}
		if strings.HasPrefix(line, "<!--") {
			comment = !strings.Contains(line, "-->")
			continue
		}
		if i == 0 && line == "---" {
			front = true
			continue
		}
		if front {
			if line == "---" || line == "..." {
				front = false
			}
			continue
		}
		if line == "" || strings.HasPrefix(line, "#") || strings.HasPrefix(line, "<!--") || line == "_此页没有可提取的文本。_" {
			continue
		}
		if key, _, ok := strings.Cut(line, ":"); ok {
			switch strings.ToLower(strings.TrimLeft(strings.TrimSpace(key), "- ")) {
			case "title", "authors", "author", "year", "doi", "arxiv", "url", "tags", "citekey", "source", "status":
				continue
			}
		}
		if strings.IndexFunc(line, func(r rune) bool { return unicode.IsLetter(r) || unicode.IsNumber(r) }) >= 0 {
			return true
		}
	}
	return false
}

func (s *PaperLibrary) readBodyLocked(p Paper) ([]byte, error) {
	if p.Markdown == nil {
		return nil, fmt.Errorf("%w：尚无已导入或转换的 Markdown 正文", os.ErrNotExist)
	}
	m := *p.Markdown
	if !m.valid() {
		return nil, fmt.Errorf("%w：正文记录版本或字段无效", errInvalidPaper)
	}
	disk, err := workspace.ManagedReadFile(filepath.Join(s.dir, "records", p.ID+".json"))
	if err != nil {
		return nil, err
	}
	if sha256.Sum256(disk) != p.diskHash {
		return nil, errPaperConflict
	}
	f, err := workspace.ManagedOpenFile(s.bodyPath(p.ID, m.BlobID), os.O_RDONLY, 0)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	b, err := io.ReadAll(io.LimitReader(f, int64(m.Bytes)+1))
	if err != nil {
		return nil, err
	}
	if len(b) != m.Bytes || fmt.Sprintf("%x", sha256.Sum256(b)) != m.Hash {
		return nil, fmt.Errorf("%w：Markdown 正文校验失败", errPaperConflict)
	}
	return b, nil
}

func (s *PaperLibrary) storeBody(id string, revision int, data []byte, origin, pdfHash string) (Paper, error) {
	if !realMarkdownBody(data) {
		return Paper{}, fmt.Errorf("%w：文件为空、只有元数据/占位内容，或不是有效的 UTF-8 Markdown 正文", errInvalidPaper)
	}
	hash := fmt.Sprintf("%x", sha256.Sum256(data))
	s.mu.Lock()
	defer s.mu.Unlock()
	p, ok := s.records[id]
	if !ok {
		return Paper{}, os.ErrNotExist
	}
	if _, err := s.currentRecord(id); err != nil {
		return Paper{}, err
	}
	if pdfHash != "" && (!p.HasPDF || p.FileSHA256 != pdfHash) {
		return Paper{}, errPaperConflict
	}
	if p.Markdown != nil {
		if !p.Markdown.valid() {
			return Paper{}, fmt.Errorf("%w：无法更新未知版本的正文", errInvalidPaper)
		}
		if p.Markdown.Hash == hash && p.Markdown.Origin == origin && p.Markdown.PDFHash == pdfHash {
			if _, err := s.readBodyLocked(p); err != nil {
				return Paper{}, err
			}
			return clonePaper(p), nil
		}
	}
	if p.Revision != revision {
		return Paper{}, errPaperConflict
	}
	bodyRev := 1
	prior := p.Markdown
	if prior != nil {
		bodyRev = prior.Revision + 1
	}
	m := &PaperMarkdown{Version: 1, Revision: bodyRev, BlobID: makeID(), Hash: hash, Origin: origin, PDFHash: pdfHash, Bytes: len(data)}
	path := s.bodyPath(p.ID, m.BlobID)
	if err := workspace.ManagedAtomicWrite(path, data); err != nil {
		return Paper{}, err
	}
	p.Markdown = m
	changePaper(&p)
	if err := s.saveLocked(p); err != nil {
		_ = workspace.ManagedRemove(path)
		return Paper{}, err
	}
	if prior != nil {
		_ = workspace.ManagedRemove(s.bodyPath(p.ID, prior.BlobID))
	}
	return clonePaper(p), nil
}

func (s *PaperLibrary) convertedMarkdown(ctx context.Context, p Paper) ([]byte, error) {
	if !p.HasPDF {
		return nil, fmt.Errorf("%w：没有可转换的本地 PDF，请导入 Markdown 正文", errInvalidPaper)
	}
	select {
	case markdownConversions <- struct{}{}:
		defer func() { <-markdownConversions }()
	case <-ctx.Done():
		return nil, ctx.Err()
	}
	pdf, err := s.verifiedPDFBytes(ctx, p)
	if err != nil {
		return nil, err
	}
	body, err := documentMarkdownBytes(pdf)
	if err != nil {
		return nil, fmt.Errorf("%w：转换失败，%s", errInvalidPaper, err)
	}
	if err = ctx.Err(); err != nil {
		return nil, err
	}
	return append([]byte("# "+strings.Join(strings.Fields(p.Title), " ")+"\n\n"), body...), nil
}

func (s *PaperLibrary) convertBody(ctx context.Context, p Paper, revision int) (Paper, error) {
	body, err := s.convertedMarkdown(ctx, p)
	if err != nil {
		return Paper{}, err
	}
	return s.storeBody(p.ID, revision, body, "pdfkit", p.FileSHA256)
}

// Called only with a completed, authenticated conversion response for the
// expected paper and original PDF fingerprint.
func (s *Service) SaveMinerMarkdown(ctx context.Context, id string, revision int, pdfHash string, data []byte) (Paper, error) {
	p, _, err := s.ConversionOriginal(ctx, id)
	if err != nil {
		return Paper{}, err
	}
	if p.FileSHA256 != pdfHash {
		return Paper{}, errPaperConflict
	}
	return s.papers.storeBody(id, revision, data, "mineru", pdfHash)
}

func (s *PaperLibrary) bodyHTTP(w http.ResponseWriter, r *http.Request, p Paper) {
	switch r.Method {
	case http.MethodGet:
		s.mu.RLock()
		data, err := s.readBodyLocked(p)
		s.mu.RUnlock()
		if p.Markdown == nil {
			paperReply(w, 404, map[string]string{"error": "尚无论文 Markdown 正文，请导入文件或转换本地 PDF", "state": "missing"})
			return
		}
		if err != nil {
			paperError(w, err)
			return
		}
		w.Header().Set("Content-Type", "text/markdown; charset=utf-8")
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Write(data)
	case http.MethodPost:
		var revision int
		var rec Paper
		var err error
		if strings.HasPrefix(r.Header.Get("Content-Type"), "multipart/form-data") {
			r.Body = http.MaxBytesReader(w, r.Body, maxPaperBody+(1<<20))
			if err = r.ParseMultipartForm(1 << 20); err != nil {
				if r.MultipartForm != nil {
					r.MultipartForm.RemoveAll()
				}
				paperError(w, errInvalidPaper)
				return
			}
			defer r.MultipartForm.RemoveAll()
			revision, _ = strconv.Atoi(r.FormValue("revision"))
			f, h, openErr := r.FormFile("file")
			if openErr != nil {
				paperError(w, errInvalidPaper)
				return
			}
			defer f.Close()
			ext := strings.ToLower(filepath.Ext(h.Filename))
			if revision < 1 || len(r.MultipartForm.File["file"]) != 1 || (ext != ".md" && ext != ".markdown") || h.Size > maxPaperBody {
				paperError(w, errInvalidPaper)
				return
			}
			var data []byte
			data, err = io.ReadAll(io.LimitReader(f, maxPaperBody+1))
			if err == nil {
				rec, err = s.storeBody(p.ID, revision, data, "import", "")
			}
		} else {
			var input struct {
				Action   string `json:"action"`
				Revision int    `json:"revision"`
			}
			if err = paperDecode(http.MaxBytesReader(w, r.Body, 4096), &input); err != nil || input.Action != "convert" || input.Revision < 1 {
				paperError(w, errInvalidPaper)
				return
			}
			rec, err = s.convertBody(r.Context(), p, input.Revision)
		}
		if err != nil {
			paperError(w, err)
			return
		}
		paperReply(w, 200, rec)
	default:
		paperMethod(w, "GET, POST")
	}
}

func (s *Service) ConversionOriginal(ctx context.Context, id string) (Paper, []byte, error) {
	p, ok := s.papers.Snapshot(id)
	if !ok || !p.HasPDF {
		return Paper{}, nil, os.ErrNotExist
	}
	pdf, err := s.papers.verifiedPDFBytes(ctx, p)
	return p, pdf, err
}
func (s *Service) ConversionPaper(id string) (Paper, bool) { return s.papers.Snapshot(id) }
