package research

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"testing"
)

func TestWikiPageLifecycleAndProjectBacklinks(t *testing.T) {
	dir := t.TempDir()
	s := newResearch(t, dir)
	project := createResearchProject(t, s, "Solar wiki")
	other := createResearchProject(t, s, "Separate wiki")
	pages := func(p Project) string { return "/projects/" + p.ID + "/notes" }
	base := pages(project)
	create := func(path string, in map[string]any) Note {
		t.Helper()
		return decodeResearch[Note](t, callResearch(t, s, "POST", path, in, 201))
	}
	concept := create(base, map[string]any{"title": "Dark Matter", "namespace": "concepts", "aliases": []string{"DM", "reference/dark sector"}})
	method := create(base, map[string]any{"title": "Dark Matter", "namespace": "methods"})
	template := "---\nmetadata:\n  skipped: '[[concept:DM]]'\n---\n"
	body := template + "See [[concept:dark-matter#Definition|DM]], [[methods/Dark Matter]] and [[reference/dark sector]].\n\n> [[concept:DM]]\n"
	source := create(base, map[string]any{"title": "Solar Capture", "body": body})
	unqualified := create(base, map[string]any{"title": "Deep definitions", "body": "[[Dark Matter]]"})
	foreign := create(pages(other), map[string]any{"title": "Foreign DM", "body": "[[concept:DM]]"})

	refs := func(n Note) []Note {
		t.Helper()
		return decodeResearch[[]Note](t, callResearch(t, s, "GET", base+"/"+n.ID+"/backlinks", nil, 200))
	}
	outgoing := func(path string, n Note) map[string]string {
		t.Helper()
		return decodeResearch[map[string]string](t, callResearch(t, s, "GET", path+"/"+n.ID+"/links", nil, 200))
	}
	for _, n := range []Note{concept, method} {
		if got := refs(n); len(got) != 1 || got[0].ID != source.ID {
			t.Fatalf("backlinks for %s: %#v", n.ID, got)
		}
	}
	if got := outgoing(base, source); len(got) != 4 || got["concept:dark-matter"] != concept.ID || got["concept:DM"] != concept.ID || got["reference/dark sector"] != concept.ID || got["methods/Dark Matter"] != method.ID {
		t.Fatalf("resolved links: %v", got)
	}
	if got := outgoing(base, unqualified); len(got) != 0 {
		t.Fatalf("ambiguous page title resolved: %v", got)
	}
	if got := outgoing(pages(other), foreign); len(got) != 0 {
		t.Fatalf("foreign links resolved: %v", got)
	}

	path := base + "/" + concept.ID
	callResearch(t, s, "PATCH", path, map[string]any{"revision": 1, "namespace": "../escape"}, 400)
	callResearch(t, s, "PATCH", path, map[string]any{"revision": 1, "namespace": "methods"}, 409)
	moved := decodeResearch[Note](t, callResearch(t, s, "PATCH", path, map[string]any{"revision": 1, "namespace": "physics/particles", "title": "Particle Dark Matter"}, 200))
	if moved.ID != concept.ID || moved.Revision != 2 || !slices.Equal(moved.PreviousPaths, []string{"concepts/Dark Matter", "concepts/DM"}) {
		t.Fatalf("move altered identity or history: %#v", moved)
	}
	callResearch(t, s, "POST", base, map[string]any{"title": "Other", "aliases": []string{"concepts/DM"}}, 409)
	callResearch(t, s, "PATCH", path, map[string]any{"revision": 1, "body": "stale overwrite"}, 409)
	callResearch(t, s, "GET", path+"/links?revision=1", nil, 409)
	if got := refs(moved); len(got) != 1 || got[0].ID != source.ID {
		t.Fatalf("move broke historical backlinks: %#v", got)
	}

	callResearch(t, s, "DELETE", path+"?revision=1", nil, 409)
	callResearch(t, s, "DELETE", path+"?revision=2", nil, 204)
	callResearch(t, s, "GET", path, nil, 404)
	if got := outgoing(base, source); len(got) != 1 || got["methods/Dark Matter"] != method.ID {
		t.Fatalf("archived link targets returned: %v", got)
	}
	callResearch(t, s, "POST", base, map[string]any{"title": moved.Title, "namespace": moved.Namespace}, 409)

	s = newResearch(t, dir)
	archived := decodeResearch[[]Note](t, callResearch(t, s, "GET", base+"?archived=1", nil, 200))
	if len(archived) != 1 || archived[0].Revision != 3 || archived[0].ID != concept.ID {
		t.Fatalf("archive missing after restart: %#v", archived)
	}
	callResearch(t, s, "POST", path+"/restore", map[string]int{"revision": 2}, 409)
	restored := decodeResearch[Note](t, callResearch(t, s, "POST", path+"/restore", map[string]int{"revision": 3}, 200))
	if restored.Archived || restored.Revision != 4 || restored.Namespace != moved.Namespace {
		t.Fatalf("restore lost note state: %#v", restored)
	}
	if got := refs(restored); len(got) != 1 || got[0].ID != source.ID {
		t.Fatalf("restore broke backlinks: %#v", got)
	}
	if got := string(callResearch(t, s, "GET", base+"/"+source.ID+"/markdown", nil, 200)); got != body {
		t.Fatalf("Markdown changed: %q", got)
	}
}

