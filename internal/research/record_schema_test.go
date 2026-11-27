package research

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func readRecordFixture(t *testing.T, path string) []byte {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return data
}

func writeRecordFixture(t *testing.T, path string, data []byte) []byte {
	t.Helper()
	if err := os.WriteFile(path, data, 0600); err != nil {
		t.Fatal(err)
	}
	return data
}

func assertRecordBytes(t *testing.T, path string, expected []byte) {
	t.Helper()
	if got := readRecordFixture(t, path); !bytes.Equal(got, expected) {
		t.Fatalf("record changed: %s\nwant: %s", got, expected)
	}
}

func legacyRecordFixture(t *testing.T, path string) []byte {
	t.Helper()
	record := decodeResearch[map[string]json.RawMessage](t, readRecordFixture(t, path))
	if string(record["schema_version"]) != "1" {
		t.Fatalf("new record schema_version: %s", record["schema_version"])
	}
	delete(record, "schema_version")
	record["retained"] = json.RawMessage(`{"items":[99999999999999999999]}`)
	legacy, err := json.MarshalIndent(record, "", "  ")
	if err != nil {
		t.Fatal(err)
	}
	return writeRecordFixture(t, path, legacy)
}

func assertVersionedRecordFixture(t *testing.T, path string) {
	t.Helper()
	record := decodeResearch[map[string]json.RawMessage](t, readRecordFixture(t, path))
	if string(record["schema_version"]) != "1" || string(record["retained"]) != `{"items":[99999999999999999999]}` {
		t.Fatalf("version or unknown field was lost: %s", record)
	}
}

func TestProjectRecordSchemaUpgradesAfterLegacyDirectoryRecovery(t *testing.T) {
	s := newResearch(t, t.TempDir())
	project := createResearchProject(t, s, "Managed project")
	path := s.recordPath(project.ID)
	legacy := legacyRecordFixture(t, path)

	// Simulate an interruption between the directory move and the record write.
	other := s.managedDirectory(project.ID, true)
	if err := os.Rename(project.Path, other); err != nil {
		t.Fatal(err)
	}
	s = newResearch(t, s.dir)
	if got, err := s.ProjectDirectory(project.ID); err != nil || got != project.Path {
		t.Fatal(got, err)
	}
	peer := newResearch(t, s.dir)
	route := "/projects/" + project.ID
	view := callResearch(t, s, "GET", route, nil, 200)
	if bytes.Contains(view, []byte(`"schema_version"`)) {
		t.Fatalf("disk-only version leaked into the project API: %s", view)
	}
	callResearch(t, s, "POST", route+"/trash", map[string]int{"revision": 2}, 409)
	assertRecordBytes(t, path, legacy)

	callResearch(t, s, "POST", route+"/trash", map[string]int{"revision": 1}, 204)
	assertVersionedRecordFixture(t, path)
	saved := readRecordFixture(t, path)
	callResearch(t, peer, "PATCH", route, map[string]any{"revision": 1, "name": "Stale edit"}, 409)
	assertRecordBytes(t, path, saved)
	s = newResearch(t, s.dir)
	view = callResearch(t, s, "POST", route+"/restore", map[string]int{"revision": 2}, 200)
	restored := decodeResearch[Project](t, view)
	if restored.ID != project.ID || restored.Path != project.Path || restored.Revision != 3 {
		t.Fatal(restored)
	}
	assertVersionedRecordFixture(t, path)
}

func TestPaperRecordSchemaUpgradesWithAtomicMarkdownSave(t *testing.T) {
	s := newResearch(t, t.TempDir())
	paper, _, err := s.papers.create(PaperMetadata{Title: "Paper fixture"}, "", "")
	if err != nil {
		t.Fatal(err)
	}
	first := "# Findings\nThis is the original body.\n"
	paper = decodeResearch[Paper](t, uploadMarkdownFixture(t, s, paper, first, 200))
	path := filepath.Join(s.papers.dir, "records", paper.ID+".json")
	legacy := legacyRecordFixture(t, path)
	s = newResearch(t, s.dir)
	peer := newResearch(t, s.dir)
	route := "/papers/" + paper.ID
	callResearch(t, s, "GET", route, nil, 200)
	uploadMarkdownFixture(t, s, paper, first, 200)
	stale := paper
	stale.Revision++
	original := "# Findings\nThis is the retained body.\n"
	uploadMarkdownFixture(t, s, stale, original, 409)
	assertRecordBytes(t, path, legacy)

	view := uploadMarkdownFixture(t, s, paper, original, 200)
	saved := decodeResearch[Paper](t, view)
	if saved.Revision != 3 || saved.Markdown == nil || saved.Markdown.Revision != 2 || bytes.Contains(view, []byte(`"schema_version"`)) {
		t.Fatalf("paper API response: %s", view)
	}
	assertVersionedRecordFixture(t, path)
	versioned := readRecordFixture(t, path)
	uploadMarkdownFixture(t, peer, paper, "A competing body.", 409)
	assertRecordBytes(t, path, versioned)
	s = newResearch(t, s.dir)
	if body := callResearch(t, s, "GET", route+"/body", nil, 200); string(body) != original {
		t.Fatal(string(body))
	}
}

