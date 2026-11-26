package research

import (
	"context"
	"fmt"
	"net/url"
	"reflect"
	"slices"
	"strconv"
	"strings"
	"time"
)

type graphArtifact struct {
	review      MeetingReview
	destination graphWorkflowLink
	changed     bool
	evidence    []Evidence
}

func graphArtifacts(project projectData, tasks map[string]Task) []graphArtifact {
	reviews := valuesBy(project.Reviews, func(a, b MeetingReview) bool {
		if a.UpdatedAt != b.UpdatedAt {
			return a.UpdatedAt > b.UpdatedAt
		}
		return a.ID < b.ID
	})
	var artifacts []graphArtifact
	for _, review := range reviews {
		if review.Version != 1 || review.Status != "accepted" || review.ProjectID != project.Project.ID || review.ResultID == "" {
			continue
		}
		var body string
		var evidence []Evidence
		params := url.Values{"project": {review.ProjectID}}
		switch review.Action {
		case "create-note", "append-note":
			note, ok := project.Notes[review.ResultID]
			if !ok || note.Archived {
				continue
			}
			body, evidence = note.Body, note.Evidence
			params.Set("view", "notes")
			params.Set("note", note.ID)
		case "create-task":
			task, ok := tasks[review.ResultID]
			if !ok {
				continue
			}
			body, evidence = task.Description, task.Evidence
			params.Set("view", "tasks")
			params.Set("task", task.ID)
		default:
			continue
		}
		reviewedText := strings.TrimSpace(normalizeWorkflowText(review.content()))
		artifacts = append(artifacts, graphArtifact{
			review: review, changed: !strings.Contains(normalizeWorkflowText(body), reviewedText),
			destination: graphWorkflowLink{Label: "打开保存的成果", URL: "/research?" + params.Encode()},
			evidence:    evidence,
		})
	}
	return artifacts
}

type graphArtifactEvidence struct {
	status string
	link   graphWorkflowLink
}

func (s *Service) graphArtifactSource(ctx context.Context, artifact graphArtifact, evidence Evidence, ordinal int) graphArtifactEvidence {
	result := graphArtifactEvidence{status: "removed"}
	if !slices.ContainsFunc(artifact.evidence, func(actual Evidence) bool { return reflect.DeepEqual(actual, evidence) }) {
		return result
	}
	loc := SourceLocation{Kind: "paper", ID: evidence.PaperID, Page: evidence.Page}
	link := artifact.review.readerLink(evidence)
	if evidence.Source != nil {
		loc = SourceLocation{Kind: evidence.Source.Kind, ID: evidence.Source.ID, Offset: evidence.Source.Offset}
		link = evidence.Source.openURL(evidence.SourceHash)
	}
	title, status := s.CheckWorkflowCitation(ctx, artifact.review.ProjectID, loc, evidence)
	if title == "" {
		title = "来源 " + strconv.Itoa(ordinal)
	}
	const prefix = "查看原文 "
	if status == "located" || status == "stale" || status == "invalid_quote" {
		result.link = graphWorkflowLink{Label: prefix + title, URL: link}
	}
	result.status = status
	return result
}

func (s *Service) graphArtifactFindings(ctx context.Context, project projectData, tasks map[string]Task, q graphWorkflowQuery, now time.Time) graphWorkflowResult {
	stale := q.operation == "stale-artifacts"
	result := graphWorkflowResult{Title: "项目图谱 · 需核对证据的成果声明", Notice: "检查已审核保存的正文和各声明登记的原文。结果描述引用覆盖情况。"}
	if stale {
		result.Title = "项目图谱 · 待复核的已保存成果"
		result.Notice = "核对 " + strconv.Itoa(q.threshold) + " 天的复核期限，以及保存的正文与原文。"
	}
	cutoff := now.AddDate(0, 0, -q.threshold)
	for _, artifact := range graphArtifacts(project, tasks) {
		if ctx.Err() != nil {
			break
		}
		var evidence []graphArtifactEvidence
		if stale || q.severity != "error" {
			for i, e := range artifact.review.Evidence {
				if ctx.Err() != nil {
					break
				}
				evidence = append(evidence, s.graphArtifactSource(ctx, artifact, e, i+1))
			}
		}
		if stale {
			if row, ok := artifact.staleFinding(cutoff, evidence); ok {
				result.Findings = append(result.Findings, row)
			}
		} else {
			result.Findings = append(result.Findings, artifact.claimFindings(q.severity, evidence)...)
		}
	}
	if len(result.Findings) == 0 {
		result.Notice += " 当前未发现满足条件的记录。"
	}
	return result
}

