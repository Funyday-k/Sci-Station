package main

import (
	"context"
	"encoding/hex"
	"errors"
	"fmt"
	"net/http"
	"slices"
	"strings"
	"unicode/utf8"

	"scistation.local/desktop/internal/meeting"
	"scistation.local/desktop/internal/research"
)

type labEvidenceReference struct {
	ID       string             `json:"id"`
	Title    string             `json:"title,omitempty"`
	Status   string             `json:"status"`
	Evidence *research.Evidence `json:"evidence,omitempty"`
}

type labEvidenceInspection struct {
	Output        string                 `json:"output"`
	Claims        []labClaim             `json:"claims"`
	Sources       []labEvidenceReference `json:"sources"`
	QualityIssues []string               `json:"qualityIssues"`
	Truncated     bool                   `json:"truncated"`
	Formal        bool                   `json:"formal"`
	ReviewBlock   string                 `json:"reviewBlock,omitempty"`
}

type workflowCitationChecker func(context.Context, string, research.SourceLocation, research.Evidence) (string, string)

func labRecordedReferences(room *meeting.Session, round int, output string) []labEvidenceReference {
	refs := make([]labEvidenceReference, 0)
	for _, material := range room.CitationMaterials(round) {
		if material.CitationID == "" {
			continue
		}
		ref := labEvidenceReference{ID: material.CitationID, Title: material.Name, Status: "unavailable"}
		var evidence research.Evidence
		var err error
		if raw, ok := strings.CutPrefix(material.Excerpt, meeting.PaperExcerptMarker); ok {
			evidence, err = recordedPaperEvidence(raw, room.ProjectID)
		} else if raw, ok := strings.CutPrefix(material.Excerpt, meeting.ProjectExcerptMarker); ok {
			evidence, err = recordedProjectEvidence(raw, room.ProjectID)
		}
		if err != nil {
			ref.Status = "invalid_locator"
		} else if evidence.PaperID != "" || evidence.Source != nil {
			evidence.MeetingID, evidence.TurnID = room.ID, output
			ref.Evidence = &evidence
			switch {
			case material.ExcerptShortened:
				ref.Status = "shortened"
			case material.ReadStatus == meeting.MaterialReadText:
				ref.Status = "recorded"
			}
		}
		refs = append(refs, ref)
	}
	return refs
}

func labReferenceIndex(refs []labEvidenceReference) map[string]labEvidenceReference {
	index := make(map[string]labEvidenceReference, len(refs))
	for _, ref := range refs {
		index[ref.ID] = ref
	}
	return index
}

func verifiedLabReferences(ctx context.Context, project string, refs []labEvidenceReference, check workflowCitationChecker) {
	for i := range refs {
		ref := &refs[i]
		if ref.Status != "recorded" || ctx.Err() != nil {
			continue
		}
		e := *ref.Evidence
		loc := research.SourceLocation{Kind: "paper", ID: e.PaperID, Page: e.Page}
		if e.Source != nil {
			loc = research.SourceLocation{Kind: e.Source.Kind, ID: e.Source.ID, Offset: e.Source.Offset}
		}
		title, status := check(ctx, project, loc, e)
		if title != "" {
			ref.Title = title
		}
		ref.Status = status
	}
}

func evidencePaper(e *research.Evidence) string {
	if e == nil {
		return ""
	}
	if e.PaperID != "" {
		return e.PaperID
	}
	if e.Source != nil && e.Source.Kind == "paper-markdown" {
		return e.Source.ID
	}
	return ""
}

// Explicitly tagged templates use the formal review gate. Existing and
// personal sessions keep their manual note/task approval path.
func formalLabWorkflow(room *meeting.Session) string {
	if len(room.Seats) != 1 || room.ProjectID == "" || !strings.HasPrefix(room.Topic, "科研工作流 · ") {
		return ""
	}
	lines := strings.SplitN(room.Topic, "\n", 3)
	if len(lines) < 2 {
		return ""
	}
	workflow, ok := strings.CutPrefix(strings.TrimSpace(lines[1]), "工作流 ID：")
	if ok && slices.Contains([]string{"paper-reading", "related-work", "gap-planning"}, workflow) {
		return workflow
	}
	return ""
}

func labDraftEvidence(workflow string, claims []labClaim, truncated bool, refs []labEvidenceReference, current bool) ([]research.Evidence, error) {
	if truncated {
		return nil, errors.New("待审正文声明过多，请拆分并逐项核对引用")
	}
	status := "recorded"
	if current {
		status = "located"
	}
	index := labReferenceIndex(refs)
	used := make(map[string]bool)
	for _, claim := range claims {
		if claim.Core && len(claim.References) == 0 {
			return nil, fmt.Errorf("待审正文第 %d 行的核心声明缺少原文引用，请填写对应的 [S编号]", claim.Line)
		}
		for _, id := range claim.References {
			if ref := index[id]; ref.Status != status || ref.Evidence == nil {
				return nil, fmt.Errorf("待审正文第 %d 行的引用 %s 无法核对，请重新选择原文", claim.Line, id)
			}
			used[id] = true
		}
	}
	selected := make([]research.Evidence, 0, len(used))
	papers := make(map[string]bool)
	for _, ref := range refs {
		if used[ref.ID] {
			selected = append(selected, *ref.Evidence)
			if paper := evidencePaper(ref.Evidence); paper != "" {
				papers[paper] = true
			}
		}
	}
	if len(selected) == 0 {
		return nil, errors.New("正式研究成果需要在待审正文中引用至少一段可核对的原文")
	}
	return selected, labRequiredEvidence(workflow, len(papers), len(selected))
}