func TestProjectRecordSchemaAllowsLegacyDirectoryRebind(t *testing.T) {
	first, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	second, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	s := newResearch(t, t.TempDir())
	allowed := func(path string) bool { return path == first || path == second }
	s.SetPathValidator(allowed)
	project, err := s.EnsureDirectoryProject(first)
	if err != nil {
		t.Fatal(err)
	}
	path := s.recordPath(project.ID)
	legacy := legacyRecordFixture(t, path)
	s = newResearch(t, s.dir)
	s.SetPathValidator(allowed)
	assertRecordBytes(t, path, legacy)
	callResearch(t, s, "POST", "/projects/"+project.ID+"/directory", map[string]any{"revision": 1, "path": second}, 200)
	assertVersionedRecordFixture(t, path)
	s = newResearch(t, s.dir)
	if dir, err := s.ProjectDirectory(project.ID); err != nil || dir != second {
		t.Fatal(dir, err)
	}
}

func TestResearchRecordSchemaRejectsUnsupportedAndMalformedVersions(t *testing.T) {
	s := newResearch(t, t.TempDir())
	project := createResearchProject(t, s, "Project fixture")
	paper, _, err := s.papers.create(PaperMetadata{Title: "Paper fixture"}, "", "")
	if err != nil {
		t.Fatal(err)
	}
	projectPath := s.recordPath(project.ID)
	paperPath := filepath.Join(s.papers.dir, "records", paper.ID+".json")
	projectBackup := readRecordFixture(t, projectPath)
	paperBackup := readRecordFixture(t, paperPath)
	edit := map[string]any{"revision": 1, "name": "Renamed fixture"}
	for _, bad := range []struct{ name, field string }{
		{"future", `"schema_version":2`},
		{"zero", `"schema_version":0`},
		{"null", `"schema_version":null`},
		{"string", `"schema_version":"1"`},
		{"decimal", `"schema_version":1.0`},
		{"duplicate", `"schema_version":1,"schema_version":1`},
		{"shadowed-future", `"schema_version":2,"schema_version":1`},
	} {
		t.Run(bad.name, func(t *testing.T) {
			for _, fixture := range []struct {
				path         string
				backup       []byte
				route        string
				update       map[string]any
				failedStatus int
			}{
				{projectPath, projectBackup, "/projects/" + project.ID, edit, 409},
				{paperPath, paperBackup, "/papers/" + paper.ID, map[string]any{"revision": 1, "title": "Renamed fixture"}, 500},
			} {
				badBytes := bytes.Replace(fixture.backup, []byte(`"schema_version":1`), []byte(bad.field), 1)
				writeRecordFixture(t, fixture.path, badBytes)
				if _, err := New(s.dir); err == nil || !strings.Contains(err.Error(), "schema_version") {
					t.Fatalf("reopen %s: %v", fixture.route, err)
				}
				callResearch(t, s, "PATCH", fixture.route, fixture.update, fixture.failedStatus)
				if fixture.path == paperPath && bad.name == "future" {
					if err := s.papers.remove(paper.ID, paper.Revision); err == nil {
						t.Fatal("removed an unsupported record")
					}
				}
				assertRecordBytes(t, fixture.path, badBytes)
				writeRecordFixture(t, fixture.path, fixture.backup)
			}
		})
	}
	// Verified copies can reopen and accept ordinary updates again.
	s = newResearch(t, s.dir)
	callResearch(t, s, "PATCH", "/projects/"+project.ID, edit, 200)
	callResearch(t, s, "PATCH", "/papers/"+paper.ID, map[string]any{"revision": 1, "title": "Renamed fixture"}, 200)
}
