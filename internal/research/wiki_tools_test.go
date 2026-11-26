package research

import (
	"net/http"
	"os"
	"path/filepath"
	"reflect"
	"slices"
	"strings"
	"testing"
)

func TestWikiExplicitFoldersSurviveRestartAndStayInProject(t *testing.T) {
	dir := t.TempDir()
	s := newResearch(t, dir)
	first := createResearchProject(t, s, "Folders")
	second := createResearchProject(t, s, "Other folders")
	wiki := func(p Project) string { return "/projects/" + p.ID + "/wiki/folders" }
	callResearch(t, s, "POST", wiki(first), map[string]string{"path": "methods/statistics"}, 201)
	callResearch(t, s, "POST", wiki(first), map[string]string{"path": "Methods/Statistics"}, 409)
	callResearch(t, s, "POST", wiki(first), map[string]string{"path": "methods/../escape"}, 400)
	s = newResearch(t, dir)
	folders := decodeResearch[[]string](t, callResearch(t, s, "GET", wiki(first), nil, 200))
	if !slices.Equal(folders, []string{"methods", "methods/statistics"}) {
		t.Fatalf("did not restore empty folders: %v", folders)
	}
	if other := decodeResearch[[]string](t, callResearch(t, s, "GET", wiki(second), nil, 200)); len(other) != 0 {
		t.Fatalf("folders leaked to another project: %v", other)
	}
	pages := "/projects/" + first.ID + "/notes"
	note := decodeResearch[Note](t, callResearch(t, s, "POST", pages, map[string]string{
		"title": "Error estimates", "namespace": "methods/statistics", "body": "Source",
	}, 201))
	callResearch(t, s, "DELETE", pages+"/"+note.ID+"?revision=1", nil, 204)
	folders = decodeResearch[[]string](t, callResearch(t, s, "GET", wiki(first), nil, 200))
	if !slices.Equal(folders, []string{"methods", "methods/statistics"}) {
		t.Fatalf("archiving the last note removed explicit folders: %v", folders)
	}
}

func TestWikiFrontmatterParsesLegacySemanticsAndPreservesRawBytes(t *testing.T) {
	doc := "\uFEFF---\r\n" +
		"title: \"Graph: retrieval #1\"\r\npublished: 2026-08-05\r\nreviewed: true\r\n" +
		"tags: [rag, \"knowledge graph\", 'citation:analysis']\r\n" +
		"summary: |\r\n  First line keeps its newline.\r\n  ---\r\n  Second line keeps the # character.\r\n" +
		"defaults: &defaults\r\n  owner: \"Research: Team\"\r\n  future: {nested: [1, 2]}\r\n" +
		"copied: *defaults\r\nmerged:\r\n  <<: *defaults\r\n  reviewed: true\r\nempty_value: null\r\n...\r\n\r\n# Wiki"
	frontmatter, err := readWikiFrontmatter(doc)
	if err != nil {
		t.Fatal(err)
	}
	if frontmatter["title"] != "Graph: retrieval #1" || frontmatter["published"] != "2026-08-05" ||
		frontmatter["reviewed"] != true || frontmatter["empty_value"] != nil ||
		frontmatter["summary"] != "First line keeps its newline.\n---\nSecond line keeps the # character.\n" ||
		!reflect.DeepEqual(frontmatter["copied"], frontmatter["defaults"]) {
		t.Fatalf("frontmatter semantics: %#v", frontmatter)
	}
	merged, ok := frontmatter["merged"].(map[string]any)
	if !ok || merged["owner"] != "Research: Team" || merged["reviewed"] != true {
		t.Fatalf("merge did not resolve legacy anchors: %v", merged)
	}
	if noHeader, err := readWikiFrontmatter("---\nraw unclosed text"); noHeader != nil || err != nil {
		t.Fatalf("unclosed delimiters should remain Markdown: %v %v", noHeader, err)
	}
	s := newResearch(t, t.TempDir())
	p := createResearchProject(t, s, "Frontmatter")
	pages := "/projects/" + p.ID + "/notes"
	n := decodeResearch[Note](t, callResearch(t, s, "POST", pages, map[string]string{"title": "Fixture", "body": doc}, 201))
	path := pages + "/" + n.ID
	entries := decodeResearch[[]wikiMetadataEntry](t, callResearch(t, s, "GET", path+"/frontmatter?revision=1", nil, 200))
	if len(entries) != 9 || !slices.Contains(entries, wikiMetadataEntry{Key: "published", Value: "2026-08-05"}) {
		t.Fatalf("unexpected entries: %v", entries)
	}
	callResearch(t, s, "PATCH", path, map[string]any{"revision": 1, "body": "---\ntitle: [broken\n---"}, 400)
	callResearch(t, s, "PATCH", path, map[string]any{"revision": 1, "namespace": "research"}, 200)
	if got := string(callResearch(t, s, "GET", path+"/markdown", nil, 200)); got != doc {
		t.Fatal("original YAML comments, unknown entries or newline bytes changed")
	}
}

