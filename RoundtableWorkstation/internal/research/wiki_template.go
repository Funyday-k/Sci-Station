package research

import (
	"maps"
	"net/http"
	"strings"

	"go.yaml.in/yaml/v3"
)

func (s *Service) createPaperWikiPage(w http.ResponseWriter, r *http.Request) {
	var in struct {
		PaperID  string `json:"paperId"`
		Revision int    `json:"revision"`
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
	paper, ok := s.papers.Snapshot(in.PaperID)
	if !found(w, ok) || !revisionOK(w, paper.Revision, in.Revision) {
		return
	}
	for _, note := range d.Notes {
		if note.Template == "paper" && note.PaperID == paper.ID {
			jsonFail(w, 409, "该项目已有此论文的 Wiki 页面，可在项目 Wiki 或归档中找到")
			return
		}
	}
	n := Note{
		Entity: fresh(), ProjectID: d.Project.ID, PaperID: paper.ID, Namespace: "papers",
		Template: "paper", Tags: []string{}, Evidence: []Evidence{},
	}
	title := strings.Join(strings.Fields(paper.Title), " ")
	n.Title = wikiTruncate(title, 240)
	if validWikiPath(paper.Citekey) {
		n.Aliases = []string{"papers/" + paper.Citekey}
	}
	if wikiNameTaken(d, n) {
		key := " (" + wikiTruncate(paper.Citekey, 120) + ")"
		n.Title = wikiTruncate(title, 240-len([]rune(key))) + key
		if wikiNameTaken(d, n) {
			jsonFail(w, 409, "论文 Wiki 的路径或引用键已被项目中的页面使用")
			return
		}
	}
	meta := map[string]any{
		"type": "paper", "id": paper.ID, "citekey": paper.Citekey, "title": paper.Title,
		"authors": paper.Authors, "tags": paper.Tags, "status": "imported", "created": n.CreatedAt[:10],
	}
	if paper.Year > 0 {
		meta["year"] = paper.Year
	}
	if paper.DOI != "" {
		meta["doi"] = paper.DOI
	}
	if paper.Arxiv != "" {
		meta["arxiv"] = paper.Arxiv
	}
	if paper.HasPDF {
		meta["source_pdf"] = prefix + "/papers/" + paper.ID + "/pdf"
		meta["source_raw_md"] = prefix + "/papers/" + paper.ID + "/markdown"
		meta["source_hash"] = paper.FileSHA256
	}
	frontmatter, err := yaml.Marshal(meta)
	if err != nil {
		jsonFail(w, 500, "无法生成论文 Wiki 元数据")
		return
	}
	n.Body = "---\n" + string(frontmatter) + "---\n\n# " + title + "\n\n" + paperWikiOutline + "\n\n[@" + paper.Citekey + "]\n"
	d.Notes = maps.Clone(d.Notes)
	d.Notes[n.ID] = n
	if s.save(w, d) {
		jsonReply(w, 201, n)
	}
}

func wikiTruncate(value string, count int) string {
	runes := []rune(value)
	if len(runes) <= count {
		return value
	}
	return strings.TrimSpace(string(runes[:count]))
}

const paperWikiOutline = `## TL;DR

## 研究问题

## 方法概述

## 关键贡献

## 实验与证据

## 局限性

## 与已有工作的关系

## 可复现性检查

## 对我研究的启发

## 相关概念

## 可能研究空白

## 引用`
