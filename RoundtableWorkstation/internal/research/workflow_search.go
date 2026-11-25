package research

import (
	"context"
	"encoding/json"
	"errors"
	"slices"
	"strings"
	"unicode/utf8"
)

type WorkflowMatch struct {
	Page   int    `json:"page,omitempty"`
	Offset int    `json:"offset"`
	Text   string `json:"text"`
}

type WorkflowMatches struct {
	Items   []WorkflowMatch `json:"items"`
	Limited bool            `json:"limited"`
}

// Each request scans one selected project record. The UI can cancel between
// records, and only sends a verified passage to the model after the user picks it.
func (s *Service) FindWorkflowSource(ctx context.Context, project string, loc SourceLocation, query string) (WorkflowMatches, error) {
	var out WorkflowMatches
	query = strings.TrimSpace(query)
	if !validID(project) || !validID(loc.ID) || !s.HasActiveProject(project) || query == "" || utf8.RuneCountInString(query) > 240 {
		return out, ErrWorkflowSource
	}
	if loc.Kind != "paper" {
		text, _, err := s.workflowRecord(project, loc)
		if err != nil {
			return out, err
		}
		return findWorkflowText(text, query), nil
	}
	p, ok := s.papers.Snapshot(loc.ID)
	if !ok || !p.HasPDF || !slices.Contains(p.ProjectIDs, project) {
		return out, ErrWorkflowSource
	}
	select {
	case pageWorkers <- struct{}{}:
		defer func() { <-pageWorkers }()
	case <-ctx.Done():
		return out, ctx.Err()
	}
	pdf, err := s.papers.verifiedPDFBytes(ctx, p)
	if err != nil {
		return out, err
	}
	data, err := findPDFEvidenceText(pdf, query)
	if err != nil {
		return out, err
	}
	if err = json.Unmarshal(data, &out); err != nil {
		return out, errors.New("无法读取全文检索结果")
	}
	if len(out.Items) > 12 {
		out.Items = out.Items[:12]
		out.Limited = true
	}
	return out, ctx.Err()
}

func findWorkflowText(text, query string) WorkflowMatches {
	text = strings.ReplaceAll(strings.ReplaceAll(text, "\r\n", "\n"), "\r", "\n")
	runes := []rune(text)
	folded, needle := strings.ToLower(text), strings.ToLower(query)
	out := WorkflowMatches{Items: []WorkflowMatch{}}
	if needle == "" {
		return out
	}
	var atByte, atRune int
	for {
		next := strings.Index(folded[atByte:], needle)
		if next < 0 {
			break
		}
		if len(out.Items) == 12 {
			out.Limited = true
			break
		}
		position := atRune + utf8.RuneCountInString(folded[atByte:atByte+next])
		length := utf8.RuneCountInString(needle)
		begin, end := max(0, position-35), min(len(runes), position+length+50)
		out.Items = append(out.Items, WorkflowMatch{Offset: position, Text: string(runes[begin:end])})
		atByte += next + len(needle)
		atRune = position + length
	}

	return out
}
