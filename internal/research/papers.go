package research

import (
	"bytes"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
	"unicode/utf8"

	"scistation.local/desktop/internal/workspace"
)

type AnnotationRect struct {
	X      float64 `json:"x"`
	Y      float64 `json:"y"`
	Width  float64 `json:"width"`
	Height float64 `json:"height"`
}
type PaperAnnotation struct {
	ID             string           `json:"id"`
	Page           int              `json:"page"`
	Kind           string           `json:"kind"`
	SelectedText   string           `json:"selected_text"`
	Note           string           `json:"note"`
	Color          string           `json:"color"`
	Rects          []AnnotationRect `json:"rects"`
	CreatedAt      time.Time        `json:"created_at"`
	SelectionStart *int             `json:"selectionStart,omitempty"`
	SelectionEnd   *int             `json:"selectionEnd,omitempty"`
	OCR            bool             `json:"ocr,omitempty"`
}

// A shared paper has one set of reading choices for each project that uses it.
type PaperProjectLink struct {
	IsPinned   bool     `json:"is_pinned"`
	SortOrder  *int     `json:"sort_order"`
	FolderPath string   `json:"folder_path"`
	UseFor     []string `json:"use_for"`
}

func (link *PaperProjectLink) UnmarshalJSON(data []byte) error {
	if bytes.Equal(bytes.TrimSpace(data), []byte("null")) {
		return fmt.Errorf("%w：项目文献设置应为对象", errInvalidPaper)
	}
	type plainLink PaperProjectLink
	return json.Unmarshal(data, (*plainLink)(link))
}

type PaperMetadata struct {
	ProjectLinks     map[string]PaperProjectLink `json:"project_links,omitempty"`
	Title            string                      `json:"title"`
	PublicationTitle string                      `json:"publication_title,omitempty"`
	Publisher        string                      `json:"publisher,omitempty"`
	Volume           string                      `json:"volume,omitempty"`
	Issue            string                      `json:"issue,omitempty"`
	Pages            string                      `json:"pages,omitempty"`
	ItemType         string                      `json:"item_type,omitempty"`
	Categories       []string                    `json:"categories,omitempty"`
	BibTeX           string                      `json:"bibtex,omitempty"`
	Authors          []string                    `json:"authors"`
	Year             int                         `json:"year"`
	DOI              string                      `json:"doi"`
	Arxiv            string                      `json:"arxiv"`
	URL              string                      `json:"url"`
	Abstract         string                      `json:"abstract"`
	Tags             []string                    `json:"tags"`
	CollectionID     string                      `json:"collection_id,omitempty"`
	ProjectIDs       []string                    `json:"project_ids"`
	CoreProjectIDs   []string                    `json:"core_project_ids"`
	Citekey          string                      `json:"citekey"`
	Status           string                      `json:"status"`
	Notes            string                      `json:"notes"`
	References       []string                    `json:"references"`
	Rating           int                         `json:"rating"`
	Priority         int                         `json:"priority"`
	InspireID        string                      `json:"inspire_id,omitempty"`
	PDFURL           string                      `json:"pdf_url,omitempty"`
	MetadataSource   string                      `json:"metadata_source,omitempty"`

	collectionExplicit bool
}
type Paper struct {
	Markdown *PaperMarkdown `json:"markdown_source,omitempty"`
	PaperMetadata
	diskHash        [32]byte
	ID              string              `json:"id"`
	HasPDF          bool                `json:"has_pdf"`
	FileSHA256      string              `json:"file_sha256"`
	Revision        int                 `json:"revision"`
	CreatedAt       time.Time           `json:"created_at"`
	UpdatedAt       time.Time           `json:"updated_at"`
	Annotations     []PaperAnnotation   `json:"annotations"`
	ReadingPosition *PDFReadingPosition `json:"reading_position,omitempty"`
}
type PaperLibrary struct {
	dir        string
	dirInfo    os.FileInfo
	mu         sync.RWMutex
	records    map[string]Paper
	hasProject func(string) bool
}

