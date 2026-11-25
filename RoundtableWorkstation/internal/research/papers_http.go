package research

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"scistation.local/desktop/internal/workspace"
)

func paperReply(w http.ResponseWriter, status int, obj any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(obj)
}
func paperError(w http.ResponseWriter, err error) {
	code := http.StatusInternalServerError
	msg := "无法完成文献操作"
	switch {
	case errors.Is(err, errPDFReaderUnavailable):
		code = 503
		msg = err.Error()
	case errors.Is(err, errRemotePDF):
		code = 502
		msg = err.Error()
	case errors.Is(err, errUnreadablePaperOrganization):
		code = http.StatusUnprocessableEntity
		msg = err.Error()
	case errors.Is(err, errUnreadableBibliography):
		code = http.StatusUnprocessableEntity
		msg = errUnreadableBibliography.Error()
	case errors.Is(err, errInvalidPaper):
		code = 400
		msg = err.Error()
	case errors.Is(err, os.ErrNotExist):
		code = 404
		msg = "未找到文献或文件"
	case errors.Is(err, errPaperConflict) || errors.Is(err, errPaperExists) || errors.Is(err, errPaperOrganizationConflict) ||
		errors.Is(err, errBibliographyConflict):
		code = 409
		msg = err.Error()
	}
	paperReply(w, code, map[string]string{"error": msg})
}
func paperDecode(r io.Reader, into any) error {
	d := json.NewDecoder(r)
	if err := d.Decode(into); err != nil {
		return fmt.Errorf("%w：请求格式错误", errInvalidPaper)
	}
	var trailing any
	if d.Decode(&trailing) != io.EOF {
		return errInvalidPaper
	}
	return nil
}
func paperMethod(w http.ResponseWriter, allow string) {
	w.Header().Set("Allow", allow)
	paperReply(w, 405, map[string]string{"error": "请求方法不适用"})
}
func (s *PaperLibrary) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	base := "/api/research/papers"
	if r.URL.Path != base && !strings.HasPrefix(r.URL.Path, base+"/") {
		http.NotFound(w, r)
		return
	}
	path := strings.Trim(strings.TrimPrefix(r.URL.Path, base), "/")
	if path == "" {
		switch r.Method {
		case "GET":
			papers, err := s.libraryPapers(r.URL.Query())
			if err != nil {
				paperError(w, err)
				return
			}
			paperReply(w, 200, papers)
		case "POST":
			s.importHTTP(w, r, false)
		default:
			paperMethod(w, "GET, POST")
		}
		return
	}
	chunks := strings.Split(path, "/")
	if len(chunks) == 1 {
		switch chunks[0] {
		case "preview":
			if r.Method != "POST" {
				paperMethod(w, "POST")
				return
			}
			s.importHTTP(w, r, true)
			return
		case "organization":
			s.organizationHTTP(w, r)
			return
		case "bibliography":
			s.workspaceBibliographyHTTP(w, r)
			return
		case "bibtex":
			if r.Method != "GET" {
				paperMethod(w, "GET")
				return
			}
			papers, err := s.libraryPapers(r.URL.Query())
			if err != nil {
				paperError(w, err)
				return
			}
			sendBibtex(w, papers)
			return
		case "graph":
			if r.Method != "GET" {
				paperMethod(w, "GET")
				return
			}
			paperReply(w, 200, paperGraph(filterPapers(s.all(), r.URL.Query().Get("project"), "", "")))
			return
		case "recommendations":
			if r.Method != "GET" {
				paperMethod(w, "GET")
				return
			}
			s.recommendHTTP(w, r)
			return
		}
	}
	id := chunks[0]
	p, ok := s.Snapshot(id)
	if !ok {
		paperError(w, os.ErrNotExist)
		return
	}
	if len(chunks) == 1 {
		switch r.Method {
		case "GET":
			paperReply(w, 200, p)
		case "PUT", "PATCH":
			var fields map[string]json.RawMessage
			if err := paperDecode(http.MaxBytesReader(w, r.Body, 4<<20), &fields); err != nil {
				paperError(w, err)
				return
			}
			var rev int
			if json.Unmarshal(fields["revision"], &rev) != nil || rev < 1 {
				paperError(w, fmt.Errorf("%w：缺少论文版本", errInvalidPaper))
				return
			}
			delete(fields, "revision")
			if updates, present := fields["project_links"]; present {
				if err := applyPaperLinkPatch(&p.PaperMetadata, updates); err != nil {
					paperError(w, err)
					return
				}
				delete(fields, "project_links")
			}
			for key := range fields {
				switch key {
				case "title", "authors", "year", "doi", "arxiv", "url", "abstract", "tags", "project_ids", "core_project_ids", "citekey", "status", "notes", "references", "priority", "rating":
				case "collection_id", "publication_title", "publisher", "volume", "issue", "pages", "item_type", "categories", "bibtex":
				default:
					paperError(w, fmt.Errorf("%w：不支持字段 %s", errInvalidPaper, key))
					return
				}
			}
			fieldsJSON, _ := json.Marshal(fields)
			if err := json.Unmarshal(fieldsJSON, &p.PaperMetadata); err != nil {
				paperError(w, errInvalidPaper)
				return
			}
			updated, err := s.update(id, rev, p.PaperMetadata)
			if err != nil {
				paperError(w, err)
				return
			}
			paperReply(w, 200, updated)
		case "DELETE":
			rev, _ := strconv.Atoi(r.URL.Query().Get("revision"))
			if err := s.remove(id, rev); err != nil {
				paperError(w, err)
				return
			}
			w.WriteHeader(204)
		default:
			paperMethod(w, "GET, PUT, PATCH, DELETE")
		}
		return
	}
	switch chunks[1] {
	case "citation":
		if len(chunks) == 2 {
			citationHTTP(w, r, p)
			return
		}
	case "verify-evidence":
		if len(chunks) == 2 {
			s.verifyPDFEvidenceHTTP(w, r, p)
			return
		}
	case "reading-position":
		if len(chunks) == 2 {
			s.updatePDFReadingPositionHTTP(w, r, p.ID)
			return
		}
	case "pages":
		readerPages(w, r, s, id, chunks[2:])
		return
	case "annotations":
		if len(chunks) > 3 {
			http.NotFound(w, r)
			return
		}
		s.annotationsHTTP(w, r, p, chunks[2:])
		return
	case "bibtex":
		if len(chunks) == 2 {
			if r.Method != "GET" {
				paperMethod(w, "GET")
				return
			}
			sendBibtex(w, []Paper{p})
			return
		}
	case "pdf":
		if len(chunks) == 2 {
			s.paperPDF(w, r, p)
			return
		}
	case "markdown":
		if len(chunks) == 2 {
			s.downloadMarkdown(w, r, p)
			return
		}

	}
	http.NotFound(w, r)
}

