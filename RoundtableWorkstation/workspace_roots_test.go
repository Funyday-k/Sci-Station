package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"scistation.local/desktop/internal/research"
	"strings"
	"sync/atomic"
	"testing"
)

func TestRootSelectionRequiresExplicitCompatibleIndependentRoot(t *testing.T) {
	roots := desktopRoots{t.TempDir()}
	base := t.TempDir()
	choice, err := roots.initial("")
	if err != nil || choice.dir != "" {
		t.Fatal(choice, err)
	}
	if _, err := roots.initial(filepath.Join(base, "one")); err != nil {
		t.Fatal(err)
	}
	one := filepath.Join(base, "one")
	if _, _, err := inspectRoot(one, false); err == nil {
		t.Fatal("opened unmarked directory")
	}
	if err := markNewRoot(one); err != nil {
		t.Fatal(err)
	}
	real, _, err := inspectRoot(one, false)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := roots.initial(filepath.Join(real, "nested", "workspace")); err == nil {
		t.Fatal("nested result")
	}
	if _, err := os.Stat(filepath.Join(real, "nested")); !os.IsNotExist(err) {
		t.Fatal("created nested data")
	}
	if err := roots.remember(real); err != nil {
		t.Fatal(err)
	}
	if p, err := roots.last(); err != nil || p != real {
		t.Fatal(p, err)
	}
	p1, err := roots.reserve(real, 0)
	if err != nil {
		t.Fatal(err)
	}
	other, err := roots.reserve(base, 0)
	if err != nil || other == p1 {
		t.Fatal(other, err)
	}
	if _, err := roots.reserve(base, p1); err == nil {
		t.Fatal("reassigned root port")
	}
	if p, err := roots.reserve(real, 0); err != nil || p != p1 {
		t.Fatal(p, err)
	}
	if err := os.WriteFile(filepath.Join(real, rootMarker), []byte("future"), 0600); err != nil {
		t.Fatal(err)
	}
	if _, _, err := inspectRoot(real, false); err == nil {
		t.Fatal("opened newer format")
	}
}

func TestRootSessionStagedSwitchFailureCancellationAndDelayedWork(t *testing.T) {
	var oldClosed, newClosed atomic.Int32
	old := &workspaceInstance{dir: "old", api: &apiServer{}, close: func() { oldClosed.Add(1) }}
	next := &workspaceInstance{dir: "new", api: &apiServer{}, close: func() { newClosed.Add(1) }}
	s := rootSession{active: old}
	failed := errors.New("candidate unavailable")
	published := false
	publish := func(*workspaceInstance) error { published = true; return nil }
	if err := s.switchTo(s.beginFor(old.api), func() (*workspaceInstance, error) { return nil, failed }, publish); !errors.Is(err, failed) {
		t.Fatal(err)
	}
	if published || s.active != old || oldClosed.Load() != 0 {
		t.Fatal("failed open changed active root")
	}
	started, ready, done := make(chan struct{}), make(chan struct{}), make(chan struct{})
	token := s.beginFor(old.api)
	go func() {
		defer close(done)
		_ = s.switchTo(token, func() (*workspaceInstance, error) { close(started); <-ready; return next, nil }, publish)
	}()
	<-started
	s.beginFor(old.api) // a later chooser was cancelled
	close(ready)
	<-done
	if published || s.active != old || oldClosed.Load() != 0 || newClosed.Load() != 1 {
		t.Fatal("cancelled load published")
	}
	err := s.switchTo(s.beginFor(old.api), func() (*workspaceInstance, error) { return next, nil }, func(*workspaceInstance) error { return failed })
	if !errors.Is(err, failed) || s.active != old || newClosed.Load() != 2 {
		t.Fatal("failed publication discarded original")
	}
	if err := s.switchTo(s.beginFor(old.api), func() (*workspaceInstance, error) { return next, nil }, publish); err != nil {
		t.Fatal(err)
	}
	if s.beginFor(old.api) != 0 {
		t.Fatal("old origin can initiate a new switch")
	}
	s.shutdown()
	if !published || oldClosed.Load() != 1 || newClosed.Load() != 3 {
		t.Fatal("service cleanup incomplete")
	}
}

