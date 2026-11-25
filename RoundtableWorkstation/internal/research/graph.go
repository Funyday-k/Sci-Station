package research

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strconv"
)

type graphNode struct {
	ID    string `json:"id"`
	Label string `json:"label"`
	Kind  string `json:"kind"`
}

type graphOccurrence struct {
	ID             string `json:"id"`
	Source         string `json:"source"`
	Ordinal        int    `json:"ordinal"`
	Quote          string `json:"quote,omitempty"`
	Line           int    `json:"line,omitempty"`
	EndLine        int    `json:"endLine,omitempty"`
	Column         int    `json:"column,omitempty"`
	SourceRevision int    `json:"sourceRevision,omitempty"`
	Page           int    `json:"page,omitempty"`
	SourceHash     string `json:"sourceHash,omitempty"`
	MeetingID      string `json:"meetingId,omitempty"`
	TurnID         string `json:"turnId,omitempty"`
	Status         string `json:"status,omitempty"`
	Start          *int   `json:"start,omitempty"`
	End            *int   `json:"end,omitempty"`
	OCR            bool   `json:"ocr,omitempty"`
	AnnotationID   string `json:"annotationId,omitempty"`
}

type graphEdge struct {
	ID          string            `json:"id,omitempty"`
	Revision    int               `json:"revision,omitempty"`
	Label       string            `json:"label,omitempty"`
	Source      string            `json:"source"`
	Target      string            `json:"target"`
	Kind        string            `json:"kind"`
	Occurrences []graphOccurrence `json:"occurrences,omitempty"`
}

type graphResult struct {
	Nodes []graphNode    `json:"nodes"`
	Edges []graphEdge    `json:"edges"`
	Hops  map[string]int `json:"hops,omitempty"`
	Path  *graphPath     `json:"path,omitempty"`
}

type graphEdgeKey struct{ source, target, kind string }
type graphEdges map[graphEdgeKey]*graphEdge

func (edges graphEdges) link(from, to, kind string) *graphEdge {
	key := graphEdgeKey{from, to, kind}
	if edge := edges[key]; edge != nil {
		return edge
	}
	edge := &graphEdge{Source: from, Target: to, Kind: kind}
	edges[key] = edge
	return edge
}

// An occurrence has an identity within an owning edge, independent of the
// load time and available offline. Revisions are checked separately at open.
func (e *graphEdge) record(occurrence graphOccurrence) {
	h := sha256.New()
	for _, field := range []string{e.Source, e.Target, e.Kind, occurrence.Source,
		strconv.Itoa(occurrence.Ordinal), strconv.Itoa(occurrence.Line),
		strconv.Itoa(occurrence.Column), strconv.Itoa(occurrence.EndLine),
		strconv.Itoa(occurrence.Page), occurrence.SourceHash, occurrence.Quote, occurrence.AnnotationID, strconv.FormatBool(occurrence.OCR),
		occurrence.MeetingID, occurrence.TurnID} {
		_, _ = h.Write([]byte(strconv.Itoa(len(field)) + ":" + field))
	}
	if occurrence.Start != nil && occurrence.End != nil {
		_, _ = h.Write([]byte(":" + strconv.Itoa(*occurrence.Start) + ":" + strconv.Itoa(*occurrence.End)))
	}
	occurrence.ID = hex.EncodeToString(h.Sum(nil))
	e.Occurrences = append(e.Occurrences, occurrence)
}

func (s *Service) graph(w http.ResponseWriter, r *http.Request) {
	query, err := parseGraphQuery(r.URL.Query())
	if err != nil {
		jsonFail(w, http.StatusBadRequest, err.Error())
		return
	}
	s.mu.RLock()
	d, ok := s.loadProject(w, r.PathValue("project"))
	var tasks map[string]Task
	if ok {
		tasks = s.visibleTasksLocked(d.Project.ID)
	}
	s.mu.RUnlock()
	if !ok {
		return
	}
	nodes, edges := s.derivedGraph(r.Context(), d, tasks)
	if r.Context().Err() != nil {
		return
	}
	// Manual relations are source records. Keep their IDs available for
	// revision-checked deletion even when an endpoint has been removed.
	for _, rel := range d.Relations {
		for _, id := range []string{rel.Source, rel.Target} {
			if _, ok := nodes[id]; !ok {
				nodes[id] = graphNode{id, id, "missing"}
			}
		}
		edge := edges.link(rel.Source, rel.Target, rel.Kind)
		edge.ID, edge.Revision, edge.Label = rel.ID, rel.Revision, rel.Label
	}
	result, err := query.run(r.Context(), nodes, sortedGraphEdges(edges))
	if r.Context().Err() != nil {
		return
	}
	if err != nil {
		jsonFail(w, http.StatusNotFound, err.Error())
		return
	}
	w.Header().Set("Cache-Control", "no-store")
	jsonReply(w, http.StatusOK, result)
}

