package research

import (
	"bytes"
	"context"
	"net/url"
	"os"
	"path/filepath"
	"reflect"
	"strconv"
	"testing"
)

func findGraphEdge(t *testing.T, edges []graphEdge, source, target, kind string) graphEdge {
	t.Helper()
	for _, edge := range edges {
		if edge.Source == source && edge.Target == target && edge.Kind == kind {
			return edge
		}
	}
	t.Fatalf("missing %s edge %s → %s in %v", kind, source, target, edges)
	return graphEdge{}
}

func TestProjectGraphKeepsOccurrencesAndRebuildsOffline(t *testing.T) {
	dir := t.TempDir()
	s := newResearch(t, dir)
	a := createResearchProject(t, s, "One")
	b := createResearchProject(t, s, "Two")
	path := func(p Project) string { return "/projects/" + p.ID }
	createPaper := func(metadata PaperMetadata) Paper {
		t.Helper()
		return decodeResearch[Paper](t, callResearch(t, s, "POST", "/papers", metadata, 201))
	}
	note := func(p Project, title, body string) Note {
		t.Helper()
		return decodeResearch[Note](t, callResearch(t, s, "POST", path(p)+"/notes",
			map[string]string{"title": title, "body": body}, 201))
	}
	upstream := createPaper(PaperMetadata{Title: "Source", ProjectIDs: []string{a.ID, b.ID},
		References: []string{"10.1000/work", "10.1000/work", "arXiv:2404.10066v8"},
		Notes:      "# Reading\n\n## References\n1. Target doi:10.1000/work\n   continuation\n2. doi:10.1000/work\n## Appendix\n10.9999/ignore"})
	target := createPaper(PaperMetadata{Title: "Target", DOI: "10.1000/work", Arxiv: "2404.10066v1", ProjectIDs: []string{a.ID}})
	n := note(a, "Summary", "前文 [[Methods#Setup|method]]\n[[Methods]]")
	m := note(a, "Methods", "We tested it.")
	note(b, "Methods", "A different note.")

	graphURL := path(a) + "/graph"
	old := callResearch(t, s, "GET", graphURL, nil, 200)
	g := decodeResearch[graphResult](t, old)
	citation := findGraphEdge(t, g.Edges, upstream.ID, target.ID, "cites")
	if len(citation.Occurrences) != 5 {
		t.Fatalf("semantic edge lost individual citations: %+v", citation)
	}
	if first := citation.Occurrences[0]; first.Source != "paper-note" || first.Line != 4 || first.EndLine != 5 ||
		first.Quote != "Target doi:10.1000/work continuation" || first.SourceRevision != upstream.Revision {
		t.Fatalf("could not locate first source: %+v", first)
	}
	if a, b := citation.Occurrences[2], citation.Occurrences[3]; a.ID == b.ID || a.Quote != b.Quote || a.Ordinal != 1 || b.Ordinal != 2 {
		t.Fatalf("identical reference strings must preserve distinct occurrences: %+v and %+v", a, b)
	}
	wikilink := findGraphEdge(t, g.Edges, n.ID, m.ID, "wikilink")
	if len(wikilink.Occurrences) != 2 || wikilink.Occurrences[0].Column != 4 || wikilink.Occurrences[0].Line != 1 ||
		wikilink.Occurrences[1].Line != 2 || wikilink.Occurrences[1].Quote != "[[Methods]]" {
		t.Fatalf("could not locate both wikilinks: %+v", wikilink)
	}
	otherResult := decodeResearch[graphResult](t, callResearch(t, s, "GET", path(b)+"/graph", nil, 200))
	for _, node := range otherResult.Nodes {
		if node.ID == m.ID || node.ID == n.ID || node.ID == target.ID {
			t.Fatalf("unrelated project data leaked: %+v", node)
		}
	}
	if len(otherResult.Nodes) < 3 || len(otherResult.Edges) != 2 {
		t.Fatalf("expected independent project notes and unresolved shared-paper references: %+v", otherResult)
	}

	// Graph reads ignore discarded derived files. A restart and refresh
	// reconstruct identical occurrence IDs from the same source bytes.
	projectFile := s.recordPath(a.ID)
	paperFile := filepath.Join(s.papers.dir, "records", upstream.ID+".json")
	sourceBefore, err := os.ReadFile(projectFile)
	if err != nil {
		t.Fatal(err)
	}
	referenceBefore, err := os.ReadFile(paperFile)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "graph.sqlite"), []byte("interrupted rebuild"), 0600); err != nil {
		t.Fatal(err)
	}
	s = newResearch(t, dir)
	if got := callResearch(t, s, "GET", graphURL, nil, 200); !bytes.Equal(got, old) {
		t.Fatalf("graph changed after restart and derived-state damage\n%s\n%s", got, old)
	}
	for file, before := range map[string][]byte{projectFile: sourceBefore, paperFile: referenceBefore} {
		if after, err := os.ReadFile(file); err != nil || !bytes.Equal(after, before) {
			t.Fatalf("graph rebuild wrote to %s, error %v", file, err)
		}
	}

	callResearch(t, s, "PATCH", "/papers/"+upstream.ID, map[string]any{
		"revision": upstream.Revision + 1, "references": []string{}, "notes": "",
	}, 409)
	if after := callResearch(t, s, "GET", graphURL, nil, 200); !bytes.Equal(old, after) {
		t.Fatal("invalid paper revision changed graph evidence")
	}
	callResearch(t, s, "PATCH", "/papers/"+upstream.ID, map[string]any{
		"revision": upstream.Revision, "references": []string{}, "notes": "",
	}, 200)
	callResearch(t, s, "DELETE", path(a)+"/notes/"+m.ID+"?revision="+strconv.Itoa(m.Revision), nil, 204)
	cleared := decodeResearch[graphResult](t, callResearch(t, s, "GET", graphURL, nil, 200))
	if len(cleared.Edges) != 0 {
		t.Fatalf("deleted sources remain in graph: %+v", cleared.Edges)
	}
}

