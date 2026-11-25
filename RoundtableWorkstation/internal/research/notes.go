package research

import (
	"encoding/json"
	"fmt"
	"maps"
	"net/http"
	"strings"
)

type noteInput struct {
	Title           *string     `json:"title"`
	Namespace       *string     `json:"namespace"`
	Aliases         *[]string   `json:"aliases"`
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
	s.mux.HandleFunc("POST "+base+"/{note}/restore", s.restoreNote)
	s.mux.HandleFunc("GET "+base+"/{note}/links", s.noteLinks)
	s.mux.HandleFunc("GET "+base+"/{note}/backlinks", s.backlinks)
	s.mux.HandleFunc("GET "+base+"/{note}/markdown", s.markdown)
}

// Only the reviewed-write transaction may attach meeting provenance. Manual
// edits may retain or remove existing citations, including legacy records.
func introducesMeetingSource(in noteInput, current Note) bool {
	if in.SourceMeetingID != nil && *in.SourceMeetingID != "" && *in.SourceMeetingID != current.SourceMeetingID {
		return true
	}
	if in.SourceTurnID != nil && *in.SourceTurnID != "" && *in.SourceTurnID != current.SourceTurnID {
		return true
	}
	if in.Evidence == nil {
		return false
	}
	old := map[string]int{}
	for _, e := range current.Evidence {
		if e.MeetingID != "" || e.TurnID != "" {
			b, _ := json.Marshal(e)
			old[string(b)]++
		}
	}
	for _, e := range *in.Evidence {
		if e.MeetingID != "" || e.TurnID != "" {
			b, _ := json.Marshal(e)
			key := string(b)
			if old[key] == 0 {
				return true
			}
			old[key]--
		}
	}
	return false
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
	if in.Namespace != nil {
		n.Namespace = strings.TrimSpace(*in.Namespace)
		if n.Namespace != "" && !validWikiPath(n.Namespace) {
			return false
		}
	}
	if in.Aliases != nil {
		if len(*in.Aliases) > 80 {
			return false
		}
		n.Aliases = nil
		seen := map[string]bool{}
		for _, alias := range *in.Aliases {
			alias = strings.TrimSpace(alias)
			if !validWikiPath(alias) {
				return false
			}
			key := strings.ToLower(alias)
			if !seen[key] {
				n.Aliases = append(n.Aliases, alias)
				seen[key] = true
			}
		}
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
func sortedNotes(d projectData, archived bool) []Note {
	notes := map[string]Note{}
	for id, note := range d.Notes {
		if note.Archived == archived {
			notes[id] = note
		}
	}
	return valuesBy(notes, func(a, b Note) bool {
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
		archived := r.URL.Query().Get("archived") == "1"
		if id == "" {
			jsonReply(w, 200, sortedNotes(d, archived))
			return
		}
		n, ok := d.Notes[id]
		if found(w, ok && n.Archived == archived) {
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
			if !exists || n.Archived {
				jsonFail(w, 410, "该结果曾经写入，之后已被移除")
				return
			}
			jsonReply(w, 200, n)
			return
		}
	}
	if introducesMeetingSource(in, d.Notes[id]) {
		jsonFail(w, 403, "请通过会议审核保存来源")
		return
	}
	if err := s.validateSources(in); err != nil {
		jsonFail(w, 409, err.Error())
		return
	}
	d.Notes = maps.Clone(d.Notes)
	if r.Method == "POST" {
		n := Note{Entity: fresh(), ProjectID: pid, Tags: []string{}, Evidence: []Evidence{}}
		if !updateNote(&n, in) {
			jsonFail(w, 400, "笔记的标题、目录、别名、内容或标签无效")
			return
		}
		if wikiNameTaken(d, n) {
			jsonFail(w, 409, "此页面路径或别名已在项目中使用")
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
	if !found(w, ok && !n.Archived) {
		return
	}
	if r.Method == "DELETE" {
		if !revisionOK(w, n.Revision, queryRevision(r.URL.Query())) {
			return
		}
		n.Archived = true
		n.bump()
		d.Notes[id] = n
		if s.save(w, d) {
			w.WriteHeader(204)
		}
		return
	}
	if !revisionOK(w, n.Revision, in.Revision) {
		return
	}
	previous := n
	if !updateNote(&n, in) {
		jsonFail(w, 400, "笔记的标题、目录、别名、内容或标签无效")
		return
	}
	retainMovedWikiPaths(&n, previous)
	if wikiNameTaken(d, n) {
		jsonFail(w, 409, "此页面路径或别名已在项目中使用")
		return
	}
	n.bump()
	d.Notes[id] = n
	if s.save(w, d) {
		jsonReply(w, 200, n)
	}
}

func (s *Service) restoreNote(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Revision int `json:"revision"`
	}
	if !payload(w, r, &in) {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	d, ok := s.loadProject(w, r.PathValue("project"))
	if !ok {
		return
	}
	id := r.PathValue("note")
	n, ok := d.Notes[id]
	if !found(w, ok && n.Archived) || !revisionOK(w, n.Revision, in.Revision) {
		return
	}
	n.Archived = false
	n.bump()
	d.Notes = maps.Clone(d.Notes)
	d.Notes[id] = n
	if s.save(w, d) {
		jsonReply(w, 200, n)
	}
}

func (s *Service) backlinks(w http.ResponseWriter, r *http.Request) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	d, ok := s.loadProject(w, r.PathValue("project"))
	if !ok {
		return
	}
	n, ok := d.Notes[r.PathValue("note")]
	if !found(w, ok && !n.Archived) {
		return
	}
	if r.URL.Query().Has("revision") && !revisionOK(w, n.Revision, queryRevision(r.URL.Query())) {
		return
	}
	index := wikiLinkIndex(d)
	out := []Note{}
	for _, other := range sortedNotes(d, false) {
		if other.ID == n.ID {
			continue
		}
		for _, link := range wikiLinks(other.Body) {
			if index.resolve(link.Target) == n.ID {
				out = append(out, other)
				break
			}
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
	if !found(w, ok && n.Archived == (r.URL.Query().Get("archived") == "1")) {
		return
	}
	w.Header().Set("Content-Type", "text/markdown; charset=utf-8")
	w.Header().Set("Content-Disposition", `attachment; filename="note.md"`)
	_, _ = fmt.Fprint(w, n.Body)
}
