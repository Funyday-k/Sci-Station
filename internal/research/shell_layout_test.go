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
	const route = "/interface/layout"
	file := filepath.Join(dir, interfaceSettingsFile)
	fixture := []byte(`{"version":1,"language":"en","future":true,"shellLayout":{"futureLayout":{"x":3}}}`)
	if err := os.WriteFile(file, fixture, 0600); err != nil {
		t.Fatal(err)
	}
	updates := []any{map[string]any{"mode": "ai", "width": 416}, map[string]any{"treeExpanded": false, "tabOrder": []string{"notes", "papers"}}, map[string]any{"projectId": p.ID, "collapsed": true, "pinned": true}}
	for _, in := range updates {
		callResearch(t, s, "PATCH", route, in, 200)
	}
	get := func(s *Service) shellLayout {
		return decodeResearch[shellLayout](t, callResearch(t, s, "GET", route, nil, 200))
	}
	a := get(newResearch(t, dir))
	if a.Mode != "ai" || a.Width != 416 || a.TreeExpanded || !slices.Equal(a.TabOrder, []string{"notes", "papers"}) || !slices.Contains(a.PinnedProjects, p.ID) || !slices.Contains(a.CollapsedProjects, p.ID) {
		t.Fatal(a)
	}
	b := get(newResearch(t, t.TempDir()))
	if b.Mode != "inspector" || b.Width != 360 || !b.TreeExpanded || len(b.PinnedProjects) != 0 {
		t.Fatal(b)
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
	broken := []byte(`{"version":1,"language":"en","shellLayout":"damaged"}`)
	if err := os.WriteFile(file, broken, 0600); err != nil {
		t.Fatal(err)
	}
	callResearch(t, s, "PATCH", route, map[string]any{"width": 400}, 500)
	if string(readModuleTestFile(t, file)) != string(broken) {
		t.Fatal("damaged layout was overwritten")
	}
}
