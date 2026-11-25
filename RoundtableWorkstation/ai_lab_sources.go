package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"unicode/utf8"

	"scistation.local/desktop/internal/meeting"
	"scistation.local/desktop/internal/research"
)

type labCitation struct {
	research.SourceLocation
	Hash  string `json:"hash"`
	Quote string `json:"quote"`
}

type labSourcesRequest struct {
	Query     string                  `json:"query"`
	Scope     string                  `json:"scope"`
	ProjectID string                  `json:"projectId"`
	Workflow  string                  `json:"workflow"`
	Location  research.SourceLocation `json:"location"`
	Citations []labCitation           `json:"citations"`
}

func (a *apiServer) serveLabSources(w http.ResponseWriter, r *http.Request, path string) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", "POST")
		reject(w, 405, "请提交项目和来源")
		return
	}
	lab, ok := a.research.(*research.Service)
	if !ok || a.meetings == nil {
		reject(w, 503, "未打开科研工作区")
		return
	}
	var in labSourcesRequest
	if !jsonBody(w, r, &in) {
		return
	}
	global := in.Scope == "global" && in.ProjectID == "" && len(in.Citations) == 0 && path == "sources/prepare"
	if in.Scope != "" && !global {
		reject(w, 400, "全局会话无法选择项目材料")
		return
	}
	if !global && !lab.HasActiveProject(in.ProjectID) {
		reject(w, 404, "项目不存在或已归档")
		return
	}
	if !requireLabModules(w, lab, in, path != "sources/prepare") {
		return
	}
	if path == "sources/search" {
		results, err := lab.FindWorkflowSource(r.Context(), in.ProjectID, in.Location, in.Query)
		if err != nil {
			reject(w, 422, err.Error())
			return
		}
		reply(w, 200, results)
		return
	}
	if path == "sources/preview" {
		source, err := lab.WorkflowSource(r.Context(), in.ProjectID, in.Location)
		if err != nil {
			reject(w, 422, err.Error())
			return
		}
		reply(w, 200, source)
		return
	}
	if len(in.Citations) > 4 {
		reject(w, 400, "每次最多选择四段原文")
		return
	}
	type attachment struct{ name, body string }
	attachments := make([]attachment, 0, len(in.Citations))
	seen := make(map[research.SourceLocation]bool)
	papers := make(map[string]bool)
	for _, citation := range in.Citations {
		if seen[citation.SourceLocation] || strings.TrimSpace(citation.Quote) == "" || utf8.RuneCountInString(citation.Quote) > 1000 {
			reject(w, 400, "选段重复、为空或超过 1,000 字")
			return
		}
		seen[citation.SourceLocation] = true
		source, err := lab.WorkflowSource(r.Context(), in.ProjectID, citation.SourceLocation)
		if err != nil {
			reject(w, 422, err.Error())
			return
		}
		if source.Hash != citation.Hash || !strings.HasPrefix(source.Text, citation.Quote) {
			reject(w, 409, "来源内容已改变，请重新选择原文")
			return
		}
		if source.Kind == "paper" {
			papers[source.ID] = true
		}
		name, body := labAttachment(in.ProjectID, source, citation.Quote)
		attachments = append(attachments, attachment{name, body})
	}
	if err := labRequiredEvidence(in.Workflow, len(papers), len(attachments)); err != nil {
		reject(w, 422, err.Error())
		return
	}
	materials := make([]meeting.Material, 0, len(attachments))
	for _, item := range attachments {
		m, err := a.meetings.StoreMaterial(item.name, strings.NewReader(item.body))
		if err != nil {
			reject(w, 500, "无法保存原文摘录")
			return
		}
		materials = append(materials, m)
	}
	reply(w, 200, materials)
}

func labRequiredEvidence(workflow string, papers, sources int) error {
	switch {
	case workflow == "paper-reading" && papers < 1:
		return errors.New("论文精读需要至少一段论文页正文")
	case workflow == "related-work" && papers < 2:
		return errors.New("相关工作比较需要来自至少两篇论文的正文")
	case workflow == "gap-planning" && sources < 1:
		return errors.New("研究空缺分析需要至少一段项目笔记、材料或论文原文")
	}
	return nil
}

func labAttachment(project string, source research.WorkflowSource, quote string) (string, string) {
	title := []rune(source.Title)
	title = title[:min(len(title), 180)]
	if source.Kind == "paper" {
		raw, start, end := source.PDFSelection(quote)
		header, _ := json.Marshal(map[string]any{"selectionStart": start, "selectionEnd": end, "projectId": project, "paperId": source.ID, "page": source.Page, "title": string(title), "fingerprint": source.Hash, "offset": source.Offset})
		return fmt.Sprintf("%s · p%d.txt", string(title), source.Page), "Sci-Station · 论文原文摘录 v1\n" + string(header) + "\n\n" + raw
	}
	header, _ := json.Marshal(map[string]any{"projectId": project, "kind": source.Kind, "id": source.ID, "title": string(title), "sha256": source.Hash, "offset": source.Offset})
	return string(title) + ".txt", "Sci-Station · 项目原文摘录 v1\n" + string(header) + "\n\n" + quote
}

func requireLabModules(w http.ResponseWriter, lab *research.Service, in labSourcesRequest, preview bool) bool {
	required := []string{"ai-lab"}
	switch in.Workflow {
	case "paper-reading":
		required = append(required, "pdf-reader")
	case "related-work":
		required = append(required, "citation-graph", "wiki")
	case "gap-planning":
		required = append(required, "wiki", "tasks", "citation-graph")
	}
	sourceModule := map[string]string{"paper": "pdf-reader", "note": "wiki", "material": "materials"}
	if preview {
		required = append(required, sourceModule[in.Location.Kind])
	} else {
		for _, ref := range in.Citations {
			required = append(required, sourceModule[ref.Kind])
		}
	}
	checked := map[string]bool{}
	for _, id := range required {
		if id == "" || checked[id] {
			continue
		}
		checked[id] = true
		enabled, err := lab.ModuleEnabled(in.ProjectID, id)
		if err != nil {
			reject(w, 503, "无法读取项目模块设置")
			return false
		}
		if !enabled {
			reject(w, 409, "本工作流依赖已停用的模块："+id)
			return false
		}
	}
	return true
}
