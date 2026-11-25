package research

import (
	"errors"
	"path/filepath"
	"slices"
	"strings"
	"unicode/utf8"

	"scistation.local/desktop/internal/workspace"
)

type BodySection struct {
	Heading string `json:"heading"`
	Line    int    `json:"line"`
}

func (s *PaperLibrary) projectMarkdown(project, id string) (string, Paper, error) {
	if !validID(id) {
		return "", Paper{}, ErrWorkflowSource
	}
	disk, err := workspace.ManagedReadFile(filepath.Join(s.dir, "records", id+".json"))
	if err != nil {
		return "", Paper{}, ErrWorkflowSource
	}
	p, err := decodePaperRecord(id, disk)
	if err != nil || !slices.Contains(p.ProjectIDs, project) {
		return "", Paper{}, ErrWorkflowSource
	}
	if p.Markdown == nil {
		return "", p, errors.New("尚无论文 Markdown 正文。请先导入 Markdown 文件或转换已有 PDF")
	}
	b, err := s.readBodyLocked(p)
	if err != nil {
		return "", p, err
	}
	return string(b), p, nil
}

func bodyLocation(text string, offset int) (int, string) {
	pos := 0
	line := 1
	heading := ""
	fence := ""
	for raw := range strings.SplitSeq(text, "\n") {
		if h := markdownLineHeading(raw, &fence); h != "" {
			heading = h
		}
		pos += utf8.RuneCountInString(raw) + 1
		if pos > offset {
			break
		}
		line++
	}
	return line, heading
}
func bodyHeading(raw string) string {
	raw = strings.TrimPrefix(raw, "\ufeff")
	s := strings.TrimLeft(raw, " ")
	if len(raw)-len(s) > 3 {
		return ""
	}
	title := strings.TrimLeft(s, "#")
	level := len(s) - len(title)
	if level < 1 || level > 6 || !strings.HasPrefix(title, " ") {
		return ""
	}
	return strings.TrimSpace(strings.TrimRight(strings.TrimSpace(title), "#"))
}

func markdownOutline(text string, requested int) ([]BodySection, int, error) {
	var headings []BodySection
	offset := 0
	line := 1
	target := -1
	fence := ""
	for raw := range strings.SplitSeq(text, "\n") {
		if line == requested {
			target = offset
		}
		if h := markdownLineHeading(raw, &fence); h != "" && len(headings) < 128 {
			headings = append(headings, BodySection{h, line})
		}
		offset += utf8.RuneCountInString(raw) + 1
		line++
	}
	if requested < 0 || requested > 0 && target < 0 {
		return nil, 0, errors.New("行号超出论文正文范围")
	}
	return headings, target, nil
}

func (e Evidence) linkedPaperID() string {
	if e.Source != nil && e.Source.Kind == "paper-markdown" {
		return e.Source.ID
	}
	return e.PaperID
}

func (s *Service) workflowMarkdown(project, id string) (text string, paper Paper, err error) {
	err = s.WithProjectDirectory(project, func(string) error {
		var e error
		text, paper, e = s.papers.projectMarkdown(project, id)
		return e
	})
	return
}

func (src WorkflowSource) HasBodyQuote(quote string) bool {
	return src.Kind != "paper-markdown" || realMarkdownBody([]byte(quote))
}

func markdownLineHeading(raw string, fence *string) string {
	value := strings.TrimSpace(raw)
	if *fence != "" {
		if strings.HasPrefix(value, *fence) && strings.Trim(value, string((*fence)[0])) == "" {
			*fence = ""
		}
		return ""
	}
	if strings.HasPrefix(value, "```") || strings.HasPrefix(value, "~~~") {
		*fence = value[:len(value)-len(strings.TrimLeft(value, string(value[0])))]
		return ""
	}
	return bodyHeading(raw)
}