var errPaperConflict = errors.New("论文已被修改，请重新打开后再保存")
var errPaperExists = errors.New("已登记相同标识符或引用键")
var errInvalidPaper = errors.New("文献信息无效")
var paperCitekeyPattern = regexp.MustCompile(`^[\p{L}\p{N}_:.+/-]{1,160}$`)
var libraryIDPattern = regexp.MustCompile(`^[0-9a-f]{32}$`)
var arxivPattern = regexp.MustCompile(`(?i)^(?:[0-9]{4}\.[0-9]{4,5}|[a-z][a-z.\-]*/[0-9]{7})(?:v[0-9]+)?$`)
var doiPattern = regexp.MustCompile(`(?i)^10\.[0-9]{4,9}/[^\s<>"]+$`)

func paperID() string {
	var id [16]byte
	// crypto/rand.Read always fills the buffer or terminates the program.
	rand.Read(id[:])
	return hex.EncodeToString(id[:])
}
func NewPaperLibrary(dir string) (*PaperLibrary, error) {
	p := &PaperLibrary{dir: dir, records: make(map[string]Paper)}
	if err := os.MkdirAll(dir, 0700); err != nil {
		return nil, err
	}
	info, err := os.Lstat(dir)
	if err != nil {
		return nil, err
	}
	if !info.IsDir() {
		return nil, fmt.Errorf("文献库目录不可用")
	}
	p.dirInfo = info
	for _, sub := range []string{"records", "pdf", "markdown"} {
		if err := workspace.ManagedMkdirAll(filepath.Join(dir, sub), 0700); err != nil {
			return nil, err
		}
	}
	entries, err := workspace.ManagedReadDir(filepath.Join(dir, "records"))
	if err != nil {
		return nil, err
	}
	if _, _, err := p.readOrganization(); err != nil {
		return nil, err
	}
	for _, ent := range entries {
		name := ent.Name()
		if !strings.HasSuffix(name, ".json") {
			continue
		}
		id := strings.TrimSuffix(name, ".json")
		if !libraryIDPattern.MatchString(id) || !ent.Type().IsRegular() {
			return nil, fmt.Errorf("损坏的文献记录 %q", name)
		}
		body, e := workspace.ManagedReadFile(filepath.Join(dir, "records", name))
		if e != nil {
			return nil, e
		}
		rec, e := decodePaperRecord(id, body)
		if e != nil {
			return nil, e
		}
		p.records[id] = rec
	}
	return p, nil
}

// SetProjectValidator is called once during application startup.
func (s *PaperLibrary) SetProjectValidator(f func(string) bool) { s.hasProject = f }
func (s *PaperLibrary) Snapshot(id string) (Paper, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	p, ok := s.records[id]
	return clonePaper(p), ok
}
func clonePaper(p Paper) Paper {
	if p.Markdown != nil {
		p.Markdown = new(*p.Markdown)
	}
	if p.ProjectLinks != nil {
		links := make(map[string]PaperProjectLink, len(p.ProjectLinks))
		for id, link := range p.ProjectLinks {
			link.UseFor = append([]string{}, link.UseFor...)
			if link.SortOrder != nil {
				order := *link.SortOrder
				link.SortOrder = &order
			}
			links[id] = link
		}
		p.ProjectLinks = links
	}
	p.Authors = append([]string{}, p.Authors...)
	p.Categories = append([]string{}, p.Categories...)
	p.Tags = append([]string{}, p.Tags...)
	p.ProjectIDs = append([]string{}, p.ProjectIDs...)
	p.CoreProjectIDs = append([]string{}, p.CoreProjectIDs...)
	p.References = append([]string{}, p.References...)
	p.Annotations = append([]PaperAnnotation{}, p.Annotations...)
	for i := range p.Annotations {
		annotation := &p.Annotations[i]
		annotation.Rects = append([]AnnotationRect{}, annotation.Rects...)
		if annotation.SelectionStart != nil {
			annotation.SelectionStart = new(*annotation.SelectionStart)
		}
		if annotation.SelectionEnd != nil {
			annotation.SelectionEnd = new(*annotation.SelectionEnd)
		}
	}
	if p.ReadingPosition != nil {
		p.ReadingPosition = new(*p.ReadingPosition)
	}
	return p
}
func (s *PaperLibrary) PDFPath(id string) (string, error) {
	p, ok := s.Snapshot(id)
	if !ok || !p.HasPDF {
		return "", os.ErrNotExist
	}
	return filepath.Join(s.dir, "pdf", p.ID+".pdf"), nil
}
func decodePaperRecord(id string, data []byte) (Paper, error) {
	var p Paper
	if err := json.Unmarshal(data, &p); err != nil || p.ID != id || p.Revision < 1 ||
		(p.CollectionID != "" && !validID(p.CollectionID)) || validatePaperLinks(&p.PaperMetadata) != nil {
		return Paper{}, fmt.Errorf("无法读取文献记录 %s.json", id)
	}
	p.diskHash = sha256.Sum256(data)
	return p, nil
}