func TestRootInstancesIsolateDelayedProjectWritesAndLocks(t *testing.T) {
	a, err := startWorkspace(t.TempDir(), 0, false, true)
	if err != nil {
		t.Fatal(err)
	}
	defer a.close()
	b, err := startWorkspace(t.TempDir(), 0, false, true)
	if err != nil {
		t.Fatal(err)
	}
	defer b.close()
	request := func(method, url, body string, status int) map[string]any {
		t.Helper()
		r, err := http.NewRequest(method, url, strings.NewReader(body))
		if err != nil {
			t.Fatal(err)
		}
		r.Header.Set("Content-Type", "application/json")
		r.Header.Set("X-Roundtable", "1")
		res, err := http.DefaultClient.Do(r)
		if err != nil {
			t.Fatal(err)
		}
		defer res.Body.Close()
		buf := new(bytes.Buffer)
		buf.ReadFrom(res.Body)
		if res.StatusCode != status {
			t.Fatalf("%s: %d: %s", url, res.StatusCode, buf)
		}
		var data map[string]any
		_ = json.Unmarshal(buf.Bytes(), &data)
		return data
	}
	if _, err := startWorkspace(a.dir, 0, false, false); err == nil {
		t.Fatal("second owner opened root")
	}
	if request("GET", a.address+"/api/workspace", "", 200)["id"] == request("GET", b.address+"/api/workspace", "", 200)["id"] {
		t.Fatal("roots share identity")
	}
	p := request("POST", a.address+"/api/research/projects", `{"name":"Root A fixture"}`, 201)
	q := request("POST", b.address+"/api/research/projects", `{"name":"Root B fixture"}`, 201)
	pending := "/api/research/projects/" + p["id"].(string) + "/notes"
	request("POST", a.address+pending, `{"title":"delayed A","body":"fixture"}`, 201)
	request("GET", b.address+pending, "", 404)
	request("GET", a.address+"/api/research/projects/"+q["id"].(string), "", 404)
	host := a.dir
	a.close()
	reopened, err := startWorkspace(host, 0, false, false)
	if err != nil {
		t.Fatal(err)
	}
	defer reopened.close()
	request("GET", reopened.address+pending, "", 200)
}

func TestStudioRegistrationUsesActiveRootResearchIdentity(t *testing.T) {
	root := t.TempDir()
	prefs, err := openSettings(root)
	if err != nil {
		t.Fatal(err)
	}
	lab, err := research.New(filepath.Join(root, "research"))
	if err != nil {
		t.Fatal(err)
	}
	api := &apiServer{prefs: prefs, research: lab}
	lab.SetPathValidator(api.approvedResearchPath)
	ext, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	var list struct {
		Projects []projectSummary `json:"projects"`
	}
	projectTestRequest(t, api.serve(8765), "POST", "", map[string]string{"path": ext}, 200, &list)
	if len(list.Projects) != 1 || list.Projects[0].ID == "" {
		t.Fatal(list)
	}
	id := list.Projects[0].ID
	if path, err := lab.ProjectDirectory(id); err != nil || path != ext {
		t.Fatal(path, err)
	}
	if repeated, err := lab.EnsureDirectoryProject(ext); err != nil || repeated.ID != id {
		t.Fatal(repeated, err)
	}
	entries, err := loadProjectRecords(api.projectsFile())
	if err != nil {
		t.Fatal(err)
	}
	original := entries[ext]
	var raw map[string]json.RawMessage
	if err := json.Unmarshal(original.disk, &raw); err != nil {
		t.Fatal(err)
	}
	raw["future"] = json.RawMessage(`{"keep":true}`)
	raw["directoryGrant"] = json.RawMessage(fmt.Sprintf(`{"device":%d,"inode":%d,"future":"keep"}`, original.DirectoryGrant.Device, original.DirectoryGrant.Inode))
	original.disk, err = json.Marshal(raw)
	if err != nil {
		t.Fatal(err)
	}
	entries[ext] = original
	if err := saveProjectRecords(api.projectsFile(), entries); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(api.projectsFile())
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Contains(data, []byte(`"keep": true`)) || !bytes.Contains(data, []byte(`"future": "keep"`)) {
		t.Fatalf("registry metadata lost: %s", data)
	}
}
