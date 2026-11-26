package research

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"maps"
	"net/http"
	"net/url"
	"slices"
	"strconv"
	"strings"
)

// ReviewSource is resolved from a published meeting record by the desktop host.
// It is never decoded from a proposed write or a decision supplied by a seat.
type ReviewSource struct {
	Text           string                                           `json:"text"`
	Evidence       []Evidence                                       `json:"evidence"`
	SelectEvidence func(string) ([]Evidence, map[string]int, error) `json:"-"`
}

type ReviewProposal struct {
	ProjectRevision     int    `json:"projectRevision"`
	TurnID              string `json:"turnId"`
	Action              string `json:"action"`
	DestinationID       string `json:"destinationId,omitempty"`
	DestinationRevision int    `json:"destinationRevision,omitempty"`
	Title               string `json:"title"`
	Body                string `json:"body"`
}

type MeetingReview struct {
	Entity
	ReviewProposal
	Version    int        `json:"version"`
	ProjectID  string     `json:"projectId"`
	MeetingID  string     `json:"meetingId"`
	SourceHash string     `json:"sourceHash"`
	SourceText string     `json:"sourceText"`
	Evidence   []Evidence `json:"evidence"`
	// CitationOrdinals binds the reviewed inline IDs to the one-based order of
	// the resolved evidence. Older decisions remain readable without this map.
	CitationOrdinals map[string]int `json:"citationOrdinals,omitempty"`
	Status           string         `json:"status"`
	ResultID         string         `json:"resultId,omitempty"`
}

func reviewSourceHash(source ReviewSource) string {
	data, _ := json.Marshal(source)
	digest := sha256.Sum256(data)
	return hex.EncodeToString(digest[:])
}

func (s *Service) registerReviews() {
	s.mux.HandleFunc("GET "+prefix+"/reviews", s.listReviews)
	s.mux.HandleFunc("GET "+prefix+"/projects/{project}/reviews", s.listReviews)
}
func (s *Service) listReviews(w http.ResponseWriter, r *http.Request) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	project := r.PathValue("project")
	if project != "" {
		if _, ok := s.loadProject(w, project); !ok {
			return
		}
	}
	rows := []MeetingReview{}
	for id, d := range s.projects {
		if d.Archived || (project != "" && project != id) {
			continue
		}
		for _, v := range d.Reviews {
			if session := r.URL.Query().Get("meeting"); session == "" || session == v.MeetingID {
				rows = append(rows, v)
			}
		}
	}
	slices.SortFunc(rows, func(a, b MeetingReview) int {
		if cmp := strings.Compare(b.CreatedAt, a.CreatedAt); cmp != 0 {
			return cmp
		}
		return strings.Compare(a.ID, b.ID)
	})
	jsonReply(w, 200, rows)
}

type ReviewRequest struct {
	Decision    string          `json:"decision"`
	OperationID string          `json:"operationId"`
	ProjectID   string          `json:"projectId"`
	Revision    int             `json:"revision,omitempty"`
	Proposal    *ReviewProposal `json:"proposal,omitempty"`
}

func (v MeetingReview) readerLink(e Evidence) string {
	q := url.Values{"project": {v.ProjectID}, "paper": {e.PaperID}, "page": {strconv.Itoa(e.Page)}, "fingerprint": {e.SourceHash}, "quote": {e.Quote}}
	if e.AnnotationID != "" {
		q.Set("annotation", e.AnnotationID)
	}
	if e.SelectionStart != nil && e.SelectionEnd != nil {
		q.Set("start", strconv.Itoa(*e.SelectionStart))
		q.Set("end", strconv.Itoa(*e.SelectionEnd))
	}
	if e.OCR {
		q.Set("ocr", "1")
	}
	return "/reader?" + q.Encode()
}
func (v MeetingReview) content() string {
	q := url.Values{"project": {v.ProjectID}, "session": {v.MeetingID}}
	meetingURL := "/studio?" + q.Encode()
	if strings.HasPrefix(v.TurnID, "round-") {
		meetingURL += "#" + url.PathEscape(v.TurnID)
	}
	var b strings.Builder
	b.WriteString(v.Body)
	fmt.Fprintf(&b, "\n\n[查看会议记录](%s)", meetingURL)
	if len(v.Evidence) > 0 {
		b.WriteString("\n\n会议共享原文")
		for _, e := range v.Evidence {
			if e.Source == nil {
				fmt.Fprintf(&b, "\n- [第 %d 页](%s)", e.Page, v.readerLink(e))
			} else {
				name := "Wiki 原文"
				if e.Source.Kind == "material" {
					name = "项目材料原文"
				}
				fmt.Fprintf(&b, "\n- [%s](%s)", name, e.Source.openURL(e.SourceHash))
			}
		}
	}
	return b.String()
}