// Merge changes to known JSON fields into the on-disk object. An unchanged
// value retains its original representation, including any newer nested fields.
func mergeRecordFields(disk, before, after json.RawMessage) json.RawMessage {
	if bytes.Equal(before, after) {
		return disk
	}
	var original, old, next map[string]json.RawMessage
	if json.Unmarshal(disk, &original) != nil || original == nil ||
		json.Unmarshal(before, &old) != nil || old == nil ||
		json.Unmarshal(after, &next) != nil || next == nil {
		return after
	}
	for key := range old {
		if _, keep := next[key]; !keep {
			delete(original, key)
		}
	}
	for key, value := range next {
		if prior, exists := old[key]; exists && original[key] != nil {
			if key == "annotations" && (value[0] == '[' || bytes.Equal(value, []byte("null"))) && !bytes.Equal(prior, value) {
				original[key] = mergePaperAnnotations(original[key], prior, value)
			} else {
				original[key] = mergeRecordFields(original[key], prior, value)
			}
		} else if !exists || !bytes.Equal(prior, value) {
			original[key] = value
		}
	}
	merged, _ := json.Marshal(original) // entries come only from parsed JSON
	return merged
}

// Annotation arrays may change order or length. Match by stable ID to
// preserve extensions on existing annotations when writing another mark.
func mergePaperAnnotations(disk, before, after json.RawMessage) json.RawMessage {
	type annotationIdentity struct {
		ID string `json:"id"`
	}
	index := func(data json.RawMessage) (map[string]json.RawMessage, bool) {
		var entries []json.RawMessage
		if json.Unmarshal(data, &entries) != nil {
			return nil, false
		}
		byID := make(map[string]json.RawMessage, len(entries))
		for _, entry := range entries {
			var identity annotationIdentity
			if json.Unmarshal(entry, &identity) != nil || identity.ID == "" || byID[identity.ID] != nil {
				return nil, false
			}
			byID[identity.ID] = entry
		}
		return byID, true
	}
	original, originalOK := index(disk)
	old, oldOK := index(before)
	var next []json.RawMessage
	if !originalOK || !oldOK || json.Unmarshal(after, &next) != nil {
		return after
	}
	for i, entry := range next {
		var identity annotationIdentity
		if json.Unmarshal(entry, &identity) == nil && original[identity.ID] != nil && old[identity.ID] != nil {
			next[i] = mergeRecordFields(original[identity.ID], old[identity.ID], entry)
		}
	}
	merged, _ := json.Marshal(next)
	return merged
}

func (s *PaperLibrary) lockRecords() (*os.File, error) {
	root, err := workspace.ManagedOpenDirectory(filepath.Join(s.dir, "records"))
	if err != nil {
		return nil, err
	}
	defer root.Close()
	dir, err := root.Open(".")
	if err != nil {
		return nil, err
	}
	if err = syscall.Flock(int(dir.Fd()), syscall.LOCK_EX); err != nil {
		dir.Close()
		return nil, err
	}
	return dir, nil // closing the descriptor releases the lock
}