func TestProjectGraphPathDepthKindsAndDeletedRelations(t *testing.T) {
	s := newResearch(t, t.TempDir())
	project := createResearchProject(t, s, "Network")
	path := "/projects/" + project.ID
	note := func(title, body string) Note {
		return decodeResearch[Note](t, callResearch(t, s, "POST", path+"/notes",
			map[string]string{"title": title, "body": body}, 201))
	}
	a := note("A", "[[B]]")
	b := note("B", "[[C]]")
	c := note("C", "")
	d := decodeResearch[Task](t, callResearch(t, s, "POST", path+"/tasks", map[string]string{"title": "D"}, 201))
	relation := decodeResearch[GraphRelation](t, callResearch(t, s, "POST", path+"/graph/relations",
		map[string]string{"source": c.ID, "target": d.ID, "kind": "related"}, 201))
	get := func(query url.Values) graphResult {
		return decodeResearch[graphResult](t, callResearch(t, s, "GET", path+"/graph?"+query.Encode(), nil, 200))
	}
	nearby := get(url.Values{"focus": {a.ID}, "depth": {"1"}})
	if len(nearby.Nodes) != 2 || len(nearby.Edges) != 1 || nearby.Hops[b.ID] != 1 {
		t.Fatalf("wrong depth-1 neighbors: %+v", nearby)
	}
	result := get(url.Values{"focus": {d.ID}, "target": {a.ID}, "depth": {"3"}})
	if result.Path == nil || !result.Path.Found || !reflect.DeepEqual(result.Path.Nodes, []string{d.ID, c.ID, b.ID, a.ID}) ||
		len(result.Edges) != 3 || result.Edges[0].ID != relation.ID || result.Edges[1].Source != b.ID {
		t.Fatalf("wrong shortest undirected path or original edge direction: %+v", result)
	}
	for _, query := range []url.Values{
		{"focus": {d.ID}, "target": {a.ID}, "depth": {"2"}},
		{"focus": {d.ID}, "target": {a.ID}, "kind": {"wikilink"}},
		{"focus": {d.ID}, "target": {a.ID}, "nodeKind": {"paper"}},
	} {
		if g := get(query); g.Path == nil || g.Path.Found || len(g.Edges) != 0 {
			t.Fatalf("unexpected path through filters %v: %+v", query, g)
		}
	}
	if g := get(url.Values{"nodeKind": {"task"}}); len(g.Nodes) != 1 || g.Nodes[0].ID != d.ID || len(g.Edges) != 0 {
		t.Fatalf("wrong node type filter: %+v", g)
	}
	callResearch(t, s, "GET", path+"/graph?focus=nope", nil, 404)
	callResearch(t, s, "GET", path+"/graph?depth=-1", nil, 400)
	callResearch(t, s, "GET", path+"/graph?kind=unknown", nil, 400)
	callResearch(t, s, "DELETE", path+"/graph/relations/"+relation.ID+"?revision=2", nil, 409)
	callResearch(t, s, "DELETE", path+"/graph/relations/"+relation.ID+"?revision=1", nil, 204)
	if g := get(url.Values{"focus": {d.ID}, "target": {a.ID}}); g.Path == nil || g.Path.Found {
		t.Fatalf("deleted manual relation still traversable: %+v", g)
	}
}

