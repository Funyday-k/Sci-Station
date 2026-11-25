package research

import (
	"context"
	"errors"
	"fmt"
	"os"
	"slices"
	"sort"
	"strings"
)

// DiscoveryCandidate retains source metadata separately from editable library fields.
type DiscoveryCandidate struct {
	PaperMetadata
	PaperID         string              `json:"paper_id,omitempty"`
	PrimaryCategory string              `json:"primary_category,omitempty"`
	PublishedAt     string              `json:"published_at,omitempty"`
	Provider        string              `json:"provider,omitempty"`
	GraphEvidence   []DiscoveryCitation `json:"graph_evidence,omitempty"`
	Reasons         []string            `json:"reasons,omitempty"`
}

type DiscoveryCitation struct {
	PaperID    string `json:"paper_id"`
	PaperTitle string `json:"paper_title"`
	Kind       string `json:"kind"`
	RelationID string `json:"relation_id,omitempty"`
	Reference  string `json:"reference,omitempty"`
}

func (c DiscoveryCandidate) Key() string {
	switch {
	case c.Arxiv != "":
		return ArxivWorkID(c.Arxiv)
	case c.DOI != "":
		return "doi:" + paperRefKey(c.DOI)
	default:
		return "paper:" + c.PaperID
	}
}

type DiscoveryContext struct {
	Project Project
	Library []Paper
	Graph   []DiscoveryCandidate
	Refs    []Paper
}

// DiscoveryContext snapshots scoped library records and follows real graph
// connections from core papers. References without a resolvable paper ID are
// surfaced only when they contain a supported bibliographic identifier.
func (s *Service) DiscoveryContext(project string, refIDs []string) (DiscoveryContext, error) {
	var context DiscoveryContext
	var relations map[string]GraphRelation
	if project != "" {
		s.mu.RLock()
		d, ok := s.projects[project]
		s.mu.RUnlock()
		if !ok || d.Archived {
			return context, fmt.Errorf("科研项目不存在或已归档")
		}
		context.Project, relations = d.Project, d.Relations
	}
	all := s.papers.all()
	context.Library = filterPapers(all, project, "", "")
	scoped := make(map[string]Paper, len(context.Library))
	lookup := make(map[string]Paper, len(all))
	for _, p := range all {
		for _, identifier := range []string{p.ID, p.Arxiv, p.DOI, p.Citekey, p.URL} {
			key := discoveryReferenceKey(identifier)
			if key != "" {
				lookup[key] = p
			}
		}
	}
	for _, p := range context.Library {
		scoped[p.ID] = p
	}
	for _, id := range refIDs {
		p, ok := scoped[id]
		if !ok {
			return context, fmt.Errorf("参考论文不在当前范围内")
		}
		context.Refs = append(context.Refs, p)
	}
	if project == "" {
		return context, nil
	}

	candidates := map[string]DiscoveryCandidate{}
	add := func(key string, evidence DiscoveryCitation) {
		key = discoveryReferenceKey(key)
		if key == "" {
			return
		}
		var candidate DiscoveryCandidate
		if p, ok := lookup[key]; ok {
			if p.ID == evidence.PaperID || paperContains(p.CoreProjectIDs, project) {
				return
			}
			// Only the editable metadata is shown. A recommendation never exposes the local PDF.
			candidate = DiscoveryCandidate{PaperID: p.ID, Provider: "library", PaperMetadata: PaperMetadata{
				Title: p.Title, Abstract: p.Abstract, Authors: p.Authors, Year: p.Year,
				Arxiv: p.Arxiv, DOI: p.DOI, URL: p.URL, Tags: p.Tags,
			}}
		} else {
			candidate.Provider = "graph"
			switch {
			case arxivPattern.MatchString(normalizeArxiv(evidence.Reference)):
				id := normalizeArxiv(evidence.Reference)
				candidate.Arxiv, candidate.Title, candidate.URL = id, "arXiv:"+id, "https://arxiv.org/abs/"+id
			case doiPattern.MatchString(key):
				candidate.DOI, candidate.Title, candidate.URL = key, key, "https://doi.org/"+key
			default:
				return
			}
		}
		key = candidate.Key()
		if existing, ok := candidates[key]; ok {
			if !paperContainsCitation(existing.GraphEvidence, evidence) {
				existing.GraphEvidence = append(existing.GraphEvidence, evidence)
				candidates[key] = existing
			}
		} else {
			candidate.GraphEvidence = []DiscoveryCitation{evidence}
			candidates[key] = candidate
		}
	}
	for _, core := range context.Library {
		if !paperContains(core.CoreProjectIDs, project) {
			continue
		}
		for _, ref := range core.References {
			add(ref, DiscoveryCitation{PaperID: core.ID, PaperTitle: core.Title, Kind: "cites", Reference: ref})
		}
		for _, rel := range relations {
			if rel.Kind != "cites" && rel.Kind != "extends" && rel.Kind != "related" {
				continue
			}
			first, second := rel.Source, rel.Target
			if second == core.ID {
				first, second = second, first
			}
			if first == core.ID {
				add(strings.TrimPrefix(second, "reference:"), DiscoveryCitation{
					PaperID: core.ID, PaperTitle: core.Title, Kind: rel.Kind, RelationID: rel.ID,
					Reference: strings.TrimPrefix(second, "reference:"),
				})
			}
		}
	}
	context.Graph = make([]DiscoveryCandidate, 0, len(candidates))
	for _, candidate := range candidates {
		sort.Slice(candidate.GraphEvidence, func(i, j int) bool {
			a, b := candidate.GraphEvidence[i], candidate.GraphEvidence[j]
			if a.PaperID != b.PaperID {
				return a.PaperID < b.PaperID
			}
			if a.RelationID != b.RelationID {
				return a.RelationID < b.RelationID
			}
			return a.Reference < b.Reference
		})
		context.Graph = append(context.Graph, candidate)
	}
	sort.Slice(context.Graph, func(i, j int) bool { return context.Graph[i].Key() < context.Graph[j].Key() })
	return context, nil
}