func (s *PaperLibrary) currentRecord(id string) ([]byte, error) {
	path := filepath.Join(s.dir, "records", id+".json")
	old, exists := s.records[id]
	info, err := os.Lstat(path)
	if errors.Is(err, os.ErrNotExist) && !exists {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	if !info.Mode().IsRegular() {
		return nil, fmt.Errorf("无效的文献记录 %s.json", id)
	}
	data, err := workspace.ManagedReadFile(path)
	if err != nil {
		return nil, err
	}
	if !exists || old.diskHash != sha256.Sum256(data) {
		updated, err := decodePaperRecord(id, data)
		if err != nil {
			return nil, err
		}
		s.records[id] = updated
		return nil, errPaperConflict
	}
	return data, nil
}

func (s *PaperLibrary) saveLocked(p Paper) error {
	lock, err := s.lockRecords()
	if err != nil {
		return err
	}
	defer lock.Close()
	return s.saveWithRecordLock(p)
}

func (s *PaperLibrary) saveWithRecordLock(p Paper) error {
	disk, err := s.currentRecord(p.ID)
	if err != nil {
		return err
	}
	if p.CollectionID != "" && p.CollectionID != s.records[p.ID].CollectionID {
		organization, _, err := s.readOrganization()
		if err != nil {
			return err
		}
		if _, exists := organization.Collections[p.CollectionID]; !exists {
			return fmt.Errorf("%w：文献集合不存在", errInvalidPaper)
		}
	}
	body, err := json.Marshal(p)
	if err != nil {
		return err
	}
	if disk != nil {
		before, err := json.Marshal(s.records[p.ID])
		if err != nil {
			return err
		}
		body = mergeRecordFields(disk, before, body)
	}
	if err = atomicWrite(filepath.Join(s.dir, "records", p.ID+".json"), body); err != nil {
		return err
	}
	p.diskHash = sha256.Sum256(body)
	s.records[p.ID] = clonePaper(p)
	return nil
}
func paperListClean(values []string, maxCount, maxLen int) ([]string, error) {
	return cleanPaperItems(values, maxCount, maxLen, false)
}

func cleanPaperItems(values []string, maxCount, maxLen int, allowRepeats bool) ([]string, error) {
	result := []string{}
	seen := map[string]bool{}
	if len(values) > maxCount {
		return nil, errInvalidPaper
	}
	for _, value := range values {
		v := strings.TrimSpace(value)
		if utf8.RuneCountInString(v) > maxLen {
			return nil, errInvalidPaper
		}
		if v != "" && (allowRepeats || !seen[v]) {
			seen[v] = true
			result = append(result, v)
		}
	}
	return result, nil
}
func paperContains(values []string, key string) bool {
	for _, v := range values {
		if v == key {
			return true
		}
	}
	return false
}
func validatePaperLinks(m *PaperMetadata) error {
	for id, link := range m.ProjectLinks {
		if !paperContains(m.ProjectIDs, id) || utf8.RuneCountInString(link.FolderPath) > 512 {
			return fmt.Errorf("%w：项目文献设置无效", errInvalidPaper)
		}
		if link.SortOrder != nil && (*link.SortOrder < -9007199254740991 || *link.SortOrder > 9007199254740991) {
			return fmt.Errorf("%w：项目顺序超出范围", errInvalidPaper)
		}
		purposes, err := paperListClean(link.UseFor, 128, 256)
		if err != nil {
			return err
		}
		link.UseFor = purposes
		link.FolderPath = strings.TrimSpace(link.FolderPath)
		m.ProjectLinks[id] = link
	}
	return nil
}
func (s *PaperLibrary) validate(m *PaperMetadata, priorProjectIDs []string) error {
	if err := normalizeBibliography(m); err != nil {
		return err
	}
	m.Title = strings.TrimSpace(m.Title)
	m.DOI = normalizeDOI(m.DOI)
	m.Arxiv = normalizeArxiv(m.Arxiv)
	m.InspireID = normalizeInspire(m.InspireID)
	m.PDFURL = strings.TrimSpace(m.PDFURL)
	if len(m.Arxiv) > 128 || len(m.PDFURL) > 4096 || len(m.MetadataSource) > 32 || (m.PDFURL != "" && !paperHTTPURL(m.PDFURL)) ||
		(m.InspireID != "" && !inspirePattern.MatchString(m.InspireID)) {
		return errInvalidPaper
	}
	m.URL = strings.TrimSpace(m.URL)
	m.Citekey = strings.TrimSpace(m.Citekey)
	if m.Title == "" || len(m.Title) > 4096 || len(m.Abstract) > 256*1024 || len(m.Notes) > 2<<20 || len(m.URL) > 4096 || len(m.DOI) > 512 || m.Year < 0 || m.Year > 9999 || m.Rating < 0 || m.Rating > 5 || m.Priority < 0 || m.Priority > 5 {
		return errInvalidPaper
	}
	if m.DOI != "" && !doiPattern.MatchString(m.DOI) || m.Arxiv != "" && !arxivPattern.MatchString(m.Arxiv) || m.Citekey != "" && !paperCitekeyPattern.MatchString(m.Citekey) {
		return errInvalidPaper
	}
	if m.URL != "" && !paperHTTPURL(m.URL) {
		return fmt.Errorf("%w：链接须为 HTTP(S)", errInvalidPaper)
	}
	if m.Status == "" {
		m.Status = "unread"
	}
	if m.Status != "unread" && m.Status != "reading" && m.Status != "read" {
		return errInvalidPaper
	}
	var err error
	for _, v := range []struct {
		list        *[]string
		count, size int
	}{{&m.Authors, 10000, 512}, {&m.Tags, 256, 128}, {&m.ProjectIDs, 512, 256}, {&m.CoreProjectIDs, 512, 256}} {
		*v.list, err = paperListClean(*v.list, v.count, v.size)
		if err != nil {
			return err
		}
	}
	m.References, err = cleanPaperItems(m.References, 4096, 512, true)
	if err != nil {
		return err
	}
	for _, id := range m.CoreProjectIDs {
		if !paperContains(m.ProjectIDs, id) {
			m.ProjectIDs = append(m.ProjectIDs, id)
		}
	}
	for _, id := range m.ProjectIDs {
		if s.hasProject != nil && !paperContains(priorProjectIDs, id) && !s.hasProject(id) {
			return fmt.Errorf("%w：项目不存在", errInvalidPaper)
		}
	}
	return validatePaperLinks(m)
}
func (s *PaperLibrary) all() []Paper {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make([]Paper, 0, len(s.records))
	for _, p := range s.records {
		out = append(out, clonePaper(p))
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].UpdatedAt.Equal(out[j].UpdatedAt) {
			return out[i].ID < out[j].ID
		}
		return out[i].UpdatedAt.After(out[j].UpdatedAt)
	})
	return out
}
func filterPapers(items []Paper, project, query, status string) []Paper {
	out := []Paper{}
	q := strings.ToLower(strings.TrimSpace(query))
	for _, p := range items {
		if project != "" && !paperContains(p.ProjectIDs, project) {
			continue
		}
		if status != "" && p.Status != status {
			continue
		}
		if q != "" {
			link := p.ProjectLinks[project]
			text := strings.Join([]string{p.Title, strings.Join(p.Authors, " "), strconv.Itoa(p.Year), p.DOI,
				p.Arxiv, p.Citekey, strings.Join(p.Tags, " "), p.PublicationTitle, p.Abstract,
				link.FolderPath, strings.Join(link.UseFor, " ")}, " ")
			if !strings.Contains(strings.ToLower(text), q) {
				continue
			}
		}
		out = append(out, p)
	}
	if project != "" {
		sort.SliceStable(out, func(i, j int) bool {
			a, b := out[i].ProjectLinks[project], out[j].ProjectLinks[project]
			if a.IsPinned != b.IsPinned {
				return a.IsPinned
			}
			if a.SortOrder == nil {
				return false
			}
			return b.SortOrder == nil || *a.SortOrder < *b.SortOrder
		})
	}
	return out
}
func changePaper(p *Paper) { p.Revision++; p.UpdatedAt = time.Now().UTC() }

