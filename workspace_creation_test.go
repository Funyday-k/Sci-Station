package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"net/http/httptest"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"scistation.local/desktop/internal/meeting"
	"scistation.local/desktop/internal/research"
)

func rootFixtureRequest(t *testing.T, api *apiServer, method, path string, input any, code int, out any) {
	t.Helper()
	b, _ := json.Marshal(input)
	r := httptest.NewRequest(method, "http://localhost:8765"+path, bytes.NewReader(b))
	r.Header.Set("Content-Type", "application/json")
	r.Header.Set("X-Roundtable", "1")
	w := httptest.NewRecorder()
	api.serve(8765).ServeHTTP(w, r)
	if w.Code != code {
		t.Fatalf("%s %s: %d %s", method, path, w.Code, w.Body)
	}
	if out != nil {
		if err := json.Unmarshal(w.Body.Bytes(), out); err != nil {
			t.Fatal(err)
		}
	}
}

func TestRootCreationTemplatesSamplesAndCancellation(t *testing.T) {
	one := rootSetup{Name: "Reading group", Template: "minimal-workspace", Acknowledged: true}
	dir := t.TempDir()
	if err := seedNewWorkspace(dir, one); err != nil {
		t.Fatal(err)
	}
	svc, err := research.New(filepath.Join(dir, "research"))
	if err != nil {
		t.Fatal(err)
	}
	api := &apiServer{workspaceDir: dir, research: svc}
	if rootDisplay(dir) != "Reading group" {
		t.Fatal(rootDisplay(dir))
	}
	for _, id := range []string{"projects", "wiki", "tasks", "calendar", "ai-lab"} {
		if enabled, err := svc.ModuleEnabled("", id); err != nil || !enabled {
			t.Fatalf("minimal missing %s", id)
		}
	}
	for _, id := range []string{"paper-library", "pdf-reader", "materials", "code"} {
		if enabled, err := svc.ModuleEnabled("", id); err != nil || enabled {
			t.Fatal(id)
		}
	}
	var projects []research.Project
	rootFixtureRequest(t, api, "GET", "/api/research/projects", nil, 200, &projects)
	if len(projects) != 1 || projects[0].Name != "Reading group" || projects[0].ColorHex != "#4F7CAC" || projects[0].IconName != "folder" {
		t.Fatal("default project does not match the new root", projects)
	}
	var notes []research.Note
	rootFixtureRequest(t, api, "GET", "/api/research/projects/"+projects[0].ID+"/notes", nil, 200, &notes)
	if len(notes) != 0 {
		t.Fatal("non-sample root contains example notes", notes)
	}
	sample, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	if err := seedNewWorkspace(sample, rootSetup{Name: "Reading sample", Template: "literature-review", Sample: true, Acknowledged: true}); err != nil {
		t.Fatal(err)
	}
	svc, err = research.New(filepath.Join(sample, "research"))
	if err != nil {
		t.Fatal(err)
	}
	api.research = svc
	if enabled, err := svc.ModuleEnabled("", "pdf-reader"); err != nil || !enabled {
		t.Fatal("literature template has no reader")
	}
	rootFixtureRequest(t, api, "GET", "/api/research/projects", nil, 200, &projects)
	if len(projects) != 1 || !strings.Contains(projects[0].Name, "Sample") || filepath.Dir(filepath.Dir(projects[0].Path)) != filepath.Join(sample, "research") {
		t.Fatal(projects)
	}
	rootFixtureRequest(t, api, "GET", "/api/research/projects/"+projects[0].ID+"/notes", nil, 200, &notes)
	if len(notes) != 3 {
		t.Fatal(notes)
	}
	for _, n := range notes {
		if !strings.Contains(n.Title, "Sample") || n.PaperID != "" || len(n.Evidence) != 0 {
			t.Fatal(n)
		}
	}
	var papers []research.Paper
	rootFixtureRequest(t, api, "GET", "/api/research/papers", nil, 200, &papers)
	if len(papers) != 0 {
		t.Fatal("sample created research evidence")
	}
	// A cancelled native panel keeps the draft and does not initialize a folder.
	var invoked int
	api.createWorkspace = func(d rootSetup) (bool, error) {
		invoked++
		if d != one {
			t.Fatal(d)
		}
		return false, nil
	}
	var reply map[string]bool
	rootFixtureRequest(t, api, "POST", "/api/workspace/setup", one, 200, &reply)
	rootFixtureRequest(t, api, "POST", "/api/workspace/setup", rootSetup{Template: "theory-notes", Acknowledged: true}, 400, nil)
	if invoked != 1 || reply["opened"] {
		t.Fatal(invoked, reply)
	}
}

