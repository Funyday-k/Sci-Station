package research

import (
	"encoding/json"
	"os"
	"path/filepath"
	"slices"
	"testing"
)

func TestWorkspaceShellLayoutIsolationAndRecovery(t *testing.T) {
	dir := t.TempDir()
	s := newResearch(t, dir)
	p := createResearchProject(t, s, "Shell fixture")
	p2 := createResearchProject(t, s, "Companion fixture")
	const route = "/interface/layout"
	file := filepath.Join(dir, interfaceSettingsFile)
	fixture := []byte(`{"version":1,"language":"en","future":true,"shellLayout":{"futureLayout":{"x":3}}}`)
	if err := os.WriteFile(file, fixture, 0600); err != nil {
		t.Fatal(err)
	}
	updates := []any{
		map[string]any{"mode": "ai", "panelPinned": true, "width": 416, "sessionSidebar": true},
		map[string]any{"treeExpanded": false, "tabOrder": []string{"notes", "papers"}},
		map[string]any{"projectId": p.ID, "collapsed": true, "pinned": true},
		map[string]any{"projectId": p2.ID, "collapsed": false},
	}
	for _, in := range updates {
		callResearch(t, s, "PATCH", route, in, 200)
	}
	get := func(s *Service) shellLayout {
		return decodeResearch[shellLayout](t, callResearch(t, s, "GET", route, nil, 200))
	}
	a := get(newResearch(t, dir))
	if !a.PanelPinned || a.Mode != "ai" || a.Width != 416 || a.TreeExpanded || !a.SessionSidebar ||
		!slices.Equal(a.TabOrder, []string{"notes", "papers"}) ||
		!slices.Contains(a.PinnedProjects, p.ID) ||
		!slices.Contains(a.CollapsedProjects, p.ID) ||
		slices.Contains(a.ExpandedProjects, p.ID) ||
		!slices.Contains(a.ExpandedProjects, p2.ID) ||
		slices.Contains(a.CollapsedProjects, p2.ID) {
		t.Fatal(a)
	}
	// Fresh workspace defaults: session sidebar closed, neither expanded nor collapsed overrides set.
	b := get(newResearch(t, t.TempDir()))
	if b.PanelPinned || b.Mode != "hidden" || b.Width != 360 || !b.TreeExpanded || b.SessionSidebar ||
		len(b.PinnedProjects) != 0 || len(b.CollapsedProjects) != 0 || len(b.ExpandedProjects) != 0 {
		t.Fatal(b)
	}
	// Toggling p from collapsed -> expanded removes it from CollapsedProjects and records it in ExpandedProjects.
	callResearch(t, s, "PATCH", route, map[string]any{"projectId": p.ID, "collapsed": false}, 200)
	afterExpand := get(newResearch(t, dir))
	if slices.Contains(afterExpand.CollapsedProjects, p.ID) || !slices.Contains(afterExpand.ExpandedProjects, p.ID) {
		t.Fatalf("expected %s to move from collapsed to expanded: %+v", p.ID, afterExpand)
	}
	callResearch(t, s, "PATCH", route, map[string]any{"sessionSidebar": false}, 200)
	if get(newResearch(t, dir)).SessionSidebar {
		t.Fatal("closing sessionSidebar did not persist")
	}
	callResearch(t, s, "PATCH", route, map[string]any{"mode": "other"}, 400)
	callResearch(t, s, "PATCH", route, map[string]any{"tabOrder": []string{"notes", "notes"}}, 400)
	callResearch(t, s, "PATCH", route, map[string]any{"projectId": "absent", "pinned": true}, 404)
	callResearch(t, s, "PATCH", "/interface", map[string]string{"language": "zh-Hans"}, 200)
	var out struct {
		Future      bool
		ShellLayout struct{ FutureLayout map[string]int }
	}
	if err := json.Unmarshal(readModuleTestFile(t, file), &out); err != nil || !out.Future || out.ShellLayout.FutureLayout["x"] != 3 {
		t.Fatalf("unknown fields: %+v, %v", out, err)
	}
	callResearch(t, s, "PATCH", route, map[string]any{"mode": "hidden"}, 200)
	if get(s).PanelPinned {
		t.Fatal("closing the pinned panel retained a pin")
	}
	// Earlier release layout without collapsedProjects, expandedProjects, or sessionSidebar.
	legacy := []byte(`{"version":1,"language":"en","shellLayout":{"mode":"inspector","width":415,"treeExpanded":false,"tabOrder":["notes"]}}`)
	if err := os.WriteFile(file, legacy, 0600); err != nil {
		t.Fatal(err)
	}
	old := get(newResearch(t, dir))
	if old.PanelPinned || old.Mode != "inspector" || old.Width != 415 || old.TreeExpanded || old.SessionSidebar ||
		!slices.Equal(old.TabOrder, []string{"notes"}) || len(old.CollapsedProjects) != 0 || len(old.ExpandedProjects) != 0 {
		t.Fatal(old)
	}
	// Earlier release layout WITH collapsedProjects preserves explicit collapses.
	legacyCollapsed := []byte(`{"version":1,"language":"en","shellLayout":{"mode":"hidden","width":360,"treeExpanded":true,"collapsedProjects":["` + p.ID + `"],"futureLayout":{"x":7}}}`)
	if err := os.WriteFile(file, legacyCollapsed, 0600); err != nil {
		t.Fatal(err)
	}
	gotLegacyCollapsed := get(newResearch(t, dir))
	if !slices.Contains(gotLegacyCollapsed.CollapsedProjects, p.ID) || len(gotLegacyCollapsed.ExpandedProjects) != 0 || gotLegacyCollapsed.SessionSidebar {
		t.Fatalf("legacy collapsedProjects not preserved: %+v", gotLegacyCollapsed)
	}
	legacyAI := []byte(`{"version":1,"language":"en","shellLayout":{"mode":"ai","width":411,"futureLayout":{"x":3}}}`)
	if err := os.WriteFile(file, legacyAI, 0600); err != nil {
		t.Fatal(err)
	}
	if got := get(s); !got.PanelPinned || got.Mode != "ai" || got.Width != 411 {
		t.Fatal(got)
	}
	callResearch(t, s, "PATCH", route, map[string]any{"panelPinned": false}, 200)
	if got := get(newResearch(t, dir)); got.PanelPinned || got.Mode != "ai" {
		t.Fatal(got)
	}
	out.ShellLayout.FutureLayout = nil
	if err := json.Unmarshal(readModuleTestFile(t, file), &out); err != nil || out.ShellLayout.FutureLayout["x"] != 3 {
		t.Fatalf("migrating legacy AI discarded unknown layout fields: %v", err)
	}
	// Invalid stored layout falls back to defaults on GET and refuses to overwrite on PATCH.
	broken := []byte(`{"version":1,"language":"en","shellLayout":"damaged"}`)
	if err := os.WriteFile(file, broken, 0600); err != nil {
		t.Fatal(err)
	}
	fallback := get(newResearch(t, dir))
	if fallback.Mode != "hidden" || fallback.Width != 360 || !fallback.TreeExpanded || fallback.SessionSidebar {
		t.Fatalf("invalid layout did not fall back to defaults on GET: %+v", fallback)
	}
	callResearch(t, s, "PATCH", route, map[string]any{"width": 400}, 500)
	if string(readModuleTestFile(t, file)) != string(broken) {
		t.Fatal("damaged layout was overwritten")
	}
	// A failed write leaves the previous valid state intact.
	validBeforeFailure := []byte(`{"version":1,"language":"en","shellLayout":{"mode":"hidden","width":360,"treeExpanded":true,"sessionSidebar":true}}`)
	if err := os.WriteFile(file, validBeforeFailure, 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(dir, 0500); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(dir, 0700) })
	callResearch(t, s, "PATCH", route, map[string]any{"sessionSidebar": false}, 500)
	if err := os.Chmod(dir, 0700); err != nil {
		t.Fatal(err)
	}
	if string(readModuleTestFile(t, file)) != string(validBeforeFailure) {
		t.Fatal("failed write modified previous layout state")
	}
	if !get(newResearch(t, dir)).SessionSidebar {
		t.Fatal("previous valid layout state was not retained after failed write")
	}
}