var arxivVersion = regexp.MustCompile(`(?i)v[0-9]+$`)

// ArxivWorkID identifies the publication across revisions while its original
// versioned ID remains available to retrieve and cite the exact source.
func ArxivWorkID(id string) string {
	return arxivVersion.ReplaceAllString(strings.ToLower(id), "")
}

func samePaper(a, b Paper) bool {
	aArxiv, bArxiv := arxivPaperIdentity(a.PaperMetadata), arxivPaperIdentity(b.PaperMetadata)
	return a.DOI != "" && strings.EqualFold(a.DOI, b.DOI) ||
		aArxiv != "" && aArxiv == bArxiv ||
		a.InspireID != "" && a.InspireID == b.InspireID ||
		a.FileSHA256 != "" && a.FileSHA256 == b.FileSHA256 ||
		a.URL != "" && a.URL == b.URL
}
func (s *PaperLibrary) create(m PaperMetadata, tempFile, digest string) (Paper, bool, error) {
	if err := s.validate(&m, nil); err != nil {
		return Paper{}, false, err
	}
	collectionExplicit := m.collectionExplicit || m.CollectionID != ""
	m.collectionExplicit = false
	p := Paper{PaperMetadata: m, ID: paperID(), CreatedAt: time.Now().UTC(), HasPDF: tempFile != "", FileSHA256: digest, Annotations: []PaperAnnotation{}}
	s.mu.Lock()
	defer s.mu.Unlock()
	other, err := s.findImportLocked(p)
	if err != nil {
		return Paper{}, false, err
	}
	isNew := other.ID == ""
	recovered := false
	if !isNew {
		existing := clonePaper(other)
		if tempFile != "" && !existing.HasPDF && conflictingArxivRevisions(existing.Arxiv, m.Arxiv) {
			return Paper{}, false, fmt.Errorf("%w：已有不同版本的 arXiv 记录，请使用该版本的 PDF", errPaperExists)
		}
		recovered = recoverPaperMetadata(&existing, m)
		addPaperImportAliases(&existing, m)
		for _, id := range m.ProjectIDs {
			if !paperContains(existing.ProjectIDs, id) {
				existing.ProjectIDs = append(existing.ProjectIDs, id)
				if link, ok := m.ProjectLinks[id]; ok {
					if existing.ProjectLinks == nil {
						existing.ProjectLinks = map[string]PaperProjectLink{}
					}
					existing.ProjectLinks[id] = link
				}
			}
		}
		for _, id := range m.CoreProjectIDs {
			if !paperContains(existing.CoreProjectIDs, id) {
				existing.CoreProjectIDs = append(existing.CoreProjectIDs, id)
			}
		}
		p = existing
	}
	if !isNew && p.HasPDF && digest != "" && p.FileSHA256 != digest {
		return Paper{}, false, fmt.Errorf("%w：同一文献已有不同 PDF", errPaperExists)
	}
	if !isNew && (p.HasPDF || tempFile == "") {
		old := s.records[p.ID]
		if !recovered && len(old.ProjectIDs) == len(p.ProjectIDs) && len(old.CoreProjectIDs) == len(p.CoreProjectIDs) &&
			old.DOI == p.DOI && old.Arxiv == p.Arxiv && old.InspireID == p.InspireID && old.PDFURL == p.PDFURL {
			return clonePaper(old), false, nil
		}
	}
	if err := s.validate(&p.PaperMetadata, other.ProjectIDs); err != nil {
		return Paper{}, false, err
	}
	if p.Citekey == "" {
		p.Citekey = defaultPaperKey(p, s.records)
	}
	for _, other := range s.records {
		if other.ID != p.ID && (samePaper(p, other) || strings.EqualFold(other.Citekey, p.Citekey)) {
			return Paper{}, false, errPaperExists
		}
	}
	changePaper(&p)
	if err := s.saveImportLocked(&p, tempFile, digest, collectionExplicit); err != nil {
		return Paper{}, false, err
	}
	return clonePaper(p), isNew, nil
}
func (s *PaperLibrary) update(id string, revision int, meta PaperMetadata) (Paper, error) {
	current, exists := s.Snapshot(id)
	if !exists {
		return Paper{}, os.ErrNotExist
	}
	if current.Revision != revision {
		return Paper{}, errPaperConflict
	}
	// A project may have been archived since this paper was linked to it.
	// Its retained membership should not block unrelated paper edits.
	for id := range meta.ProjectLinks {
		if paperContains(current.ProjectIDs, id) && !paperContains(meta.ProjectIDs, id) && !paperContains(meta.CoreProjectIDs, id) {
			delete(meta.ProjectLinks, id)
		}
	}
	if err := s.validate(&meta, current.ProjectIDs); err != nil {
		return Paper{}, err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	p, ok := s.records[id]
	if !ok {
		return Paper{}, os.ErrNotExist
	}
	if revision != p.Revision {
		return Paper{}, errPaperConflict
	}
	p.PaperMetadata = meta
	if p.Citekey == "" {
		p.Citekey = defaultPaperKey(p, s.records)
	}
	for otherID, other := range s.records {
		if otherID != id && (samePaper(p, other) || strings.EqualFold(p.Citekey, other.Citekey)) {
			return Paper{}, errPaperExists
		}
	}
	changePaper(&p)
	err := s.saveLocked(p)
	return clonePaper(p), err
}
func (s *PaperLibrary) SetNotes(id string, revision int, notes string) (Paper, error) {
	p, ok := s.Snapshot(id)
	if !ok {
		return Paper{}, os.ErrNotExist
	}
	p.Notes = notes
	return s.update(id, revision, p.PaperMetadata)
}
