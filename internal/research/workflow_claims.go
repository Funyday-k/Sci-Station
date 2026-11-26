package research

import (
	"regexp"
	"slices"
	"strings"
	"unicode/utf8"
)

var (
	labClaimRef      = regexp.MustCompile(`(?i)\[(?:evidence:([a-z0-9_-]{1,80})|(S[1-9][0-9]{0,2}))\]`)
	labClaimListItem = regexp.MustCompile(`^(?:[-*+]\s+|\d+[.)]\s+)`)
	labStrongWording = regexp.MustCompile(`(?i)\b(?:best|significantly|state-of-the-art|sota|novel|first|only)\b|首创|首次|最优|唯一|显著`)
)

var labCoreClaimSections = strings.Split("tl;dr|contributions|method|methods|experiments|limitations|open questions|relevance to current project|scope|theme 1|theme 2|theme 3|research gap summary|current context|candidate gaps|hypotheses|proposed experiments|milestones|conclusions|结论|主要结论|主要贡献|核心发现|方法|研究方法|实验|局限|待核查问题|相关工作|主题 1|主题 2|主题 3|研究缺口|候选缺口|可检验假设|后续实验", "|")

const labClaimLimit = 160

type WorkflowClaim struct {
	Line       int      `json:"line"`
	Section    string   `json:"section,omitempty"`
	Text       string   `json:"text"`
	Core       bool     `json:"core,omitempty"`
	References []string `json:"references"`
	Status     string   `json:"status"`
	Warnings   []string `json:"warnings,omitempty"`
}

// WorkflowClaims extracts the same source references and claim lines for review and graph queries.
func WorkflowClaims(markdown string) ([]WorkflowClaim, bool) {
	claims := make([]WorkflowClaim, 0)
	var section, fence string
	var displayMath bool
	for i, line := range strings.Split(markdown, "\n") {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "```") || strings.HasPrefix(line, "~~~") {
			marker := line[:3]
			if fence == "" {
				fence = marker
			} else if fence == marker {
				fence = ""
			}
			continue
		}
		if fence != "" {
			continue
		}
		if strings.HasPrefix(line, "$$") && strings.Count(line, "$$") == 1 {
			displayMath = !displayMath
			continue
		}
		if displayMath || line == "" || strings.HasPrefix(line, ">") {
			continue
		}
		if strings.HasPrefix(line, "#") {
			section = strings.ToLower(strings.TrimSpace(strings.Trim(line, "#")))
			section = strings.Trim(labClaimListItem.ReplaceAllString(section, ""), " :：")
			continue
		}
		if slices.Contains([]string{"evidence", "evidence matrix", "证据", "证据矩阵", "参考文献", "sources", "references"}, section) {
			continue
		}
		text := labClaimListItem.ReplaceAllString(line, "")
		refs := claimReferences(text)
		trimmed := strings.TrimSpace(labClaimRef.ReplaceAllString(text, ""))
		if trimmed == "" || (len(refs) == 0 && (utf8.RuneCountInString(trimmed) < 8 || strings.HasPrefix(trimmed, "|"))) {
			continue
		}
		if len(claims) == labClaimLimit {
			return claims, true
		}
		core := slices.Contains(labCoreClaimSections, section)
		claim := WorkflowClaim{Line: i + 1, Section: section, Text: shortenClaim(text), Core: core, References: refs}
		if len(refs) > 0 && labStrongWording.MatchString(trimmed) {
			claim.Warnings = append(claim.Warnings, "strong_wording")
		}
		claims = append(claims, claim)
	}
	return claims, false
}

func claimReferences(text string) []string {
	refs := make([]string, 0)
	for _, match := range labClaimRef.FindAllStringSubmatch(text, -1) {
		ref := match[1] + match[2]
		if len(ref) > 1 && (ref[0] == 's' || ref[0] == 'S') && ref[1] >= '0' && ref[1] <= '9' {
			ref = strings.ToUpper(ref)
		}
		if !slices.Contains(refs, ref) {
			refs = append(refs, ref)
		}
	}
	return refs
}

func shortenClaim(text string) string {
	if utf8.RuneCountInString(text) <= 1500 {
		return text
	}
	return string([]rune(text)[:1500]) + "…"
}