// Updates name only the projects and fields the caller edited. Archived or
// hidden links stay intact when a different project's reading choices change.
func applyPaperLinkPatch(metadata *PaperMetadata, raw json.RawMessage) error {
	var patch map[string]json.RawMessage
	if json.Unmarshal(raw, &patch) != nil || patch == nil || len(patch) > 512 {
		return errInvalidPaper
	}
	if metadata.ProjectLinks == nil {
		metadata.ProjectLinks = map[string]PaperProjectLink{}
	}
	for project, values := range patch {
		var fields map[string]json.RawMessage
		if json.Unmarshal(values, &fields) != nil || fields == nil {
			return errInvalidPaper
		}
		for key := range fields {
			switch key {
			case "is_pinned", "sort_order", "folder_path", "use_for":
			default:
				return fmt.Errorf("%w：不支持的项目文献字段 %s", errInvalidPaper, key)
			}
		}
		link := metadata.ProjectLinks[project]
		if err := json.Unmarshal(values, &link); err != nil {
			return errInvalidPaper
		}
		metadata.ProjectLinks[project] = link
	}
	return nil
}

func (s *PaperLibrary) remove(id string, revision int) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	p, ok := s.records[id]
	if !ok {
		return os.ErrNotExist
	}
	if revision < 1 || revision != p.Revision {
		return errPaperConflict
	}
	lock, err := s.lockRecords()
	if err != nil {
		return err
	}
	defer lock.Close()
	if _, err = s.currentRecord(id); err != nil {
		return err
	}
	if err := workspace.ManagedRemove(filepath.Join(s.dir, "records", id+".json")); err != nil {
		return err
	}
	delete(s.records, id)
	if p.HasPDF {
		if err := workspace.ManagedRemove(filepath.Join(s.dir, "pdf", id+".pdf")); err != nil && !errors.Is(err, os.ErrNotExist) {
			return err
		}
	}
	return nil
}
func (s *PaperLibrary) importHTTP(w http.ResponseWriter, r *http.Request, preview bool) {
	var input paperImport
	var temp, digest, warning, metadataWarning string
	var err error
	if strings.HasPrefix(r.Header.Get("Content-Type"), "multipart/form-data") {
		r.Body = http.MaxBytesReader(w, r.Body, maxPaperPDF+(4<<20))
		if err = r.ParseMultipartForm(2 << 20); err != nil {
			if r.MultipartForm != nil {
				r.MultipartForm.RemoveAll()
			}
			paperError(w, fmt.Errorf("%w：文件过大或表单无效", errInvalidPaper))
			return
		}
		defer r.MultipartForm.RemoveAll()
		if field := r.FormValue("metadata"); field != "" {
			if err = paperDecode(strings.NewReader(field), &input); err != nil {
				paperError(w, err)
				return
			}
		}
		if err = input.prepare(); err != nil {
			paperError(w, err)
			return
		}
		f, h, e := r.FormFile("file")
		if e != nil {
			paperError(w, fmt.Errorf("%w：缺少 file", errInvalidPaper))
			return
		}
		temp, digest, err = s.stagePDF(r.Context(), f)
		f.Close()
		if err != nil {
			paperError(w, err)
			return
		}
		defer workspace.ManagedRemove(temp)
		input.MetadataSource = ""
		input.readLocalMetadata(r.Context(), temp, h.Filename)
		input.SkipLookup = true
		_, err = enrichPaper(r.Context(), &input)
		if err != nil {
			paperError(w, err)
			return
		}
	} else {
		if err = paperDecode(http.MaxBytesReader(w, r.Body, 4<<20), &input); err != nil {
			paperError(w, err)
			return
		}
		input.MetadataSource = ""
		metadataWarning, err = enrichPaper(r.Context(), &input)
		if err != nil {
			if r.Context().Err() != nil {
				paperReply(w, http.StatusRequestTimeout, map[string]string{"error": "导入已取消"})
				return
			}
			paperError(w, err)
			return
		}
		if !preview && input.FetchPDF {
			from := input.PDFURL
			if from == "" {
				from = input.URL
			}
			temp, digest, err = s.downloadPDF(r.Context(), from)
			if err != nil {
				if r.Context().Err() != nil {
					paperReply(w, http.StatusRequestTimeout, map[string]string{"error": "导入已取消"})
					return
				}
				if !errors.Is(err, errRemotePDF) && !errors.Is(err, errInvalidPaper) {
					paperError(w, err)
					return
				}
				if !input.AllowLinkOnly || !(paperHTTPURL(input.URL) || input.Arxiv != "" || input.DOI != "") {
					paperError(w, fmt.Errorf("%w；可关闭下载后仅保存文献链接", err))
					return
				}
				warning = err.Error()
			} else {
				defer workspace.ManagedRemove(temp)
			}
		}
	}
	if r.Context().Err() != nil {
		paperReply(w, http.StatusRequestTimeout, map[string]string{"error": "导入已取消"})
		return
	}
	if input.ImportCollection != nil {
		input.CollectionID = *input.ImportCollection
		input.collectionExplicit = true
	}
	if preview {
		organization, _, err := s.readOrganization()
		if err != nil {
			paperError(w, err)
			return
		}
		if !input.collectionExplicit && organization.Library != nil {
			input.CollectionID = organization.Library.DefaultCollection
		}
		if input.CollectionID != "" {
			if _, exists := organization.Collections[input.CollectionID]; !exists {
				paperError(w, fmt.Errorf("%w：文献集合不存在", errInvalidPaper))
				return
			}
		}
		if err := s.validate(&input.PaperMetadata, nil); err != nil {
			paperError(w, err)
			return
		}
		existing, err := s.findImport(input.PaperMetadata, digest)
		if err != nil {
			paperError(w, err)
			return
		}
		paperReply(w, http.StatusOK, paperImportPreview{
			PaperMetadata: input.PaperMetadata, ExistingPaperID: existing.ID, ExistingTitle: existing.Title,
			HasLocalPDF: temp != "", MetadataWarning: metadataWarning,
		})
		return
	}
	rec, created, err := s.create(input.PaperMetadata, temp, digest)
	if err != nil {
		paperError(w, err)
		return
	}
	status := http.StatusOK
	if created {
		status = http.StatusCreated
	}
	if rec.HasPDF {
		warning = ""
	}
	paperReply(w, status, struct {
		Paper
		ImportWarning   string `json:"import_warning,omitempty"`
		MetadataWarning string `json:"metadata_warning,omitempty"`
	}{rec, warning, metadataWarning})
}

