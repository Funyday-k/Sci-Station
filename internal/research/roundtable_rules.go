package research

import (
	"cmp"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"unicode"
	"unicode/utf8"

	"scistation.local/desktop/internal/workspace"
)

const MaxRoundtableRuleBytes = 32 << 10
const MaxRoundtableRules = 24

type RoundtableProjectSummary struct {
	ID        string `json:"id,omitempty"`
	Name      string `json:"name"`
	Path      string `json:"path"`
	RuleCount int    `json:"rule_count"`
}

// Listing projects does not need to read or validate imported guidance.
func (s *Service) RoundtableProjects() []RoundtableProjectSummary {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := []RoundtableProjectSummary{}
	for _, d := range s.projects {
		if !d.Archived {
			out = append(out, RoundtableProjectSummary{ID: d.Project.ID, Name: d.Project.Name, Path: d.Project.Path, RuleCount: len(d.RoundtableRules)})
		}
	}
	slices.SortFunc(out, func(a, b RoundtableProjectSummary) int {
		if a.Name != b.Name {
			return cmp.Compare(a.Name, b.Name)
		}
		return cmp.Compare(a.ID, b.ID)
	})
	return out
}

type RoundtableRuleVersion struct {
	Path   string `json:"path"`
	Digest string `json:"digest"`
}

type RoundtableRule struct {
	RoundtableRuleVersion
	Source string `json:"source"`
	Text   string `json:"text"`
}

func RoundtableRuleSource(path string) string {
	switch path {
	case "AGENTS.md":
		return "AGENTS.md"
	case "AGENTS.override.md":
		return "Codex"
	case "CLAUDE.md", ".claude/CLAUDE.md":
		return "Claude Code"
	case ".cursorrules":
		return "Cursor"
	}
	if len(path) > 1024 || !fs.ValidPath(path) || path == "." || strings.ContainsRune(path, '\\') || strings.IndexFunc(path, unicode.IsControl) >= 0 {
		return ""
	}
	parts := strings.Split(path, "/")
	if len(parts) < 3 || len(parts) > 7 {
		return ""
	}
	for _, part := range parts[2:] {
		if strings.HasPrefix(part, ".") {
			return ""
		}
	}
	switch {
	case strings.HasPrefix(path, ".claude/rules/") && filepath.Ext(path) == ".md":
		return "Claude Code"
	case strings.HasPrefix(path, ".cursor/rules/") && filepath.Ext(path) == ".mdc":
		return "Cursor"
	}
	return ""
}

func ValidRoundtableRuleText(text string) bool {
	return len(text) <= MaxRoundtableRuleBytes && utf8.ValidString(text) && !strings.ContainsRune(text, 0) && strings.TrimSpace(text) != ""
}

func RoundtableRuleDigest(text string) string {
	digest := sha256.Sum256([]byte(text))
	return hex.EncodeToString(digest[:])
}

func RoundtableRuleText(rules []RoundtableRule) string {
	var context strings.Builder
	for _, rule := range rules {
		fmt.Fprintf(&context, "Source: %s (%s)\n%s\n\n", rule.Path, rule.Source, rule.Text)
	}
	return context.String()
}

func ValidRoundtableRules(rules []RoundtableRule) bool {
	if len(rules) > MaxRoundtableRules {
		return false
	}
	seen := map[string]bool{}
	for _, rule := range rules {
		if seen[rule.Path] || rule.Source == "" || rule.Source != RoundtableRuleSource(rule.Path) ||
			!ValidRoundtableRuleText(rule.Text) || rule.Digest != RoundtableRuleDigest(rule.Text) {
			return false
		}
		seen[rule.Path] = true
	}
	return len(RoundtableRuleText(rules)) <= 64<<10
}

// MergeRoundtableRules replaces snapshots by relative path and validates the complete project rule set.
func MergeRoundtableRules(old, additions []RoundtableRule) ([]RoundtableRule, error) {
	combined := slices.Clone(old)
	for _, addition := range additions {
		index := slices.IndexFunc(combined, func(rule RoundtableRule) bool { return rule.Path == addition.Path })
		if index < 0 {
			combined = append(combined, addition)
		} else {
			combined[index] = addition
		}
	}
	if !ValidRoundtableRules(combined) {
		return nil, errors.New("项目规则无效或超出 24 个文件／64 KiB 的限制")
	}
	slices.SortFunc(combined, func(a, b RoundtableRule) int { return strings.Compare(a.Path, b.Path) })
	return combined, nil
}

// Rules are saved snapshots. Viewing or disabling them needs an active
// project record, but does not require access to the original files.
func (s *Service) RoundtableRules(id string, expectedPath string) ([]RoundtableRule, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	d, ok := s.projects[id]
	if !ok || d.Archived {
		return nil, os.ErrNotExist
	}
	if expectedPath != "" {
		current, err := s.directory(d)
		if err != nil {
			return nil, err
		}
		if current != expectedPath {
			return nil, os.ErrPermission
		}
	}
	if !ValidRoundtableRules(d.RoundtableRules) {
		return nil, errors.New("无法读取项目规则配置")
	}
	return append([]RoundtableRule{}, d.RoundtableRules...), nil
}

func (s *Service) DisableRoundtableRule(id, expectedPath string, ref RoundtableRuleVersion) ([]RoundtableRule, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	d, ok := s.projects[id]
	if !ok || d.Archived {
		return nil, os.ErrNotExist
	}
	if expectedPath != "" {
		current, err := s.directory(d)
		if err != nil {
			return nil, err
		}
		if current != expectedPath {
			return nil, os.ErrPermission
		}
	}
	for i, rule := range d.RoundtableRules {
		if rule.Path != ref.Path {
			continue
		}
		if rule.Digest != ref.Digest {
			return nil, fmt.Errorf("%w: 这条规则已有新版本，请重新查看", workspace.ErrConflict)
		}
		d.RoundtableRules = slices.Delete(slices.Clone(d.RoundtableRules), i, i+1)
		d.Project.bump()
		if err := s.commit(d); err != nil {
			return nil, err
		}
		break
	}
	return append([]RoundtableRule{}, d.RoundtableRules...), nil
}
