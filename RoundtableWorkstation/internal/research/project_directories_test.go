package research

import (
	"errors"
	"os"
	"path/filepath"
	"testing"

	"scistation.local/desktop/internal/workspace"
)

func TestProjectTrashMovesOnlyOwnedDirectoryAndKeepsSharedPaper(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "research")
	s := newResearch(t, dir)
	p, q := createResearchProject(t, s, "A"), createResearchProject(t, s, "B")
	paper, _, err := s.papers.create(PaperMetadata{Title: "Fixture", ProjectIDs: []string{p.ID, q.ID}}, "", "")
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(p.Path, "content.md"), []byte("fixture"), 0600); err != nil {
		t.Fatal(err)
	}
	base := "/projects/" + p.ID
	callResearch(t, s, "DELETE", base+"?revision=1", nil, 204)
	callResearch(t, s, "POST", base+"/trash", map[string]int{"revision": 1}, 409)
	callResearch(t, s, "POST", base+"/trash", map[string]int{"revision": 2}, 204)
	if _, err := os.Stat(p.Path); !os.IsNotExist(err) {
		t.Fatalf("old path still accessible: %v", err)
	}
	s = newResearch(t, dir)
	bin := decodeResearch[[]Project](t, callResearch(t, s, "GET", "/projects?trashed=1", nil, 200))
	active := decodeResearch[[]Project](t, callResearch(t, s, "GET", "/projects", nil, 200))
	archived := decodeResearch[[]Project](t, callResearch(t, s, "GET", "/projects?archived=1", nil, 200))
	if len(bin) != 1 || bin[0].ID != p.ID || len(active) != 1 || active[0].ID != q.ID || len(archived) != 0 {
		t.Fatal(bin, active, archived)
	}
	if _, err := s.ProjectDirectory(p.ID); !errors.Is(err, os.ErrNotExist) {
		t.Fatal(err)
	}
	kept := decodeResearch[Paper](t, callResearch(t, s, "GET", "/papers/"+paper.ID, nil, 200))
	if len(kept.ProjectIDs) != 2 {
		t.Fatalf("membership changed: %#v", kept)
	}
	reopened := decodeResearch[Project](t, callResearch(t, s, "POST", base+"/restore", map[string]int{"revision": 3}, 200))
	content, err := os.ReadFile(filepath.Join(reopened.Path, "content.md"))
	if err != nil || string(content) != "fixture" || reopened.ID != p.ID || reopened.Path != p.Path {
		t.Fatal(reopened, err)
	}
	// A crash between folder rename and metadata commit is reconciled to the
	// last durable record on reopen.
	if err := os.Rename(p.Path, s.managedDirectory(p.ID, true)); err != nil {
		t.Fatal(err)
	}
	s = newResearch(t, dir)
	if path, err := s.ProjectDirectory(p.ID); err != nil || path != p.Path {
		t.Fatal(path, err)
	}
}

func TestExternalDirectoryGrantIdentityAndRevocation(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "research")
	ext, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	s := newResearch(t, dir)
	s.SetPathValidator(func(path string) bool { return path == ext })
	p, err := s.EnsureDirectoryProject(ext)
	if err != nil {
		t.Fatal(err)
	}
	marker := filepath.Join(ext, "fixture.txt")
	if err := os.WriteFile(marker, []byte("external fixture"), 0600); err != nil {
		t.Fatal(err)
	}
	if q, err := s.EnsureDirectoryProject(ext); err != nil || p.ID != q.ID {
		t.Fatal(q, err)
	}
	s = newResearch(t, dir)
	if path, err := s.ProjectDirectory(p.ID); err != nil || path != ext {
		t.Fatal(path, err)
	}
	base := "/projects/" + p.ID
	callResearch(t, s, "POST", base+"/directory", map[string]any{"revision": 1, "path": ""}, 200)
	if _, err := s.ProjectDirectory(p.ID); !errors.Is(err, os.ErrPermission) {
		t.Fatal(err)
	}
	s.SetPathValidator(func(path string) bool { return path == ext })
	if _, err := s.EnsureDirectoryProject(ext); !errors.Is(err, os.ErrPermission) {
		t.Fatal(err)
	}
	callResearch(t, s, "POST", base+"/directory", map[string]any{"revision": 2, "path": ext}, 200)
	if err := os.Rename(ext, ext+".moved"); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if err := os.RemoveAll(ext + ".moved"); err != nil {
			t.Error(err)
		}
	})
	if err := os.Mkdir(ext, 0700); err != nil {
		t.Fatal(err)
	}
	if _, err := s.ProjectDirectory(p.ID); !errors.Is(err, os.ErrPermission) {
		t.Fatal(err)
	}
	if err := os.Remove(ext); err != nil {
		t.Fatal(err)
	}
	if err := os.Rename(ext+".moved", ext); err != nil {
		t.Fatal(err)
	}
	callResearch(t, s, "POST", base+"/trash", map[string]int{"revision": 3}, 204)
	if b, err := os.ReadFile(marker); err != nil || string(b) != "external fixture" {
		t.Fatal(err)
	}
	restored := decodeResearch[Project](t, callResearch(t, s, "POST", base+"/restore", map[string]int{"revision": 4}, 200))
	if restored.ID != p.ID || restored.Path != ext {
		t.Fatal(restored)
	}
	if err := os.WriteFile(filepath.Join(ext, workspace.RootMarker), []byte(workspace.RootFormat), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := s.ProjectDirectory(p.ID); !errors.Is(err, os.ErrPermission) {
		t.Fatal(err)
	}
}