// checkReviewDestination is run for both presentation and commit under the
// project lock. New records bind to the project's revision; appends also bind
// to the exact note revision and title the researcher selected.
func checkReviewDestination(d projectData, v MeetingReview) error {
	if d.Project.Revision != v.ProjectRevision {
		return errors.New("项目设置已改变，请重新审核")
	}
	switch v.Action {
	case "append-note":
		n, ok := d.Notes[v.DestinationID]
		if !ok || n.Archived || n.Revision != v.DestinationRevision || n.Title != v.Title {
			return errors.New("目标笔记或版本已改变，请重新审核")
		}
	case "create-note", "create-task":
		if v.DestinationID != "" || v.DestinationRevision != 0 {
			return errors.New("新建记录不能指定已有目标")
		}
	default:
		return errors.New("不支持的审核操作")
	}
	return nil
}

// Hold s.mu, and s.papers.mu when the review includes a PDF. The reader
// validates the original text and location against each owning record.
func (s *Service) checkReviewEvidence(ctx context.Context, d projectData, v MeetingReview) error {
	for _, e := range v.Evidence {
		if e.Source != nil {
			if err := s.verifyProjectReviewEvidence(d, e); err != nil {
				return err
			}
			continue
		}
		p, ok := s.papers.records[e.PaperID]
		if !ok || !slices.Contains(p.ProjectIDs, v.ProjectID) {
			return errors.New("引用的论文未关联此项目")
		}
		if _, err := s.papers.currentRecord(e.PaperID); err != nil {
			return errors.New("论文记录已在其他窗口或应用中改变，请重新审核")
		}
		if err := s.papers.verifyPDFEvidence(ctx, e, p); err != nil {
			return err
		}
	}
	return nil
}

func (s *Service) applyMeetingReview(d *projectData, v *MeetingReview) error {
	content := v.content()
	if v.Action == "create-task" {
		t := newTask(v.ProjectID)
		input := taskInput{Title: &v.Title, Description: &content}
		papers := []string{}
		for _, ref := range v.Evidence {
			if ref.linkedPaperID() != "" && !slices.Contains(papers, ref.linkedPaperID()) {
				papers = append(papers, ref.linkedPaperID())
			}
		}
		input.RelatedPaperIDs = &papers
		if err := s.updateTaskLocked(&t, input); err != nil {
			return err
		}
		t.Evidence = slices.Clone(v.Evidence)
		d.Tasks = maps.Clone(d.Tasks)
		d.Tasks[t.ID] = t
		v.ResultID = t.ID
		return nil
	}
	var n Note
	if v.Action == "append-note" {
		n = d.Notes[v.DestinationID]
		content = strings.TrimRight(n.Body, "\r\n") + "\n\n" + content
		n.bump()
	} else {
		n = Note{Entity: fresh(), ProjectID: v.ProjectID, Title: v.Title, Tags: []string{}, SourceMeetingID: v.MeetingID, SourceTurnID: v.TurnID}
		if len(v.Evidence) == 1 {
			n.PaperID = v.Evidence[0].linkedPaperID()
		}
	}
	n.Evidence = append(slices.Clone(n.Evidence), v.Evidence...)
	if !updateNote(&n, noteInput{Body: &content}) || len(n.Evidence) > 128 {
		return errors.New("合并后笔记的正文或证据条目超出限制")
	}
	if _, err := readWikiFrontmatter(n.Body); err != nil {
		return fmt.Errorf("Markdown 元数据有误：%w", err)
	}
	if wikiNameTaken(*d, n) {
		return errors.New("项目中已有同名笔记")
	}
	d.Notes = maps.Clone(d.Notes)
	d.Notes[n.ID] = n
	v.ResultID = n.ID
	return nil
}

