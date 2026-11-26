package main

import (
	"slices"
	"strings"
	"unicode/utf8"

	"scistation.local/desktop/internal/research"
)

type labClaim = research.WorkflowClaim

func labClaims(markdown string) ([]labClaim, bool) {
	return research.WorkflowClaims(markdown)
}

// Structural statuses describe citation coverage, never claim truth.
func labClaimStatuses(claims []labClaim, sources map[string]labEvidenceReference) {
	reuse := make(map[string]int)
	for i := range claims {
		claim := &claims[i]
		var located int
		for _, id := range claim.References {
			reuse[id]++
			if sources[id].Status == "located" {
				located++
			}
		}
		switch {
		case len(claim.References) == 0:
			claim.Status = "missing_reference"
		case located == len(claim.References):
			claim.Status = "located"
		case located > 0:
			claim.Status = "incomplete"
		default:
			claim.Status = "unresolved"
		}
	}
	for i := range claims {
		for _, ref := range claims[i].References {
			if reuse[ref] > 3 {
				claims[i].Warnings = append(claims[i].Warnings, "reused_source")
				break
			}
		}
	}
}

func labQualityIssues(goal, answer string, hasPaper, hasPaperCitation bool) []string {
	answer = strings.ToLower(strings.TrimSpace(answer))
	goal = strings.ToLower(goal)
	issues := make([]string, 0)
	if utf8.RuneCountInString(answer) < 12 || (strings.Contains(answer, "tools used") && strings.Contains(answer, "last tool result")) ||
		(strings.Contains(answer, "已使用工具") && strings.Contains(answer, "最后一个工具结果")) {
		issues = append(issues, "missing_direct_answer")
	}
	formula := containsLabPhrase(goal, "formula", "equation", "蒸发率", "evaporation rate", "公式", "方程")
	mentionsPaper := containsLabPhrase(goal, "paper", "论文", "文章", "文献")
	needsPaper := formula || (mentionsPaper && containsLabPhrase(goal, "summary", "summarize", "abstract", "methods", "method", "section", "claim", "citation", "source", "reading note", "摘要", "正文", "方法", "结论", "章节", "概括", "精读", "引用", "来源", "笔记"))
	if needsPaper && !hasPaper {
		issues = append(issues, "missing_evidence")
		if !containsLabPhrase(answer, "没有读取", "未读取", "paper.md", "not read", "missing") {
			issues = append(issues, "missing_content_explanation")
		}
	}
	if formula && strings.Count(answer, "$$") < 2 && !(strings.Contains(answer, `\[`) && strings.Contains(answer, `\]`)) {
		issues = append(issues, "missing_display_math")
	}
	if needsPaper && hasPaper && !hasPaperCitation {
		issues = append(issues, "missing_source")
	}
	return issues
}

func containsLabPhrase(text string, phrases ...string) bool {
	return slices.ContainsFunc(phrases, func(phrase string) bool { return strings.Contains(text, phrase) })
}