func TestProjectGraphCancelledTraversal(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	query := graphQuery{focus: "a", target: "b", depth: 1}
	_, err := query.run(ctx, map[string]graphNode{"a": {ID: "a"}, "b": {ID: "b"}}, []graphEdge{{Source: "a", Target: "b"}})
	if err != context.Canceled {
		t.Fatalf("traversal ignored cancellation: %v", err)
	}
}

func TestPaperNoteReferenceFenceAndLineNumbers(t *testing.T) {
	notes := "```markdown\n# References\n- code\n```\n## References ##\n[12]. DOI:10.1234/test\n\n- arXiv:hep-ph/0102030v2\n### More\n- not a citation"
	got := paperNoteReferences(notes)
	if len(got) != 2 || got[0].Line != 6 || got[1].Line != 8 ||
		citationKey(got[0].Quote) != "10.1234/test" || citationKey(got[1].Quote) != "hep-ph/0102030" {
		t.Fatalf("did not preserve source positions or normalize identifiers: %+v", got)
	}
}

func TestProjectGraphEvidenceAnchorsAndMissingPDF(t *testing.T) {
	s := newResearch(t, t.TempDir())
	project := createResearchProject(t, s, "Evidence")
	fixture, err := os.ReadFile(readerFixture(t))
	if err != nil {
		t.Fatal(err)
	}
	paper := uploadTestPDF(t, s.papers, string(fixture), `{"title":"Local source"}`)
	pdf, err := s.papers.PDFPath(paper.ID)
	if err != nil {
		t.Fatal(err)
	}
	pdfBefore, err := os.ReadFile(pdf)
	if err != nil {
		t.Fatal(err)
	}
	path := "/projects/" + project.ID
	start, end := 0, len("Evidence sample")
	note := decodeResearch[Note](t, callResearch(t, s, "POST", path+"/notes", map[string]any{
		"title": "Reviewed passage", "evidence": []Evidence{
			{PaperID: paper.ID, Page: 1, Quote: "Evidence sample", SourceHash: paper.FileSHA256, MeetingID: "discussion", TurnID: "round-1-analyst", SelectionStart: &start, SelectionEnd: &end},
			{PaperID: paper.ID, Page: 2, Quote: "also considered"},
			{MeetingID: "discussion", TurnID: "turn-5", Quote: "another discussion"},
		},
	}, 201))
	read := func() graphResult {
		return decodeResearch[graphResult](t, callResearch(t, s, "GET", path+"/graph", nil, 200))
	}
	g := read()
	edge := findGraphEdge(t, g.Edges, note.ID, paper.ID, "evidence")
	if len(edge.Occurrences) != 2 {
		t.Fatalf("lost PDF evidence: %+v", edge)
	}
	for i, a := range edge.Occurrences {
		if a.Status != "matched" || a.Page != i+1 || a.SourceHash != paper.FileSHA256 || a.SourceRevision != note.Revision {
			t.Fatalf("invalid PDF locator: %+v", a)
		}
	}
	if first := edge.Occurrences[0]; first.Start == nil || *first.Start != 0 || first.End == nil || *first.End != end ||
		first.TurnID != "round-1-analyst" {
		t.Fatalf("lost exact PDF selection: %+v", first)
	}
	meeting := findGraphEdge(t, g.Edges, note.ID, "meeting:discussion", "evidence")
	if len(meeting.Occurrences) != 1 || meeting.Occurrences[0].TurnID != "turn-5" {
		t.Fatalf("lost meeting source anchor: %+v", meeting)
	}
	if after, err := os.ReadFile(pdf); err != nil || !bytes.Equal(pdfBefore, after) {
		t.Fatal("graph read modified PDF bytes", err)
	}
	if err := os.Remove(pdf); err != nil {
		t.Fatal(err)
	}
	missing := findGraphEdge(t, read().Edges, note.ID, paper.ID, "evidence")
	if missing.Occurrences[0].Status != "missing" || missing.Occurrences[0].Quote != edge.Occurrences[0].Quote ||
		missing.Occurrences[0].ID != edge.Occurrences[0].ID {
		t.Fatalf("invalid missing-file recovery: %+v", missing)
	}
}