func TestWikiOccurrencesUseSourceCoordinates(t *testing.T) {
	body := "---\r\ninternal: '[[hidden]]'\r\n...\r\n太阳 [[method:Glauber|GM]] and [[DM#overview]]\r\n" +
		"`[[inline]]` \\[[escaped]] [[real]]\r\n~~~markdown\r\n[[fenced]]\r\n~~~"
	links := wikiLinks(body)
	want := []wikiLinkOccurrence{
		{Target: "method:Glauber", Text: "[[method:Glauber|GM]]", Line: 4, Column: 4, Excerpt: "太阳 [[method:Glauber|GM]] and [[DM#overview]]"},
		{Target: "DM", Text: "[[DM#overview]]", Line: 4, Column: 30, Excerpt: "太阳 [[method:Glauber|GM]] and [[DM#overview]]"},
		{Target: "real", Text: "[[real]]", Line: 5, Column: 27, Excerpt: "`[[inline]]` \\[[escaped]] [[real]]"},
	}
	if !slices.Equal(links, want) {
		t.Fatalf("links: %#v", links)
	}
}

func TestWikiRecordCompatibilityAndFailedMove(t *testing.T) {
	dir := t.TempDir()
	s := newResearch(t, dir)
	p := createResearchProject(t, s, "Wiki compatibility")
	projectFile := s.recordPath(p.ID)
	noteID := makeID()
	before := []byte(fmt.Sprintf(`{
		"project":{"id":"%s","revision":1,"name":"Compatibility","path":%q,"futureProject":{"key":true}},
		"notes":{"%s":{"id":"%s","revision":1,"title":"Legacy", "projectId":"%s","body":"[[Legacy]]", "tags":[], "evidence":[{"quote":"Text","futureAnchor":{"paragraph":2}}], "futureNote":{"deeper":[1,{"two":2}]}}},
		"tasks":{},"materials":{},"noteKeys":{},"taskKeys":{},"futureRoot":{"layout":["A","B"]}
	}`, p.ID, p.Path, noteID, noteID, p.ID))
	if err := os.WriteFile(projectFile, before, 0600); err != nil {
		t.Fatal(err)
	}
	s = newResearch(t, dir)
	path := "/projects/" + p.ID + "/notes/" + noteID
	legacy := decodeResearch[Note](t, callResearch(t, s, "GET", path, nil, 200))
	if legacy.Title != "Legacy" || legacy.Archived || legacy.Namespace != "" {
		t.Fatalf("legacy metadata defaults: %#v", legacy)
	}

	recordsDir := filepath.Dir(projectFile)
	recoveryDir := recordsDir + ".recoverable"
	if err := os.Rename(recordsDir, recoveryDir); err != nil {
		t.Fatal(err)
	}
	callResearch(t, s, "PATCH", path, map[string]any{"revision": 1, "namespace": "broken"}, 500)
	unchanged := decodeResearch[Note](t, callResearch(t, s, "GET", path, nil, 200))
	if unchanged.Revision != 1 || unchanged.Namespace != "" || len(unchanged.PreviousPaths) != 0 {
		t.Fatalf("failed transfer changed active state: %#v", unchanged)
	}
	if err := os.Rename(recoveryDir, recordsDir); err != nil {
		t.Fatal(err)
	}

	changedOnDisk := bytes.Replace(before, []byte("Legacy"), []byte("Edited outside"), 1)
	if err := os.WriteFile(projectFile, changedOnDisk, 0600); err != nil {
		t.Fatal(err)
	}
	callResearch(t, s, "PATCH", path, map[string]any{"revision": 1, "namespace": "overwrite"}, 409)
	got, err := os.ReadFile(projectFile)
	if err != nil || !bytes.Equal(got, changedOnDisk) {
		t.Fatalf("conflict rewrote original record: %v, %s", err, got)
	}
	s = newResearch(t, dir)
	recovered := decodeResearch[Note](t, callResearch(t, s, "PATCH", path, map[string]any{"revision": 1, "namespace": "research"}, 200))
	if recovered.Title != "Edited outside" || recovered.Namespace != "research" || recovered.Revision != 2 {
		t.Fatalf("recovered note: %#v", recovered)
	}
	got, err = os.ReadFile(projectFile)
	if err != nil {
		t.Fatal(err)
	}
	var persisted struct {
		Project json.RawMessage
		Notes   map[string]json.RawMessage
	}
	if err := json.Unmarshal(got, &persisted); err != nil {
		t.Fatal(err)
	}
	for name, value := range map[string][]byte{"futureRoot": got, "futureProject": persisted.Project, "futureNote": persisted.Notes[noteID], "futureAnchor": persisted.Notes[noteID]} {
		if !bytes.Contains(value, []byte(`"`+name+`"`)) {
			t.Fatalf("lost %s: %s", name, got)
		}
	}
}
