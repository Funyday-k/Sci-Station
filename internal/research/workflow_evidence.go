package research

import (
	"context"
	"errors"
	"slices"
	"strings"
)

// CheckWorkflowCitation verifies a recorded excerpt in its current project.
// The evidence check is read-only and also respects the source module.
func (s *Service) CheckWorkflowCitation(ctx context.Context, project string, loc SourceLocation, evidence Evidence) (title, status string) {
	module, ok := map[string]string{"paper": "pdf-reader", "paper-markdown": "paper-library", "note": "wiki", "material": "materials"}[loc.Kind]
	if !ok {
		return "", "unavailable"
	}
	enabled, err := s.ModuleEnabled(project, module)
	if err != nil || !enabled {
		return "", "unavailable"
	}
	if loc.Kind == "paper" {
		p, found := s.papers.Snapshot(loc.ID)
		if !found || !slices.Contains(p.ProjectIDs, project) || !s.HasActiveProject(project) {
			return "", "unavailable"
		}
		if err := s.papers.verifyPDFEvidence(ctx, evidence, p); err != nil {
			if errors.Is(err, errPaperConflict) {
				return p.Title, "stale"
			}
			return p.Title, "unavailable"
		}
		return p.Title, "located"
	}
	if loc.Kind == "note" || loc.Kind == "material" {
		s.mu.RLock()
		defer s.mu.RUnlock()
		d, found := s.projects[project]
		if !found || d.Archived || evidence.Source == nil {
			return "", "unavailable"
		}
		part, err := s.verifiedProjectSource(d, *evidence.Source, evidence.SourceHash, false)
		if errors.Is(err, errProjectEvidenceChanged) {
			return "", "stale"
		}
		if err != nil {
			return "", "unavailable"
		}
		if part.Quote != evidence.Quote {
			return part.Title, "invalid_quote"
		}
		return part.Title, "located"
	}
	source, err := s.WorkflowSource(ctx, project, loc)
	if err != nil {
		return "", "unavailable"
	}
	if source.Hash != evidence.SourceHash {
		return source.Title, "stale"
	}
	if !strings.HasPrefix(source.Text, evidence.Quote) || evidence.Quote == "" {
		return source.Title, "invalid_quote"
	}
	return source.Title, "located"
}