func discoveryReferenceKey(raw string) string {
	key := paperRefKey(raw)
	if arxivPattern.MatchString(key) {
		return ArxivWorkID(key)
	}
	return key
}

func paperContainsCitation(citations []DiscoveryCitation, want DiscoveryCitation) bool {
	for _, citation := range citations {
		if citation == want {
			return true
		}
	}
	return false
}

// DiscoveryImport reports a recoverable source download failure alongside a
// successfully registered library item.
type DiscoveryImport struct {
	Paper
	Warning string `json:"import_warning,omitempty"`
}

// ImportDiscoveryCandidate keeps existing papers intact. A new arXiv
// recommendation can attach the exact original PDF or retain its source link
// when the upstream file is unavailable.
func (s *Service) ImportDiscoveryCandidate(ctx context.Context, project string, candidate DiscoveryCandidate, fetchPDF bool) (DiscoveryImport, error) {
	if project != "" && !s.HasActiveProject(project) {
		return DiscoveryImport{}, fmt.Errorf("科研项目不存在或已归档")
	}
	if candidate.PaperID != "" {
		for range 3 {
			paper, ok := s.papers.Snapshot(candidate.PaperID)
			if !ok {
				return DiscoveryImport{}, fmt.Errorf("图谱引用的馆藏论文已移除")
			}
			if project == "" || paperContains(paper.ProjectIDs, project) {
				return DiscoveryImport{Paper: paper}, nil
			}
			paper.ProjectIDs = append(paper.ProjectIDs, project)
			updated, err := s.papers.update(paper.ID, paper.Revision, paper.PaperMetadata)
			if !errors.Is(err, errPaperConflict) {
				return DiscoveryImport{Paper: updated}, err
			}
		}
		return DiscoveryImport{}, errPaperConflict
	}
	metadata := PaperMetadata{
		Title: candidate.Title, Authors: candidate.Authors, Year: candidate.Year,
		DOI: candidate.DOI, Arxiv: candidate.Arxiv, URL: candidate.URL, Abstract: candidate.Abstract,
		Tags: append(slices.Clone(candidate.Tags), "recommendation"),
	}
	if project != "" {
		metadata.ProjectIDs = []string{project}
	}

	var temp, digest, warning string
	if fetchPDF && arxivPattern.MatchString(metadata.Arxiv) && !s.papers.hasDiscoveryPDF(metadata) {
		var err error
		temp, digest, err = s.papers.downloadPDF(ctx, "https://arxiv.org/pdf/"+metadata.Arxiv)
		if err != nil {
			if !errors.Is(err, errRemotePDF) && !errors.Is(err, errInvalidPaper) {
				return DiscoveryImport{}, err
			}
			warning = "arXiv PDF 暂不可用，已保存来源链接"
		} else {
			defer os.Remove(temp)
		}
	}
	if err := ctx.Err(); err != nil {
		return DiscoveryImport{}, err
	}
	if project != "" && !s.HasActiveProject(project) {
		return DiscoveryImport{}, fmt.Errorf("科研项目已关闭，请重新选择")
	}
	paper, _, err := s.papers.create(metadata, temp, digest)
	if temp != "" && errors.Is(err, errPaperExists) {
		// A different version may have been registered concurrently. Preserve the
		// stored original and only add the selected project link.
		paper, _, err = s.papers.create(metadata, "", "")
		if err == nil {
			warning = "馆藏中已有此文献，已保留原 PDF"
		}
	}
	return DiscoveryImport{Paper: paper, Warning: warning}, err
}

func (s *PaperLibrary) hasDiscoveryPDF(metadata PaperMetadata) bool {
	s.mu.RLock()
	defer s.mu.RUnlock()
	for _, paper := range s.records {
		if paper.HasPDF && samePaper(Paper{PaperMetadata: metadata}, paper) {
			return true
		}
	}
	return false
}
