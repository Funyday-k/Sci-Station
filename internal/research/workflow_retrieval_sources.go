package research

import (
	"crypto/sha256"
	"errors"
	"fmt"
	"os"
	"slices"
	"strings"
)

var errRetrievalSourceTooLarge = errors.New("原文超过本次本地索引容量")

type workflowRetrievalSource struct {
	SourceLocation
	core bool
}

func (s *Service) workflowRetrievalSources(project string) ([]workflowRetrievalSource, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	d, ok := s.projects[project]
	if !ok || d.Archived || d.Trashed {
		return nil, ErrWorkflowSource
	}
	if _, err := s.directory(d); err != nil {
		return nil, os.ErrPermission
	}
	config, err := s.readModuleConfig(project)
	if err != nil || !config.effective("ai-lab", project) {
		return nil, ErrWorkflowSource
	}

	var sources []workflowRetrievalSource
	if config.effective("wiki", project) {
		for id, note := range d.Notes {
			if !note.Archived && note.ProjectID == project && validID(id) {
				sources = append(sources, workflowRetrievalSource{SourceLocation: SourceLocation{Kind: "note", ID: id}})
			}
		}
	}
	if config.effective("materials", project) {
		for id, material := range d.Materials {
			if material.ProjectID == project && strings.HasPrefix(material.MediaType, "text/plain") && validID(id) {
				sources = append(sources, workflowRetrievalSource{SourceLocation: SourceLocation{Kind: "material", ID: id}})
			}
		}
	}
	if config.effective("paper-library", project) {
		s.papers.mu.RLock()
		for id, paper := range s.papers.records {
			if paper.Markdown != nil && slices.Contains(paper.ProjectIDs, project) {
				sources = append(sources, workflowRetrievalSource{
					SourceLocation: SourceLocation{Kind: "paper-markdown", ID: id},
					core:           slices.Contains(paper.CoreProjectIDs, project),
				})
			}
		}
		s.papers.mu.RUnlock()
	}
	slices.SortFunc(sources, func(a, b workflowRetrievalSource) int {
		return strings.Compare(a.key(), b.key())
	})
	return sources, nil
}

func (source workflowRetrievalSource) key() string {
	return source.Kind + ":" + source.ID
}

func (s *Service) readWorkflowRetrievalSource(project string, loc SourceLocation, maxBytes int) (text, title, hash string, err error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	d, ok := s.projects[project]
	if !ok || d.Archived || d.Trashed {
		return "", "", "", ErrWorkflowSource
	}
	if _, err = s.directory(d); err != nil {
		return "", "", "", os.ErrPermission
	}
	if loc.Kind == "paper-markdown" {
		var p Paper
		text, p, err = s.papers.projectMarkdownWithin(project, loc.ID, maxBytes)
		if err == nil {
			title, hash = p.Title, p.Markdown.Hash
		}
		return
	}
	if loc.Kind == "material" && d.Materials[loc.ID].Size > int64(maxBytes) ||
		loc.Kind == "note" && len(d.Notes[loc.ID].Body) > maxBytes {
		return "", "", "", errRetrievalSourceTooLarge
	}
	text, title, err = s.workflowRecordLocked(d, loc)
	if err == nil {
		hash = fmt.Sprintf("%x", sha256.Sum256([]byte(text)))
	}
	return
}
