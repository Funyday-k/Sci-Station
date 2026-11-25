package research

import (
	"context"
	"crypto/sha256"
	"errors"
	"fmt"
	"io"
	"os"
	"slices"
	"strings"
	"syscall"
	"unicode/utf16"
	"unicode/utf8"

	"scistation.local/desktop/internal/workspace"
)

// SourceLocation addresses a research record and a Unicode character offset.
// PDF page numbers are one-based. A hash identifies the version actually read.
type SourceLocation struct {
	Kind   string `json:"kind"`
	ID     string `json:"id"`
	Page   int    `json:"page,omitempty"`
	Offset int    `json:"offset,omitempty"`
}

type WorkflowSource struct {
	rawText  string
	Revision int           `json:"revision,omitempty"`
	Line     int           `json:"line,omitempty"`
	Heading  string        `json:"heading,omitempty"`
	Sections []BodySection `json:"sections,omitempty"`
	SourceLocation
	Title string `json:"title"`
	Hash  string `json:"hash"`
	Text  string `json:"text"`
	More  bool   `json:"more"`
}

var ErrWorkflowSource = errors.New("来源无效或不属于当前项目")

const workflowWindow = 4000

func (s *Service) WorkflowSource(ctx context.Context, project string, loc SourceLocation) (WorkflowSource, error) {
	return s.WorkflowSourceAtLine(ctx, project, loc, 0)
}
func (s *Service) WorkflowSourceAtLine(ctx context.Context, project string, loc SourceLocation, line int) (WorkflowSource, error) {
	var out WorkflowSource
	if !validID(project) || !validID(loc.ID) || loc.Offset < 0 || (loc.Kind == "paper" && (loc.Page < 1 || loc.Page > 100000)) || (loc.Kind != "paper" && loc.Page != 0) {
		return out, ErrWorkflowSource
	}
	var meta WorkflowSource
	var text, title, hash string
	var err error
	if loc.Kind == "paper" {
		if !s.HasActiveProject(project) {
			return out, ErrWorkflowSource
		}
		text, title, hash, err = s.workflowPaperPage(ctx, project, loc)
	} else if loc.Kind == "paper-markdown" {
		if !s.HasActiveProject(project) {
			return out, ErrWorkflowSource
		}
		var p Paper
		text, p, err = s.workflowMarkdown(project, loc.ID)
		if err != nil {
			return out, err
		}
		title = p.Title
		hash = p.Markdown.Hash
		meta.Revision = p.Markdown.Revision
	} else {
		text, title, err = s.workflowRecord(project, loc)
		hash = fmt.Sprintf("%x", sha256.Sum256([]byte(text)))
	}
	if err != nil {
		return out, err
	}
	if strings.TrimSpace(text) == "" {
		return out, errors.New("来源没有可引用的正文。扫描版论文请先转换为可检索文本")
	}
	// HTML textareas normalize CR and CRLF to LF. Keep offsets reproducible across native and web previews.
	normalized := normalizeWorkflowText(text)
	if loc.Kind == "paper-markdown" {
		var target int
		meta.Sections, target, err = markdownOutline(normalized, line)
		if err != nil {
			return out, err
		}
		if target >= 0 {
			loc.Offset = target
		}
		meta.Line, meta.Heading = bodyLocation(normalized, loc.Offset)
	} else if line != 0 {
		return out, ErrWorkflowSource
	}
	runes := []rune(normalized)
	if loc.Offset >= len(runes) {
		return out, errors.New("原文位置超出范围，请重新预览")
	}
	end := loc.Offset + min(len(runes)-loc.Offset, workflowWindow)
	meta.rawText = text
	meta.SourceLocation = loc
	meta.Title = title
	meta.Hash = hash
	meta.Text = string(runes[loc.Offset:end])
	meta.More = end < len(runes)
	return meta, nil
}

func (s *Service) workflowPaperPage(ctx context.Context, project string, loc SourceLocation) (string, string, string, error) {
	p, ok := s.papers.Snapshot(loc.ID)
	if !ok || !p.HasPDF || !slices.Contains(p.ProjectIDs, project) {
		return "", "", "", ErrWorkflowSource
	}
	text, err := s.papers.verifiedPageText(ctx, p, Evidence{PaperID: p.ID, Page: loc.Page, SourceHash: p.FileSHA256})
	return text, p.Title, p.FileSHA256, err
}

func (s *Service) workflowRecord(project string, loc SourceLocation) (string, string, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	d, ok := s.projects[project]
	if !ok || d.Archived {
		return "", "", ErrWorkflowSource
	}
	if _, err := s.directory(d); err != nil {
		return "", "", os.ErrPermission
	}
	return s.workflowRecordLocked(d, loc)
}

func normalizeWorkflowText(text string) string {
	return strings.ReplaceAll(strings.ReplaceAll(text, "\r\n", "\n"), "\r", "\n")
}

// The caller holds the project lock and has authorized the owning directory.
func (s *Service) workflowRecordLocked(d projectData, loc SourceLocation) (string, string, error) {
	switch loc.Kind {
	case "note":
		n, ok := d.Notes[loc.ID]
		if !ok || n.Archived || n.ProjectID != d.Project.ID {
			return "", "", ErrWorkflowSource
		}
		return n.Body, n.Title, nil
	case "material":
		m, ok := d.Materials[loc.ID]
		if !ok || m.ProjectID != d.Project.ID {
			return "", "", ErrWorkflowSource
		}
		if !strings.HasPrefix(m.MediaType, "text/plain") {
			return "", "", errors.New("请选择纯文本项目材料")
		}
		const maxSize = 4 << 20
		if m.Size > maxSize {
			return "", "", errors.New("请先从大于 4 MiB 的材料中另存所需文本部分")
		}
		f, err := workspace.ManagedOpenFile(s.blobPath(m.ID), os.O_RDONLY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK, 0)
		if err != nil {
			return "", "", errors.New("材料文件不可用")
		}
		defer f.Close()
		stat, err := f.Stat()
		if err != nil || !stat.Mode().IsRegular() || stat.Size() != m.Size {
			return "", "", errors.New("材料文件已改变")
		}
		data, err := io.ReadAll(io.LimitReader(f, maxSize+1))
		if err != nil || int64(len(data)) != m.Size || !utf8.Valid(data) {
			return "", "", errors.New("无法读取 UTF-8 文本材料")
		}
		return string(data), m.Name, nil
	default:
		return "", "", ErrWorkflowSource
	}
}

// Raw PDFKit offsets count UTF-16 units. Textarea offsets supplied in a citation
// count Unicode characters after normalizing line endings.
func (s WorkflowSource) PDFSelection(quote string) (string, int, int) {
	start, units := originalTextOffset(s.rawText, s.Offset)
	length, span := originalTextOffset(s.rawText[start:], utf8.RuneCountInString(quote))
	return s.rawText[start : start+length], units, units + span
}

func originalTextOffset(text string, n int) (bytes, units int) {
	for n > 0 && bytes < len(text) {
		r, size := utf8.DecodeRuneInString(text[bytes:])
		bytes += size
		units += utf16.RuneLen(r)
		if r == '\r' && bytes < len(text) && text[bytes] == '\n' {
			bytes++
			units++
		}
		n--
	}
	return bytes, units
}