func TestWikiPaperPageUsesLibrarySnapshotAndCannotOverwrite(t *testing.T) {
	dir := t.TempDir()
	s := newResearch(t, dir)
	p := createResearchProject(t, s, "Templates")
	body, err := os.ReadFile(readerFixture(t))
	if err != nil {
		t.Fatal(err)
	}
	paper := uploadTestPDF(t, s.papers, string(body), `{"title":"Solar capture: an observation","authors":["Ada Jones"],"year":2026,"citekey":"jones-fixture-2026"}`)
	pages := "/projects/" + p.ID + "/notes"
	request := map[string]any{"paperId": paper.ID, "revision": paper.Revision}
	callResearch(t, s, "POST", pages+"/paper-template", map[string]any{"paperId": paper.ID, "revision": paper.Revision + 1}, 409)
	n := decodeResearch[Note](t, callResearch(t, s, "POST", pages+"/paper-template", request, 201))
	meta, err := readWikiFrontmatter(n.Body)
	if err != nil {
		t.Fatal(err)
	}
	if n.PaperID != paper.ID || n.Template != "paper" || len(n.Evidence) != 0 ||
		meta["id"] != paper.ID || meta["source_pdf"] != prefix+"/papers/"+paper.ID+"/pdf" ||
		meta["source_hash"] != paper.FileSHA256 || !strings.Contains(n.Body, "## TL;DR") ||
		!strings.Contains(n.Body, "[@"+paper.Citekey+"]") {
		t.Fatalf("template lacks original paper provenance: %#v, %#v", n, meta)
	}
	if got := callResearch(t, s, "GET", "/papers/"+paper.ID+"/pdf", nil, http.StatusOK); string(got) != string(body) {
		t.Fatal("template original PDF endpoint did not preserve bytes")
	}
	path := pages + "/" + n.ID
	callResearch(t, s, "PATCH", path, map[string]any{"revision": 1, "paperId": ""}, 400)
	callResearch(t, s, "PATCH", path, map[string]any{"revision": 1, "body": "Reviewed template"}, 200)
	callResearch(t, s, "POST", pages+"/paper-template", request, 409)
	s = newResearch(t, dir)
	reopened := decodeResearch[Note](t, callResearch(t, s, "GET", path, nil, 200))
	if reopened.Body != "Reviewed template" || reopened.PaperID != paper.ID {
		t.Fatalf("template duplicate overwrote a revised page: %#v", reopened)
	}
}

func TestWikiSnippetsUseRevisionedWorkspaceYAMLAndRecover(t *testing.T) {
	dir := t.TempDir()
	s := newResearch(t, dir)
	path := "/wiki/snippets"
	defaults := decodeResearch[wikiSnippetSettings](t, callResearch(t, s, "GET", path, nil, 200))
	if len(defaults.Snippets) != 5 || defaults.Snippets[1].Trigger != ";eq" {
		t.Fatalf("built-ins: %#v", defaults.Snippets)
	}
	custom := "# Custom entries keep user fields\n- trigger: ';result'\n  body: |\n    ## ${cursor}\n  future: {preserve: true}\n"
	updated := decodeResearch[wikiSnippetSettings](t, callResearch(t, s, "PUT", path, map[string]string{"content": custom, "revision": defaults.Revision}, 200))
	callResearch(t, s, "PUT", path, map[string]string{"content": defaults.Content, "revision": defaults.Revision}, 409)
	callResearch(t, s, "PUT", path, map[string]string{"content": "[broken", "revision": updated.Revision}, 400)
	s = newResearch(t, dir)
	read := decodeResearch[wikiSnippetSettings](t, callResearch(t, s, "GET", path, nil, 200))
	if read.Content != custom || read.Revision != updated.Revision || len(read.Snippets) != 1 ||
		read.Snippets[0].Trigger != ";result" || read.Snippets[0].Title != ";result" {
		t.Fatalf("custom file did not survive restart: %#v", read)
	}
	stored := filepath.Join(dir, "settings", "markdown_snippets.yaml")
	if err := os.WriteFile(stored, []byte("[broken"), 0600); err != nil {
		t.Fatal(err)
	}
	callResearch(t, s, "PUT", path, map[string]string{"content": defaults.Content, "revision": updated.Revision}, 409)
	invalid := decodeResearch[wikiSnippetSettings](t, callResearch(t, s, "GET", path, nil, 200))
	if invalid.Content != "[broken" || invalid.ParseError == "" || len(invalid.Snippets) != 5 {
		t.Fatalf("invalid config did not expose recovery path: %#v", invalid)
	}
	repaired := decodeResearch[wikiSnippetSettings](t, callResearch(t, s, "PUT", path, map[string]string{"content": custom, "revision": invalid.Revision}, 200))
	if repaired.Content != custom || repaired.ParseError != "" {
		t.Fatalf("repair did not restore custom snippets: %#v", repaired)
	}
}