func graphArtifactEvidenceMessage(status string) string {
	switch status {
	case "stale":
		return "原文已改变"
	case "invalid_quote":
		return "原文与登记的摘录不符"
	case "removed":
		return "证据已从成果移除"
	default:
		return "原文不可用"
	}
}

func (a graphArtifact) label() string {
	return graphExcerptLabel(a.review.Title) + " [" + a.review.ResultID + "]"
}

func (a graphArtifact) staleFinding(cutoff time.Time, evidence []graphArtifactEvidence) (graphWorkflowFinding, bool) {
	reasons := []string{}
	links := []graphWorkflowLink{a.destination}
	if saved, err := time.Parse(time.RFC3339Nano, a.review.UpdatedAt); err == nil && saved.Before(cutoff) {
		reasons = append(reasons, "距上次审核已超过期限")
	}
	if a.changed {
		reasons = append(reasons, "保存的正文已改变")
	}
	if len(evidence) == 0 {
		reasons = append(reasons, "未登记可核对的原文证据")
	}
	for _, e := range evidence {
		if e.status == "located" {
			continue
		}
		message := graphArtifactEvidenceMessage(e.status)
		if !slices.Contains(reasons, message) {
			reasons = append(reasons, message)
		}
		if e.link.URL != "" {
			links = append(links, e.link)
		}
	}
	return graphWorkflowFinding{Text: a.label() + " · " + strings.Join(reasons, "、"), Severity: "warning", Links: links}, len(reasons) > 0
}

func (a graphArtifact) claimFindings(filter string, evidence []graphArtifactEvidence) []graphWorkflowFinding {
	var findings []graphWorkflowFinding
	add := func(line int, detail, severity string, links ...graphWorkflowLink) {
		if filter == "" || filter == severity {
			findings = append(findings, graphWorkflowFinding{
				Text: a.label() + " · " + detail, Severity: severity, Line: line, Links: append([]graphWorkflowLink{a.destination}, links...),
			})
		}
	}
	if a.changed {
		add(0, "保存的正文已改变，需重新核对声明与引用", "warning")
		return findings
	}
	claims, truncated := WorkflowClaims(a.review.Body)
	inspected := false
	for _, claim := range claims {
		if !claim.Core && len(claim.References) == 0 {
			continue
		}
		inspected = true
		claimLabel := fmt.Sprintf("审核稿第 %d 行 %s", claim.Line, graphExcerptLabel(claim.Text))
		if len(claim.References) == 0 {
			add(claim.Line, claimLabel+" · 缺少声明对应的原文引用", "error")
			continue
		}
		var issues []string
		var links []graphWorkflowLink
		severity := "warning"
		for _, id := range claim.References {
			ordinal := a.review.CitationOrdinals[id]
			if ordinal < 1 || ordinal > len(a.review.Evidence) {
				if len(a.review.Evidence) > 0 && a.review.CitationOrdinals == nil {
					issues = append(issues, id+" 的引用映射未保存在这条旧审核记录中")
				} else {
					issues = append(issues, id+" 缺少已核对的原文记录")
					severity = "error"
				}
				continue
			}
			if ordinal > len(evidence) {
				continue
			}
			e := evidence[ordinal-1]
			if e.status == "located" {
				continue
			}
			issues = append(issues, id+" "+graphArtifactEvidenceMessage(e.status))
			if e.link.URL != "" {
				links = append(links, e.link)
			}
		}
		if len(issues) > 0 {
			add(claim.Line, claimLabel+" · "+strings.Join(issues, "、"), severity, links...)
		}
	}
	if !inspected && len(a.review.Evidence) == 0 {
		add(0, "未登记可核对的原文证据", "error")
	}
	if truncated {
		add(0, "正文超出声明核查范围，其余条目需分段核对", "warning")
	}
	return findings
}