func sortedGraphEdges(edges graphEdges) []graphEdge {
	out := make([]graphEdge, 0, len(edges))
	for _, edge := range edges {
		out = append(out, *edge)
	}
	sort.Slice(out, func(i, j int) bool {
		a, b := out[i], out[j]
		if a.Source != b.Source {
			return a.Source < b.Source
		}
		if a.Target != b.Target {
			return a.Target < b.Target
		}
		return a.Kind < b.Kind
	})
	return out
}

// This projection is rebuilt from one published project snapshot and one
// library snapshot. No derived files need to be repaired or loaded on restart.
func (s *Service) derivedGraph(ctx context.Context, d projectData, tasks map[string]Task) (map[string]graphNode, graphEdges) {
	nodes := map[string]graphNode{}
	edges := graphEdges{}
	papers := map[string]Paper{}
	allPapers := s.papers.all()
	for _, paper := range allPapers {
		papers[paper.ID] = paper
	}
	library := buildPaperGraph(ctx, filterPapers(allPapers, d.Project.ID, "", ""))
	for _, p := range library.Nodes {
		nodes[p.ID] = graphNode{p.ID, p.Title, p.Kind}
	}
	for _, e := range library.Edges {
		edges.link(e.Source, e.Target, e.Kind).Occurrences = e.Occurrences
	}
	addWikiGraph(ctx, d, nodes, edges)

	// An explicit note/task link can point to one shared paper outside this
	// project. Its own outgoing edges remain outside this project.
	addPaper := func(from, id, kind string) *graphEdge {
		if paper, known := papers[id]; known {
			nodes[id] = graphNode{id, paper.Title, "paper"}
		} else {
			nodes[id] = graphNode{id, id, "missing"}
		}
		return edges.link(from, id, kind)
	}
	pdfStatus := map[string]bool{}
	recordEvidence := func(id string, revision int, all []Evidence) {
		for i, evidence := range all {
			occurrence := graphOccurrence{Source: "evidence", Ordinal: i + 1, Page: evidence.Page,
				SourceHash: evidence.SourceHash, Quote: evidence.Quote, SourceRevision: revision,
				MeetingID: evidence.MeetingID, TurnID: evidence.TurnID,
				Start: evidence.SelectionStart, End: evidence.SelectionEnd, OCR: evidence.OCR, AnnotationID: evidence.AnnotationID}
			if evidence.PaperID == "" {
				if evidence.MeetingID != "" {
					occurrence.Source = "meeting"
					meetingID := "meeting:" + evidence.MeetingID
					nodes[meetingID] = graphNode{meetingID, evidence.MeetingID, "meeting"}
					edges.link(id, meetingID, "evidence").record(occurrence)
				}
				continue
			}
			paper := papers[evidence.PaperID]
			available, checked := pdfStatus[paper.ID]
			if !checked && paper.HasPDF {
				info, err := os.Stat(filepath.Join(s.papers.dir, "pdf", paper.ID+".pdf"))
				available = err == nil && info.Mode().IsRegular()
				pdfStatus[paper.ID] = available
			}
			switch {
			case paper.ID == "" || evidence.Page > 0 && !available:
				occurrence.Status = "missing"
			case evidence.SourceHash != "" && evidence.SourceHash != paper.FileSHA256:
				occurrence.Status = "changed"
			case evidence.SourceHash != "":
				occurrence.Status = "matched"
			default:
				occurrence.Status = "unversioned"
			}
			addPaper(id, evidence.PaperID, "evidence").record(occurrence)
		}
	}
	for _, note := range d.Notes {
		if ctx.Err() != nil {
			return nodes, edges
		}
		if nodes[note.ID].Kind != "note" {
			continue
		}
		if note.PaperID != "" {
			addPaper(note.ID, note.PaperID, "paper")
		}
		recordEvidence(note.ID, note.Revision, note.Evidence)
	}
	for _, task := range tasks {
		nodes[task.ID] = graphNode{task.ID, task.Title, "task"}
		for _, id := range task.RelatedPaperIDs {
			addPaper(task.ID, id, "reading")
		}
		recordEvidence(task.ID, task.Revision, task.Evidence)
	}
	return nodes, edges
}

func addWikiGraph(ctx context.Context, d projectData, nodes map[string]graphNode, edges graphEdges) {
	index := wikiLinkIndex(d)
	for _, note := range d.Notes {
		if !note.Archived {
			nodes[note.ID] = graphNode{note.ID, wikiPath(note), "note"}
		}
	}
	for _, note := range d.Notes {
		if ctx.Err() != nil {
			return
		}
		if note.Archived {
			continue
		}
		for i, link := range wikiLinks(note.Body) {
			if target := index.resolve(link.Target); target != "" {
				edges.link(note.ID, target, "wikilink").record(graphOccurrence{
					Source: "wikilink", Ordinal: i + 1, Line: link.Line,
					Column: link.Column, Quote: link.Text, SourceRevision: note.Revision,
				})
			}
		}
	}
}