func TestProjectGraphUsesSharedWikiResolverAndTaskProjection(t *testing.T) {
	s := newResearch(t, t.TempDir())
	primary := createResearchProject(t, s, "Primary")
	shared := createResearchProject(t, s, "Shared")
	isolated := createResearchProject(t, s, "Isolated")
	path := "/projects/" + primary.ID
	projectGraph := func(project Project) graphResult {
		return decodeResearch[graphResult](t, callResearch(t, s, "GET", "/projects/"+project.ID+"/graph", nil, 200))
	}
	createNote := func(input map[string]any) Note {
		return decodeResearch[Note](t, callResearch(t, s, "POST", path+"/notes", input, 201))
	}
	target := createNote(map[string]any{"title": "Reference", "namespace": "concepts", "aliases": []string{"Ref"}})
	method := createNote(map[string]any{"title": "Reference", "namespace": "methods"})
	source := createNote(map[string]any{"title": "Claim", "body": "See [[concept:Ref]] and [[methods/Reference]].\n`[[concept:Ref]]`\n[[Reference]]"})
	first := decodeResearch[Paper](t, callResearch(t, s, "POST", "/papers", map[string]string{"title": "First"}, 201))
	second := decodeResearch[Paper](t, callResearch(t, s, "POST", "/papers", map[string]string{"title": "Second"}, 201))
	task := decodeResearch[Task](t, callResearch(t, s, "POST", path+"/tasks", map[string]any{
		"title": "Read both", "kind": "reading", "projectIds": []string{primary.ID, shared.ID},
		"relatedPaperIds": []string{first.ID, second.ID},
	}, 201))
	g := projectGraph(primary)
	link := findGraphEdge(t, g.Edges, source.ID, target.ID, "wikilink")
	if len(link.Occurrences) != 1 || link.Occurrences[0].Line != 1 || link.Occurrences[0].Column != 5 {
		t.Fatalf("graph and wiki resolver disagree: %+v", link)
	}
	findGraphEdge(t, g.Edges, source.ID, method.ID, "wikilink")
	for _, project := range []Project{primary, shared} {
		g = projectGraph(project)
		findGraphEdge(t, g.Edges, task.ID, first.ID, "reading")
		findGraphEdge(t, g.Edges, task.ID, second.ID, "reading")
	}
	if g = projectGraph(isolated); len(g.Nodes) != 0 || len(g.Edges) != 0 {
		t.Fatalf("task links leaked to another project's graph: %+v", g)
	}
	callResearch(t, s, "DELETE", path+"/notes/"+target.ID+"?revision=1", nil, 204)
	for _, node := range projectGraph(primary).Nodes {
		if node.ID == target.ID {
			t.Fatalf("archived note still in project graph: %+v", node)
		}
	}
	callResearch(t, s, "POST", path+"/notes/"+target.ID+"/restore", map[string]int{"revision": 2}, 200)
	restored := findGraphEdge(t, projectGraph(primary).Edges, source.ID, target.ID, "wikilink")
	if restored.Occurrences[0].ID != link.Occurrences[0].ID {
		t.Fatalf("restoring the same target changed the linked occurrence: %+v", restored)
	}
}