func labReviewSource(room *meeting.Session, output string) (research.ReviewSource, error) {
	workflow := formalLabWorkflow(room)
	if workflow == "" || (output != "report" && !strings.HasPrefix(output, "round-")) {
		return recordedReviewSource(room, output)
	}
	text, round, err := meetingOutput(room, output)
	if err != nil {
		return research.ReviewSource{}, err
	}
	refs := labRecordedReferences(room, round, output)
	return research.ReviewSource{Text: text, SelectEvidence: func(body string) ([]research.Evidence, error) {
		claims, truncated := labClaims(body)
		// ServeMeetingReview rechecks the selected original bytes while
		// holding the corresponding project and paper locks.
		return labDraftEvidence(workflow, claims, truncated, refs, false)
	}}, nil
}

func labOutputGoal(room *meeting.Session, number int) string {
	for _, round := range room.Rounds {
		if round.Number == number && strings.TrimSpace(round.Note) != "" {
			return round.Note
		}
	}
	for _, block := range strings.Split(room.Topic, "\n\n") {
		if goal, ok := strings.CutPrefix(block, "研究问题\n"); ok {
			return goal
		}
	}
	return ""
}

func inspectLabOutput(ctx context.Context, room *meeting.Session, output string, check workflowCitationChecker) (labEvidenceInspection, error) {
	var result labEvidenceInspection
	if len(room.Seats) != 1 || room.ProjectID == "" || !strings.HasPrefix(output, "round-") {
		return result, errors.New("请选择已完成的项目单席输出")
	}
	body, round, err := meetingOutput(room, output)
	if err != nil {
		return result, err
	}
	result.Output = output
	result.Claims, result.Truncated = labClaims(body)
	result.Sources = labRecordedReferences(room, round, output)
	verifiedLabReferences(ctx, room.ProjectID, result.Sources, check)
	if err := ctx.Err(); err != nil {
		return labEvidenceInspection{}, err
	}
	index := labReferenceIndex(result.Sources)
	labClaimStatuses(result.Claims, index)
	hasPaper := slices.ContainsFunc(result.Sources, func(ref labEvidenceReference) bool {
		return ref.Status == "located" && evidencePaper(ref.Evidence) != ""
	})
	hasPaperCitation := slices.ContainsFunc(result.Claims, func(claim labClaim) bool {
		return slices.ContainsFunc(claim.References, func(id string) bool {
			return index[id].Status == "located" && evidencePaper(index[id].Evidence) != ""
		})
	})
	result.QualityIssues = labQualityIssues(labOutputGoal(room, round), body, hasPaper, hasPaperCitation)
	if workflow := formalLabWorkflow(room); workflow != "" {
		result.Formal = true
		if _, err := labDraftEvidence(workflow, result.Claims, result.Truncated, result.Sources, true); err != nil {
			result.ReviewBlock = err.Error()
		}
	}
	return result, nil
}

func (a *apiServer) serveLabEvidence(w http.ResponseWriter, r *http.Request, id string) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", "GET")
		reject(w, 405, "请读取证据检查")
		return
	}
	decoded, err := hex.DecodeString(id)
	if err != nil || len(decoded) != 16 || id != strings.ToLower(id) {
		http.NotFound(w, r)
		return
	}
	lab, ok := a.research.(*research.Service)
	if !ok || a.meetings == nil {
		reject(w, 503, "未打开科研工作区")
		return
	}
	project := r.URL.Query().Get("project")
	output := r.URL.Query().Get("output")
	if project == "" || utf8.RuneCountInString(output) > 256 || !lab.HasActiveProject(project) {
		reject(w, 404, "未找到此项目的单席输出")
		return
	}
	room, err := a.meetings.Get(id)
	if err != nil {
		if !replyUnreadableSession(w, err) {
			reject(w, 404, "未找到此项目的单席输出")
		}
		return
	}
	if room.ProjectID != project || len(room.Seats) != 1 {
		reject(w, 404, "未找到此项目的单席输出")
		return
	}
	if enabled, err := lab.ModuleEnabled(project, "ai-lab"); err != nil || !enabled {
		reject(w, 409, "AI 实验室模块未启用")
		return
	}
	result, err := inspectLabOutput(r.Context(), room, output, lab.CheckWorkflowCitation)
	if err != nil {
		reject(w, 422, err.Error())
		return
	}
	reply(w, 200, result)
}
