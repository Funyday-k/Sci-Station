package research

import (
	"fmt"
	"mime"
	"net/http"
	"os"
	"strconv"
	"strings"

	"scistation.local/desktop/internal/workspace"
)

var markdownConversions = make(chan struct{}, 2)

func (s *PaperLibrary) downloadMarkdown(w http.ResponseWriter, r *http.Request, p Paper) {
	if r.Method != "GET" {
		paperMethod(w, "GET")
		return
	}
	path, err := s.PDFPath(p.ID)
	if err != nil {
		paperError(w, err)
		return
	}
	select {
	case markdownConversions <- struct{}{}:
		defer func() { <-markdownConversions }()
	case <-r.Context().Done():
		return
	}
	body, err := documentMarkdown(path)
	if err != nil {
		paperReply(w, 422, map[string]string{"error": err.Error()})
		return
	}
	w.Header().Set("Content-Type", "text/markdown; charset=utf-8")
	w.Header().Set("Content-Disposition", mime.FormatMediaType("attachment", map[string]string{"filename": p.Citekey + ".md"}))
	w.Header().Set("X-Content-Type-Options", "nosniff")
	fmt.Fprintf(w, "# %s\n\n", strings.Join(strings.Fields(p.Title), " "))
	_, _ = w.Write(body)
}

func (s *PaperLibrary) attachPDF(w http.ResponseWriter, r *http.Request, p Paper) {
	if p.HasPDF {
		paperReply(w, 409, map[string]string{"error": "此论文已有关联的 PDF"})
		return
	}
	var tmp, digest string
	var err error
	if strings.HasPrefix(r.Header.Get("Content-Type"), "multipart/form-data") {
		r.Body = http.MaxBytesReader(w, r.Body, maxPaperPDF+(2<<20))
		if err := r.ParseMultipartForm(2 << 20); err != nil {
			if r.MultipartForm != nil {
				r.MultipartForm.RemoveAll()
			}
			paperError(w, fmt.Errorf("%w：PDF 上传失败", errInvalidPaper))
			return
		}
		defer r.MultipartForm.RemoveAll()
		file, _, errOpen := r.FormFile("file")
		if errOpen != nil {
			paperError(w, errInvalidPaper)
			return
		}
		tmp, digest, err = s.stagePDF(r.Context(), file)
		file.Close()
	} else {
		var body struct {
			URL string `json:"url"`
		}
		if r.ContentLength != 0 {
			if err := paperDecode(http.MaxBytesReader(w, r.Body, 32<<10), &body); err != nil {
				paperError(w, err)
				return
			}
		}
		from := strings.TrimSpace(body.URL)
		if from == "" {
			from = p.PDFURL
		}
		if from == "" {
			in := paperImport{PaperMetadata: p.PaperMetadata}
			if _, err = enrichPaper(r.Context(), &in); err != nil {
				paperError(w, err)
				return
			}
			from = firstPaperValue(in.PDFURL, in.URL)
		}
		if from == "" {
			paperError(w, fmt.Errorf("%w：请输入 PDF 链接或上传文件", errInvalidPaper))
			return
		}
		tmp, digest, err = s.downloadPDF(r.Context(), from)
	}
	if err != nil {
		paperError(w, err)
		return
	}
	defer workspace.ManagedRemove(tmp)
	s.mu.Lock()
	current, ok := s.records[p.ID]
	if !ok {
		s.mu.Unlock()
		paperError(w, os.ErrNotExist)
		return
	}
	if current.HasPDF || current.Revision != p.Revision {
		s.mu.Unlock()
		paperError(w, errPaperConflict)
		return
	}
	for id, other := range s.records {
		if id != p.ID && other.FileSHA256 == digest {
			s.mu.Unlock()
			paperError(w, fmt.Errorf("%w：已有相同 PDF，可在现有文献上添加项目关联", errPaperExists))
			return
		}
	}
	changePaper(&current)
	err = s.saveImportLocked(&current, tmp, digest, false)
	s.mu.Unlock()
	if err != nil {
		paperError(w, err)
		return
	}
	paperReply(w, 200, current)
}

func (s *PaperLibrary) paperPDF(w http.ResponseWriter, r *http.Request, p Paper) {
	if r.Method == "POST" {
		s.attachPDF(w, r, p)
		return
	}
	if r.Method != "GET" && r.Method != "HEAD" {
		paperMethod(w, "GET, HEAD, POST")
		return
	}
	file, err := s.PDFPath(p.ID)
	if err != nil {
		paperError(w, err)
		return
	}
	f, err := workspace.ManagedOpenFile(file, os.O_RDONLY, 0)
	if err != nil {
		paperError(w, err)
		return
	}
	defer f.Close()
	w.Header().Set("Content-Type", "application/pdf")
	w.Header().Set("Content-Disposition", "inline")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("ETag", strconv.Quote(p.FileSHA256))
	http.ServeContent(w, r, p.ID+".pdf", p.CreatedAt, f)
}
