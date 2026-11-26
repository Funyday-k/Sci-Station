package research

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"slices"
	"testing"
)

func TestWikiHistoricalPaperSourceSurvivesUnlinkAndDelete(t *testing.T) {
	dir := t.TempDir()
	s := newResearch(t, dir)
	a := createResearchProject(t, s, "Primary fixture")
	b := createResearchProject(t, s, "Shared fixture")
	c := createResearchProject(t, s, "Archived fixture")
	metadata, err := json.Marshal(PaperMetadata{
		Title: "Original fixture paper", Citekey: "fixture-paper", ProjectIDs: []string{a.ID, b.ID},
		CoreProjectIDs: []string{a.ID, b.ID}, ProjectLinks: map[string]PaperProjectLink{
			a.ID: {IsPinned: true}, b.ID: {FolderPath: "Retain this arrangement"},
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	pdf, err := os.ReadFile(readerFixture(t))
	if err != nil {
		t.Fatal(err)
	}
	paper := uploadTestPDF(t, s.papers, string(pdf), string(metadata))
	paperPath := "/papers/" + paper.ID
	other := decodeResearch[Paper](t, callResearch(t, s, "POST", "/papers", map[string]any{"title": "Replacement fixture", "skip_metadata_lookup": true}, 201))
	pages := "/projects/" + a.ID + "/notes"
	note := decodeResearch[Note](t, callResearch(t, s, "POST", pages+"/paper-template", map[string]any{"paperId": paper.ID, "revision": paper.Revision}, 201))
	notePath := pages + "/" + note.ID
	assertSource := func(path, status string) wikiNoteView {
		t.Helper()
		view := decodeResearch[wikiNoteView](t, callResearch(t, s, "GET", path, nil, 200))
		if view.PaperID != paper.ID || view.PaperStatus != status {
			t.Fatalf("got source %s (%s), want %s (%s)", view.PaperID, view.PaperStatus, paper.ID, status)
		}
		return view
	}
	assertSource(notePath, "available")

	linked := decodeResearch[Paper](t, callResearch(t, s, "PATCH", paperPath, map[string]any{
		"revision": paper.Revision, "project_ids": []string{b.ID}, "core_project_ids": []string{b.ID},
	}, 200))
	if !slices.Equal(linked.ProjectIDs, []string{b.ID}) || !slices.Equal(linked.CoreProjectIDs, []string{b.ID}) ||
		len(linked.ProjectLinks) != 1 || linked.ProjectLinks[b.ID].FolderPath != "Retain this arrangement" {
		t.Fatalf("unlink changed another project's reading arrangement: %#v", linked)
	}
	if got := callResearch(t, s, "GET", paperPath+"/pdf", nil, 200); !bytes.Equal(got, pdf) {
		t.Fatal("project unlink altered the shared PDF")
	}
	assertSource(notePath, "outside_project")

	archivedPages := "/projects/" + c.ID + "/notes"
	archived := decodeResearch[Note](t, callResearch(t, s, "POST", archivedPages, map[string]any{
		"title": "Archived evidence-only fixture", "evidence": []Evidence{{PaperID: paper.ID, Quote: "Fixture quotation"}},
	}, 201))
	callResearch(t, s, "DELETE", archivedPages+"/"+archived.ID+"?revision=1", nil, 204)
	callResearch(t, s, "DELETE", "/projects/"+c.ID+"?revision=1", nil, 204)
	callResearch(t, s, "POST", "/tasks", map[string]any{"title": "Read fixture", "relatedPaperIds": []string{paper.ID}}, 201)
	removal := paperPath + "/removal"
	preview := func() paperRemovalImpact {
		t.Helper()
		return decodeResearch[paperRemovalImpact](t, callResearch(t, s, "GET", removal, nil, 200))
	}
	confirm := func(impact paperRemovalImpact, want int) {
		t.Helper()
		callResearch(t, s, "DELETE", fmt.Sprintf("%s?revision=%d&confirmation=%s", removal, impact.Revision, impact.Confirmation), nil, want)
	}
	impact := preview()
	if impact.Revision != linked.Revision || !impact.HasPDF || impact.RelatedTasks != 1 ||
		len(impact.Projects) != 3 || !slices.Contains(impact.Projects, paperRemovalProject{ID: a.ID, Name: a.Name, WikiPages: 1}) ||
		!slices.Contains(impact.Projects, paperRemovalProject{ID: b.ID, Name: b.Name, Member: true}) ||
		!slices.Contains(impact.Projects, paperRemovalProject{ID: c.ID, Name: c.Name, Archived: true, ArchivedWikiPages: 1}) {
		t.Fatalf("incorrect shared deletion impact: %#v", impact)
	}
	regular := decodeResearch[Note](t, callResearch(t, s, "POST", pages, map[string]any{"title": "New fixture note", "paperId": paper.ID}, 201))
	confirm(impact, 409)
	impact = preview()
	callResearch(t, s, "PATCH", paperPath, map[string]any{"revision": impact.Revision, "tags": []string{"revised"}}, 200)
	confirm(impact, 409)
	confirm(preview(), 204)
	callResearch(t, s, "GET", paperPath, nil, 404)
	assertSource(notePath, "missing")

	s = newResearch(t, dir)
	assertSource(notePath, "missing")
	changed := decodeResearch[Note](t, callResearch(t, s, "PATCH", notePath, map[string]any{
		"revision": note.Revision, "paperId": note.PaperID, "title": note.Title, "namespace": note.Namespace,
		"aliases": note.Aliases, "tags": note.Tags, "body": note.Body + "\nReviewed after deletion.",
	}, 200))
	callResearch(t, s, "PATCH", notePath, map[string]any{"revision": changed.Revision, "paperId": ""}, 400)
	callResearch(t, s, "PATCH", notePath, map[string]any{"revision": changed.Revision, "paperId": other.ID}, 400)
	callResearch(t, s, "POST", pages, map[string]any{"title": "Invalid new link", "paperId": paper.ID}, 409)
	regularPath := pages + "/" + regular.ID
	callResearch(t, s, "PATCH", regularPath, map[string]any{"revision": regular.Revision, "paperId": makeID()}, 409)
	callResearch(t, s, "PATCH", regularPath, map[string]any{"revision": regular.Revision, "paperId": other.ID}, 200)
	callResearch(t, s, "PATCH", regularPath, map[string]any{"revision": regular.Revision + 1, "paperId": ""}, 200)

	s = newResearch(t, dir)
	reopened := assertSource(notePath, "missing")
	if reopened.Revision != changed.Revision || reopened.Body != note.Body+"\nReviewed after deletion." {
		t.Fatalf("source frontmatter or body changed after reopen: %#v", reopened)
	}
}