type paperImportPreview struct {
	PaperMetadata
	ExistingPaperID string `json:"existing_paper_id,omitempty"`
	ExistingTitle   string `json:"existing_title,omitempty"`
	HasLocalPDF     bool   `json:"has_local_pdf,omitempty"`
	MetadataWarning string `json:"metadata_warning,omitempty"`
}

func validAnnotation(a *PaperAnnotation) bool {
	if a.Kind == "" {
		a.Kind = "highlight"
	}
	if a.Kind != "highlight" && a.Kind != "underline" && a.Kind != "note" {
		return false
	}
	if a.Color == "" {
		a.Color = "#ffdd55"
	}
	if a.Page <= 0 || a.Page > 1000000 || len(a.Note) > 65536 || len(a.SelectedText) > 131072 || len(a.Rects) > 2048 || len(a.Color) > 40 {
		return false
	}
	if !validPDFSelectionRange(a.SelectionStart, a.SelectionEnd) || (a.SelectionStart != nil || a.OCR) && strings.TrimSpace(a.SelectedText) == "" {
		return false
	}
	if strings.TrimSpace(a.Note) == "" && strings.TrimSpace(a.SelectedText) == "" && len(a.Rects) == 0 {
		return false
	}
	for _, rect := range a.Rects {
		if rect.Width <= 0 || rect.Height <= 0 {
			return false
		}
	}
	return true
}
func (s *PaperLibrary) annotationsHTTP(w http.ResponseWriter, r *http.Request, p Paper, tail []string) {
	if r.Method == "GET" && len(tail) == 0 {
		paperReply(w, 200, p.Annotations)
		return
	}
	var req PaperAnnotation
	if r.Method == "POST" && len(tail) == 0 || r.Method == "PUT" && len(tail) == 1 {
		if e := paperDecode(http.MaxBytesReader(w, r.Body, 1<<20), &req); e != nil {
			paperError(w, e)
			return
		}
		if !validAnnotation(&req) {
			paperError(w, errInvalidPaper)
			return
		}
	} else if r.Method != "DELETE" || len(tail) != 1 {
		paperMethod(w, "GET, POST, PUT, DELETE")
		return
	}
	s.mu.Lock()
	p, ok := s.records[p.ID]
	if !ok {
		s.mu.Unlock()
		paperError(w, os.ErrNotExist)
		return
	}
	p = clonePaper(p)
	// Appends are independent. Edits and deletions must name the revision read.
	if raw := r.URL.Query().Get("revision"); raw != "" || len(tail) == 1 {
		rev, _ := strconv.Atoi(raw)
		if rev < 1 || rev != p.Revision {
			s.mu.Unlock()
			paperError(w, errPaperConflict)
			return
		}
	}
	code := 200
	if len(tail) == 0 {
		req.ID = paperID()
		req.CreatedAt = time.Now().UTC()
		p.Annotations = append(p.Annotations, req)
		code = 201
	} else {
		i := -1
		for n, a := range p.Annotations {
			if a.ID == tail[0] {
				i = n
				break
			}
		}
		if i < 0 {
			s.mu.Unlock()
			paperError(w, os.ErrNotExist)
			return
		}
		if r.Method == "DELETE" {
			p.Annotations = append(p.Annotations[:i], p.Annotations[i+1:]...)
			code = 204
		} else {
			req.ID = tail[0]
			req.CreatedAt = p.Annotations[i].CreatedAt
			p.Annotations[i] = req
		}
	}
	changePaper(&p)
	err := s.saveLocked(p)
	s.mu.Unlock()
	if err != nil {
		paperError(w, err)
		return
	}
	if code == 204 {
		w.WriteHeader(code)
	} else {
		paperReply(w, code, req)
	}
}
func (s *PaperLibrary) recommendHTTP(w http.ResponseWriter, r *http.Request) {
	if r.URL.Query().Get("source") == "arxiv" {
		q := strings.TrimSpace(r.URL.Query().Get("q"))
		if q == "" || len(q) > 512 {
			paperError(w, fmt.Errorf("%w：请输入检索词", errInvalidPaper))
			return
		}
		ctx, cancel := context.WithTimeout(r.Context(), 12*time.Second)
		defer cancel()
		items, err := arxivPaperSearch(ctx, url.Values{"search_query": {"all:" + q}, "start": {"0"}, "max_results": {"20"}, "sortBy": {"relevance"}})
		if err != nil {
			paperReply(w, 502, map[string]string{"error": "arXiv 搜索暂时不可用"})
			return
		}
		paperReply(w, 200, items)
		return
	}
	project := r.URL.Query().Get("project")
	paperReply(w, 200, rankPapers(filterPapers(s.all(), project, "", ""), project))
}
