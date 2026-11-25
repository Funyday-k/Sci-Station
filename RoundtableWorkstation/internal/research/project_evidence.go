package research

import (
	"crypto/sha256"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"unicode/utf8"
)

// ProjectEvidenceLocation addresses a selection on an active project record.
// Its offsets count Unicode characters after normalizing line endings. PDF
// evidence keeps the separate, existing page and UTF-16 selection fields.
type ProjectEvidenceLocation struct {
	ProjectID string `json:"projectId"`
	Kind      string `json:"kind"`
	ID        string `json:"id"`
	Offset    int    `json:"offset"`
	End       int    `json:"end"`
}

const maxProjectEvidenceRunes = 1000

func (loc ProjectEvidenceLocation) valid() bool {
	return validID(loc.ProjectID) && validID(loc.ID) && (loc.Kind == "note" || loc.Kind == "material") &&
		loc.Offset >= 0 && loc.End > loc.Offset && loc.End-loc.Offset <= maxProjectEvidenceRunes
}

func (loc ProjectEvidenceLocation) openURL(hash string) string {
	params := url.Values{"project": {loc.ProjectID}, "fingerprint": {hash},
		"offset": {strconv.Itoa(loc.Offset)}, "end": {strconv.Itoa(loc.End)}}
	if loc.Kind == "note" {
		params.Set("view", "notes")
		params.Set("note", loc.ID)
	} else {
		params.Set("view", "materials")
		params.Set("material", loc.ID)
	}
	return "/research?" + params.Encode()
}

type ProjectSourceExcerpt struct {
	Title    string `json:"title"`
	Revision int    `json:"revision"`
	Before   string `json:"before"`
	Quote    string `json:"quote"`
	After    string `json:"after"`
	Line     int    `json:"line"`
	Column   int    `json:"column"`
}

var errProjectEvidenceChanged = errors.New("引用的项目原文或选段已改变，请重新选择和审核")

// Used by review and by citation navigation, under the owning project lock.
func (s *Service) verifiedProjectSource(d projectData, loc ProjectEvidenceLocation, hash string) (ProjectSourceExcerpt, error) {
	if !loc.valid() || loc.ProjectID != d.Project.ID || len(hash) != sha256.Size*2 {
		return ProjectSourceExcerpt{}, ErrWorkflowSource
	}
	module := "wiki"
	if loc.Kind == "material" {
		module = "materials"
	}
	config, err := s.readModuleConfig(loc.ProjectID)
	if err != nil || !config.effective(module, loc.ProjectID) {
		return ProjectSourceExcerpt{}, os.ErrPermission
	}
	text, title, err := s.workflowRecordLocked(d, SourceLocation{Kind: loc.Kind, ID: loc.ID})
	if err != nil {
		return ProjectSourceExcerpt{}, err
	}
	if hash != fmt.Sprintf("%x", sha256.Sum256([]byte(text))) {
		return ProjectSourceExcerpt{}, errProjectEvidenceChanged
	}
	runes := []rune(normalizeWorkflowText(text))
	if loc.End > len(runes) {
		return ProjectSourceExcerpt{}, errProjectEvidenceChanged
	}
	line, lastNewline := 1, -1
	for i, ch := range runes[:loc.Offset] {
		if ch == '\n' {
			lastNewline = i
			line++
		}
	}
	const context = 160
	revision := d.Notes[loc.ID].Revision
	if loc.Kind == "material" {
		revision = d.Materials[loc.ID].Revision
	}
	return ProjectSourceExcerpt{
		Title: title, Revision: revision, Quote: string(runes[loc.Offset:loc.End]), Line: line, Column: loc.Offset - lastNewline,
		Before: string(runes[max(0, loc.Offset-context):loc.Offset]), After: string(runes[loc.End:min(len(runes), loc.End+context)]),
	}, nil
}

func (s *Service) verifyProjectReviewEvidence(d projectData, evidence Evidence) error {
	if evidence.Source == nil || evidence.PaperID != "" || evidence.Page != 0 || evidence.AnnotationID != "" ||
		evidence.SelectionStart != nil || evidence.SelectionEnd != nil || evidence.OCR ||
		utf8.RuneCountInString(evidence.Quote) != evidence.Source.End-evidence.Source.Offset {
		return ErrWorkflowSource
	}
	match, err := s.verifiedProjectSource(d, *evidence.Source, evidence.SourceHash)
	if err != nil {
		return err
	}
	if match.Quote != evidence.Quote {
		return errProjectEvidenceChanged
	}
	return nil
}

func (s *Service) projectSourceExcerpt(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	start, startErr := strconv.Atoi(q.Get("offset"))
	end, endErr := strconv.Atoi(q.Get("end"))
	loc := ProjectEvidenceLocation{ProjectID: r.PathValue("project"), Kind: r.PathValue("kind"), ID: r.PathValue("source"), Offset: start, End: end}
	if startErr != nil || endErr != nil || !loc.valid() {
		jsonFail(w, 400, "原文位置无效")
		return
	}
	s.mu.RLock()
	defer s.mu.RUnlock()
	d, ok := s.loadProject(w, loc.ProjectID)
	if !ok {
		return
	}
	if _, err := s.directory(d); err != nil {
		jsonFail(w, 403, "项目目录授权不可用")
		return
	}
	excerpt, err := s.verifiedProjectSource(d, loc, q.Get("fingerprint"))
	switch {
	case err == nil:
		jsonReply(w, 200, excerpt)
	case errors.Is(err, os.ErrPermission):
		jsonFail(w, 403, "原文访问授权不可用")
	case errors.Is(err, ErrWorkflowSource):
		jsonFail(w, 404, "未找到引用的项目原文")
	default:
		jsonFail(w, 409, err.Error())
	}
}