// ServeMeetingReview is invoked only by the host holding a recorded meeting
// snapshot. The session's persisted project ID authorizes the scope. An
// operation and its effects always share a single atomic project-file write.
func (s *Service) ServeMeetingReview(w http.ResponseWriter, r *http.Request, project, meeting string, in ReviewRequest, resolve func(string) (ReviewSource, error)) {
	if project == "" || project != in.ProjectID {
		jsonFail(w, 403, "会议不属于所选科研项目")
		return
	}
	if !validID(in.OperationID) {
		jsonFail(w, 400, "操作标识无效")
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	d, ok := s.loadProject(w, project)
	if !ok {
		return
	}
	v, exists := d.Reviews[in.OperationID]
	if exists && (v.MeetingID != meeting || v.ProjectID != project || v.Version != 1) {
		jsonFail(w, 409, "操作标识已被使用或审核格式不受支持")
		return
	}
	propose := in.Decision == "propose"
	if propose {
		p := in.Proposal
		if p == nil || in.Revision != 0 || !label(p.Title, 240) || strings.TrimSpace(p.Body) == "" || len(p.Body) > 2<<20 || !label(p.TurnID, 256) {
			jsonFail(w, 400, "请提供待审标题、内容和会议输出")
			return
		}
		if exists {
			if v.ReviewProposal != *p {
				jsonFail(w, 409, "重试操作的内容已改变")
				return
			}
			jsonReply(w, 200, v)
			return
		}
		e := fresh()
		e.ID = in.OperationID
		v = MeetingReview{Entity: e, ReviewProposal: *p, Version: 1, ProjectID: project, MeetingID: meeting, Status: "pending"}
	} else {
		if (in.Decision != "accept" && in.Decision != "reject") || in.Proposal != nil || in.Revision < 1 {
			jsonFail(w, 400, "请确认或拒绝已读取的审核版本")
			return
		}
		if !found(w, exists) {
			return
		}
		if v.Status != "pending" {
			if (v.Status == "accepted" && in.Decision == "accept" || v.Status == "rejected" && in.Decision == "reject") && (in.Revision == v.Revision || in.Revision == v.Revision-1) {
				jsonReply(w, 200, v)
				return
			}
			jsonFail(w, 409, "此项审核已经结束")
			return
		}
		if !revisionOK(w, v.Revision, in.Revision) {
			return
		}
	}
	if in.Decision == "reject" {
		v.Status = "rejected"
		v.bump()
	} else {
		if _, err := s.directory(d); err != nil {
			jsonFail(w, 403, "项目目录授权不可用")
			return
		}
		if err := checkReviewDestination(d, v); err != nil {
			jsonFail(w, 409, err.Error())
			return
		}
		source, err := resolve(v.TurnID)
		if err != nil {
			jsonFail(w, 409, err.Error())
			return
		}
		var ordinals map[string]int
		if source.SelectEvidence != nil {
			source.Evidence, ordinals, err = source.SelectEvidence(v.Body)
			if err != nil {
				jsonFail(w, 422, err.Error())
				return
			}
		}
		if propose {
			v.SourceHash = reviewSourceHash(source)
			v.SourceText = source.Text
			v.Evidence = source.Evidence
		} else if v.SourceHash != reviewSourceHash(source) || (v.CitationOrdinals != nil && !maps.Equal(v.CitationOrdinals, ordinals)) {
			jsonFail(w, 409, "会议原文或共享证据已改变，请重新审核")
			return
		}
		v.CitationOrdinals = ordinals
		if slices.ContainsFunc(v.Evidence, func(e Evidence) bool { return e.linkedPaperID() != "" }) {
			s.papers.mu.Lock()
			defer s.papers.mu.Unlock()
			records, err := s.papers.lockRecords()
			if err != nil {
				jsonFail(w, 500, "无法锁定论文记录")
				return
			}
			defer records.Close()
		}
		if err := s.checkReviewEvidence(r.Context(), d, v); err != nil {
			jsonFail(w, 409, err.Error())
			return
		}
		if !propose {
			if err := s.applyMeetingReview(&d, &v); err != nil {
				jsonFail(w, 409, err.Error())
				return
			}
			v.Status = "accepted"
			v.bump()
		}
	}
	d.Reviews = maps.Clone(d.Reviews)
	if d.Reviews == nil {
		d.Reviews = map[string]MeetingReview{}
	}
	d.Reviews[v.ID] = v
	if s.save(w, d) {
		status := http.StatusOK
		if propose {
			status = http.StatusCreated
		}
		jsonReply(w, status, v)
	}
}
