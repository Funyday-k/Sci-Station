package research

import (
	"fmt"
	"maps"
	"net/http"
	"regexp"
	"strings"
)

type noteInput struct {
	Title           *string     `json:"title"`
	Body            *string     `json:"body"`
	Tags            *[]string   `json:"tags"`
	PaperID         *string     `json:"paperId"`
	Evidence        *[]Evidence `json:"evidence"`
	SourceMeetingID *string     `json:"sourceMeetingId"`
	SourceTurnID    *string     `json:"sourceTurnId"`
	IdempotencyKey  string      `json:"idempotencyKey"`
	Revision        int         `json:"revision"`
}

func (s *Service) registerNotes() {
	base := prefix + "/projects/{project}/notes"
	for _, m := range []string{"GET", "POST"} {
		s.mux.HandleFunc(m+" "+base, s.notes)
	}
	for _, m := range []string{"GET", "PATCH", "DELETE"} {
		s.mux.HandleFunc(m+" "+base+"/{note}", s.notes)
	}
	s.mux.HandleFunc("GET "+base+"/{note}/backlinks", s.backlinks)
	s.mux.HandleFunc("GET "+base+"/{note}/markdown", s.markdown)
}
func (s *Service) validateSources(in noteInput) error {
	if in.PaperID != nil && *in.PaperID != "" {
		if _, ok := s.papers.Snapshot(*in.PaperID); !ok {
			return fmt.Errorf("关联论文不存在")
		}
	}
	if in.Evidence == nil {
		return nil
	}
	if len(*in.Evidence) > 128 {
		return fmt.Errorf("证据条目过多")
	}
	for i := range *in.Evidence {
		e := &(*in.Evidence)[i]
		if (e.PaperID == "" && e.MeetingID == "") || e.Page < 0 || strings.TrimSpace(e.Quote) == "" || len(e.Quote) > 128<<10 || len(e.MeetingID) > 256 || len(e.TurnID) > 256 {
			return fmt.Errorf("来源引用不完整")
		}
		if e.PaperID == "" {
			continue
		}
		p, ok := s.papers.Snapshot(e.PaperID)
		if !ok {
			return fmt.Errorf("证据关联的论文不存在")
		}
		if e.SourceHash != "" && p.FileSHA256 != e.SourceHash {
			return fmt.Errorf("来源 PDF 已改变，请重新核对")
		}
		if e.Page > 0 && p.FileSHA256 == "" {
			return fmt.Errorf("来源论文没有对应 PDF")
		}
		if e.Page > 0 && e.SourceHash == "" {
			e.SourceHash = p.FileSHA256
		}
	}
	return nil
}
func updateNote(n *Note, in noteInput) bool {
	if in.Title != nil {
		n.Title = strings.TrimSpace(*in.Title)
	}
	if in.Body != nil {
		n.Body = *in.Body
	}
	if in.Tags != nil {
		n.Tags = *in.Tags
		if n.Tags == nil {
			n.Tags = []string{}
		}
	}
	if in.Evidence != nil {
		n.Evidence = *in.Evidence
		if n.Evidence == nil {
			n.Evidence = []Evidence{}
		}
	}
	if in.PaperID != nil {
		n.PaperID = *in.PaperID
	}
	if in.SourceMeetingID != nil {
		n.SourceMeetingID = *in.SourceMeetingID
	}
	if in.SourceTurnID != nil {
		n.SourceTurnID = *in.SourceTurnID
	}
	if !label(n.Title, 240) || len(n.Body) > 2<<20 || len(n.Tags) > 64 || len(n.SourceMeetingID) > 256 || len(n.SourceTurnID) > 256 {
		return false
	}
	for _, tag := range n.Tags {
		if !label(tag, 80) {
			return false
		}
	}
	return true
}
func noteTaken(d projectData, n Note) bool {
	for _, other := range d.Notes {
		if other.ID != n.ID && strings.EqualFold(other.Title, n.Title) {
			return true
		}
	}
	return false
}
func sortedNotes(d projectData) []Note {
	return valuesBy(d.Notes, func(a, b Note) bool {
		if a.UpdatedAt == b.UpdatedAt {
			return a.ID < b.ID
		}
		return a.UpdatedAt > b.UpdatedAt
	})
}
func validKey(k string) bool { return k == "" || label(k, 256) }
func (s *Service) notes(w http.ResponseWriter, r *http.Request) {
	pid, id := r.PathValue("project"), r.PathValue("note")
	if r.Method == "GET" || r.Method == "HEAD" {
		s.mu.RLock()
		defer s.mu.RUnlock()
		d, ok := s.loadProject(w, pid)
		if !ok {
			return
		}
		if id == "" {
			jsonReply(w, 200, sortedNotes(d))
			return
		}
		n, ok := d.Notes[id]
		if found(w, ok) {
			jsonReply(w, 200, n)
		}
		return
	}
	var in noteInput
	if r.Method != "DELETE" {
		if !payload(w, r, &in) {
			return
		}
		if !validKey(in.IdempotencyKey) {
			jsonFail(w, 400, "请求标识无效")
			return
		}
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	d, ok := s.loadProject(w, pid)
	if !ok {
		return
	}
	if in.IdempotencyKey != "" && r.Method == "POST" {
		if existing, ok := d.NoteKeys[in.IdempotencyKey]; ok {
			n, exists := d.Notes[existing]
			if !exists {
				jsonFail(w, 410, "该结果曾经写入，之后已被移除")
				return
			}
			jsonReply(w, 200, n)
			return
		}
	}
	if err := s.validateSources(in); err != nil {
		jsonFail(w, 409, err.Error())
		return
	}
	d.Notes = maps.Clone(d.Notes)
	if r.Method == "POST" {
		n := Note{Entity: fresh(), ProjectID: pid, Tags: []string{}, Evidence: []Evidence{}}
		if !updateNote(&n, in) {
			jsonFail(w, 400, "笔记标题、内容或标签无效")
			return
		}
		if noteTaken(d, n) {
			jsonFail(w, 409, "项目中已有同名笔记")
			return
		}
		d.Notes[n.ID] = n
		if in.IdempotencyKey != "" {
			d.NoteKeys = maps.Clone(d.NoteKeys)
			d.NoteKeys[in.IdempotencyKey] = n.ID
		}
		if s.save(w, d) {
			jsonReply(w, 201, n)
		}
		return
	}
	n, ok := d.Notes[id]
	if !found(w, ok) {
		return
	}
	if r.Method == "DELETE" {
		if !revisionOK(w, n.Revision, queryRevision(r.URL.Query())) {
			return
		}
		delete(d.Notes, id)
		if s.save(w, d) {
			w.WriteHeader(204)
		}
		return
	}
	if !revisionOK(w, n.Revision, in.Revision) {
		return
	}
	if !updateNote(&n, in) {
		jsonFail(w, 400, "笔记标题、内容或标签无效")
		return
	}
	if noteTaken(d, n) {
		jsonFail(w, 409, "项目中已有同名笔记")
		return
	}
	n.bump()
	d.Notes[id] = n
	if s.save(w, d) {
		jsonReply(w, 200, n)
	}
}

var wikiLink = regexp.MustCompile(`\[\[([^\[\]\n|#]+)(?:#[^\[\]|]*)?(?:\|[^\[\]]*)?\]\]`)

func referencedTitles(body string) map[string]bool {
	out := map[string]bool{}
	for _, match := range wikiLink.FindAllStringSubmatch(body, -1) {
		if key := strings.ToLower(strings.TrimSpace(match[1])); key != "" {
			out[key] = true
		}
	}
	return out
}
func (s *Service) backlinks(w http.ResponseWriter, r *http.Request) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	d, ok := s.loadProject(w, r.PathValue("project"))
	if !ok {
		return
	}
	n, ok := d.Notes[r.PathValue("note")]
	if !found(w, ok) {
		return
	}
	out := []Note{}
	for _, other := range sortedNotes(d) {
		if referencedTitles(other.Body)[strings.ToLower(n.Title)] {
			out = append(out, other)
		}
	}
	jsonReply(w, 200, out)
}
func (s *Service) markdown(w http.ResponseWriter, r *http.Request) {
	s.mu.RLock()
	d, ok := s.loadProject(w, r.PathValue("project"))
	s.mu.RUnlock()
	if !ok {
		return
	}
	n, ok := d.Notes[r.PathValue("note")]
	if !found(w, ok) {
		return
	}
	w.Header().Set("Content-Type", "text/markdown; charset=utf-8")
	w.Header().Set("Content-Disposition", `attachment; filename="note.md"`)
	_, _ = fmt.Fprint(w, n.Body)
}