func TestWorkspaceTargetKeepsSelectedContentAndRejectsNestedRoots(t *testing.T) {
	parent, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	draft := rootSetup{Name: "Reading notes", Template: "literature-review", Acknowledged: true}
	target, err := prepareWorkspaceTarget(parent, draft)
	if err != nil || target != filepath.Join(parent, draft.Name) {
		t.Fatal(target, err)
	}
	file := filepath.Join(target, "existing.txt")
	if err := os.WriteFile(file, []byte("keep"), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := prepareWorkspaceTarget(parent, draft); !errors.Is(err, os.ErrExist) {
		t.Fatal("would reuse an existing path", err)
	}
	draft.UseEmptyFolder = true
	if _, err := prepareWorkspaceTarget(target, draft); err == nil {
		t.Fatal("would initialize a nonempty folder")
	}
	if data, err := os.ReadFile(file); err != nil || string(data) != "keep" {
		t.Fatal("existing content changed", err)
	}
	draft.UseEmptyFolder = false
	draft.Name = "Parent root"
	parentRoot, err := prepareWorkspaceTarget(parent, draft)
	if err != nil {
		t.Fatal(err)
	}
	if err := seedNewWorkspace(parentRoot, draft); err != nil {
		t.Fatal(err)
	}
	draft.Name = "Nested"
	if _, err := prepareWorkspaceTarget(parentRoot, draft); err == nil {
		t.Fatal("would create inside a research root")
	}
	draft.UseEmptyFolder = true
	draft.Name = ""
	empty, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	if dir, err := prepareWorkspaceTarget(empty, draft); err != nil || dir != empty {
		t.Fatal(dir, err)
	}
	if err := seedNewWorkspace(empty, draft); err != nil || rootDisplay(empty) != filepath.Base(empty) {
		t.Fatal(rootDisplay(empty), err)
	}
}

func TestRenameMaintainsIdentityRecordAndMeetingDirectory(t *testing.T) {
	parent, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	old := filepath.Join(parent, "original")
	next := filepath.Join(parent, "renamed")
	roots := desktopRoots{filepath.Join(parent, "registry")}
	if err = os.Mkdir(old, 0700); err != nil {
		t.Fatal(err)
	}
	a, err := startRegisteredWorkspace(roots, rootChoice{dir: old, create: true}, 0, false)
	if err != nil {
		t.Fatal(err)
	}
	defer a.close()
	initial, initialAddress := a.binding, a.address
	var project research.Project
	rootFixtureRequest(t, a.api, "POST", "/api/research/projects", map[string]any{"name": "Fixture", "iconName": "atom", "colorHex": "#a7c7e7"}, 201, &project)
	if project.ColorHex != "#A7C7E7" || project.IconName != "atom" {
		t.Fatal(project)
	}
	if err := os.WriteFile(filepath.Join(project.Path, "field-notes.md"), []byte("# Durable notes"), 0600); err != nil {
		t.Fatal(err)
	}
	var session meeting.Session
	rootFixtureRequest(t, a.api, "POST", "/api/studio/sessions", map[string]any{"topic": "Fixture discussion", "project_id": project.ID}, 201, &session)
	if err := roots.remember(old, a.binding); err != nil {
		t.Fatal(err)
	}
	id := a.binding
	if err = roots.moveRoot(old, next, id); err == nil {
		t.Fatal("moved in-use root")
	}
	if !a.freeze() {
		t.Fatal("unable to pause idle workspace")
	}
	a.close()
	if err = os.Mkdir(next, 0700); err != nil {
		t.Fatal(err)
	}
	if err = roots.moveRoot(old, next, id); err == nil {
		t.Fatal("would replace an existing destination")
	}
	if p, err := roots.last(); err != nil || p != old {
		t.Fatal(p, err)
	}
	if err = os.Remove(next); err != nil {
		t.Fatal(err)
	}
	if err = roots.moveRoot(old, next, id); err != nil {
		t.Fatal(err)
	}
	if p, err := roots.last(); err != nil || p != next {
		t.Fatal(p, err)
	}
	choice, err := roots.initial("")
	if err != nil {
		t.Fatal(err)
	}
	b, err := startRegisteredWorkspace(roots, choice, 0, false)
	if err != nil {
		t.Fatal(err)
	}
	defer b.close()
	if b.binding.ID != initial.ID || !slices.Contains(b.binding.Paths, old) || b.address != initialAddress {
		t.Fatal(b.binding, b.address)
	}
	var opened meeting.Session
	rootFixtureRequest(t, b.api, "GET", "/api/studio/sessions/"+session.ID, nil, 200, &opened)
	if opened.ProjectID != project.ID || opened.Project != filepath.Join(next, "research", "workspaces", project.ID) {
		t.Fatal(opened)
	}
	rootFixtureRequest(t, b.api, "GET", "/api/studio/sessions/"+session.ID+"/files", nil, 200, nil)
	if saved, err := os.ReadFile(filepath.Join(opened.Project, "field-notes.md")); err != nil || string(saved) != "# Durable notes" {
		t.Fatal("project content was lost during the move", err)
	}
	rootFixtureRequest(t, b.api, "GET", "/api/research/projects/"+project.ID, nil, 200, &project)
	if project.IconName != "atom" || project.ColorHex != "#A7C7E7" {
		t.Fatal(project)
	}
	rootFixtureRequest(t, b.api, "PATCH", "/api/research/projects/"+project.ID, map[string]any{"revision": project.Revision, "iconName": "star.fill", "colorHex": "#123456"}, 200, &project)
	rootFixtureRequest(t, b.api, "PATCH", "/api/research/projects/"+project.ID, map[string]any{"revision": project.Revision, "colorHex": "invalid"}, 400, nil)
	if project.IconName != "star.fill" {
		t.Fatal(project)
	}
	// A different resource later using the original name gets its own scope.
	if err = os.Mkdir(old, 0700); err != nil {
		t.Fatal(err)
	}
	replacement, err := startRegisteredWorkspace(roots, rootChoice{dir: old, create: true}, 0, false)
	if err != nil {
		t.Fatal(err)
	}
	defer replacement.close()
	if replacement.binding.ID == initial.ID {
		t.Fatal(replacement.binding)
	}
	staleStamp := roots.recentStamp()
	if err = roots.remember(old, replacement.binding); err != nil {
		t.Fatal(err)
	}
	if err := roots.forget("", staleStamp); err == nil {
		t.Fatal("an older welcome window cleared a newer selection")
	}
	if p, err := roots.last(); err != nil || p != old {
		t.Fatal(p, err)
	}
	if err = roots.forget(next); err != nil {
		t.Fatal(err)
	}
	if p, err := roots.last(); err != nil || p != old {
		t.Fatal("stale window cleared selection")
	}
	if err = roots.forget(old); err != nil {
		t.Fatal(err)
	}
	if p, err := roots.last(); p != "" || err != nil {
		t.Fatal(p, err)
	}
	if _, err = os.Stat(filepath.Join(next, rootMarker)); err != nil {
		t.Fatal(err)
	}
	if _, err = os.Stat(filepath.Join(roots.dir, "renamed-workspaces.json")); errors.Is(err, os.ErrNotExist) {
		t.Fatal("forget removed bindings")
	}
}
