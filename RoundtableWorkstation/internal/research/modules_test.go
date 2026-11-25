package research

import (
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"slices"
	"testing"
)

func moduleGet(t *testing.T, s *Service, project string) moduleResponse {
	t.Helper()
	return decodeResearch[moduleResponse](t, callResearch(t, s, "GET", "/modules?project="+project, nil, 200))
}

func modulePatch(t *testing.T, s *Service, project string, change moduleChange) moduleResponse {
	t.Helper()
	change.Revision = moduleGet(t, s, project).Revision
	return decodeResearch[moduleResponse](t, callResearch(t, s, "PATCH", "/modules?project="+project, change, 200))
}

func moduleCheck(t *testing.T, state moduleResponse, id string, configured, effective, placeholder bool) moduleState {
	t.Helper()
	for _, module := range state.Modules {
		if module.ID != id {
			continue
		}
		if module.Enabled != configured || module.Effective != effective || module.Placeholder != placeholder {
			t.Fatalf("unexpected %s: %+v", id, module)
		}
		return module
	}
	t.Fatalf("missing module %s", id)
	return moduleState{}
}

func moduleBool(v bool) *bool { return &v }

func TestModuleDependenciesAndPlaceholders(t *testing.T) {
	s := newResearch(t, t.TempDir())
	state := moduleGet(t, s, "")
	want := []string{"projects", "paper-library", "wiki", "materials", "tasks", "calendar", "pdf-reader", "ai-lab", "citation-graph", "recommendation"}
	var enabled []string
	for _, module := range state.Modules {
		if module.Effective {
			enabled = append(enabled, module.ID)
		}
	}
	if !slices.Equal(enabled, want) {
		t.Fatalf("default modules %v want %v", enabled, want)
	}
	moduleCheck(t, state, "experiments", false, false, true)
	state = modulePatch(t, s, "", moduleChange{Action: "set", ModuleID: "wiki", Enabled: moduleBool(false)})
	moduleCheck(t, state, "wiki", false, false, false)
	moduleCheck(t, state, "citation-graph", true, false, false)
	callResearch(t, s, "PATCH", "/modules", moduleChange{Action: "set", ModuleID: "code", Enabled: moduleBool(true), Revision: state.Revision}, 400)
	if unchanged := moduleGet(t, s, ""); unchanged.Revision != state.Revision {
		t.Fatal("failed mutation changed revision")
	}
	state = modulePatch(t, s, "", moduleChange{Action: "set", ModuleID: "projects", Enabled: moduleBool(false)})
	moduleCheck(t, state, "tasks", true, false, false)
	moduleCheck(t, state, "calendar", true, false, false)
	state = modulePatch(t, s, "", moduleChange{Action: "enable-dependencies", ModuleID: "experiments"})
	for _, id := range []string{"projects", "wiki", "ai-lab", "materials", "calendar"} {
		moduleCheck(t, state, id, true, true, false)
	}
	for _, id := range []string{"code", "datasets", "experiments"} {
		moduleCheck(t, state, id, true, true, true)
	}
	moduleCheck(t, state, "writing", false, false, true)
}

func TestModulePinsAndProjectOverridesRoundTrip(t *testing.T) {
	dir := t.TempDir()
	s := newResearch(t, dir)
	first := createResearchProject(t, s, "First")
	second := createResearchProject(t, s, "Second")
	for _, id := range []string{"wiki", "calendar"} {
		modulePatch(t, s, "", moduleChange{Action: "pin", ModuleID: id, Enabled: moduleBool(true)})
	}
	zero := 0
	modulePatch(t, s, "", moduleChange{Action: "move", ModuleID: "calendar", Position: &zero})
	state := modulePatch(t, s, first.ID, moduleChange{Action: "set", ModuleID: "tasks", Enabled: moduleBool(false)})
	if module := moduleCheck(t, state, "tasks", false, false, false); module.Override == nil || *module.Override || !module.WorkspaceEnabled {
		t.Fatalf("expected project override: %+v", module)
	}
	if module := moduleCheck(t, state, "calendar", true, false, false); !module.Pinned || module.Override != nil {
		t.Fatalf("expected inherited but dependency-blocked pin: %+v", module)
	}
	s = newResearch(t, dir)
	state = moduleGet(t, s, first.ID)
	if !slices.Equal(state.PinnedOrder, []string{"calendar", "wiki"}) {
		t.Fatalf("invalid pin order %v", state.PinnedOrder)
	}
	moduleCheck(t, state, "calendar", true, false, false)
	moduleCheck(t, moduleGet(t, s, ""), "calendar", true, true, false)
	moduleCheck(t, moduleGet(t, s, second.ID), "calendar", true, true, false)
	for _, test := range []struct {
		project string
		enabled bool
	}{{first.ID, false}, {second.ID, true}, {"", true}} {
		if enabled, err := s.ModuleEnabled(test.project, "calendar"); err != nil || enabled != test.enabled {
			t.Fatalf("unexpected resolution %v: %v", enabled, err)
		}
	}
	global := modulePatch(t, s, "", moduleChange{Action: "reset"})
	if len(global.PinnedOrder) != 0 {
		t.Fatalf("reset retained workspace pins: %v", global.PinnedOrder)
	}
	moduleCheck(t, moduleGet(t, s, first.ID), "tasks", false, false, false)
	callResearch(t, s, "DELETE", "/projects/"+first.ID+"?revision=1", nil, 204)
	callResearch(t, s, "GET", "/modules?project="+first.ID, nil, 404)
	callResearch(t, s, "POST", "/projects/"+first.ID+"/restore", map[string]int{"revision": 2}, 200)
	moduleCheck(t, moduleGet(t, s, first.ID), "tasks", false, false, false)
	state = modulePatch(t, s, first.ID, moduleChange{Action: "set", ModuleID: "tasks"})
	if module := moduleCheck(t, state, "tasks", true, true, false); module.Override != nil {
		t.Fatalf("expected inherited choice: %+v", module)
	}
}

func TestModuleMutationRejectsStaleConfigAndPreservesUnknownFields(t *testing.T) {
	dir := t.TempDir()
	s := newResearch(t, dir)
	project := createResearchProject(t, s, "Project")
	other := newResearch(t, t.TempDir())
	global := moduleGet(t, s, "")
	change := moduleChange{Action: "set", ModuleID: "wiki", Enabled: moduleBool(false), Revision: global.Revision}
	callResearch(t, other, "PATCH", "/modules", change, 409)
	callResearch(t, s, "PATCH", "/modules?project="+project.ID, change, 409)
	callResearch(t, s, "PATCH", "/modules", change, 200)
	callResearch(t, s, "PATCH", "/modules", change, 409)
	callResearch(t, s, "PATCH", "/modules", moduleChange{Action: "reset"}, 428)

	path := filepath.Join(dir, moduleSettingsFile)
	original := `{"version":1,"enabled":{"future":false},"pins":["future"],"projects":{"future-project":{"future":true}},"future":{"nested":[1,false]}}`
	if err := os.WriteFile(path, []byte(original), 0600); err != nil {
		t.Fatal(err)
	}
	modulePatch(t, s, "", moduleChange{Action: "reset"})
	result := readModuleTestFile(t, path)
	var decodedA, decodedB any
	if err := json.Unmarshal([]byte(original), &decodedA); err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(result, &decodedB); err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(decodedA, decodedB) {
		t.Fatalf("unexpected saved fields: %s", result)
	}
	for _, broken := range []string{`{"version":2}`, `{"version":1,"enabled":[]}`, `{"version":1`, `null`} {
		if err := os.WriteFile(path, []byte(broken), 0600); err != nil {
			t.Fatal(err)
		}
		callResearch(t, s, "GET", "/modules", nil, 500)
		callResearch(t, s, "PATCH", "/modules", change, 500)
		if actual := string(readModuleTestFile(t, path)); actual != broken {
			t.Fatalf("failed edit overwrote config with %s", actual)
		}
	}
	if err := os.WriteFile(path, result, 0600); err != nil {
		t.Fatal(err)
	}
	moduleCheck(t, moduleGet(t, s, ""), "wiki", true, true, false)
}

func readModuleTestFile(t *testing.T, path string) []byte {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return data
}

func TestRepairModuleDirectoryStaysWithinResearchRoot(t *testing.T) {
	dir := t.TempDir()
	s := newResearch(t, dir)
	if err := os.Remove(filepath.Join(dir, "library/pdf")); err != nil {
		t.Fatal(err)
	}
	state := moduleGet(t, s, "")
	library := moduleCheck(t, state, "paper-library", true, true, false)
	if len(library.Paths) != 2 || library.Paths[1].Exists || !library.Paths[1].Repairable {
		t.Fatalf("missing directory was not marked repairable: %+v", library.Paths)
	}
	invalid := moduleChange{Action: "repair", ModuleID: "paper-library", Path: "../../outside", Revision: state.Revision}
	callResearch(t, s, "PATCH", "/modules", invalid, 400)
	state = modulePatch(t, s, "", moduleChange{Action: "repair", ModuleID: "paper-library", Path: "library/pdf"})
	library = moduleCheck(t, state, "paper-library", true, true, false)
	if !library.Paths[1].Exists || library.Paths[1].Repairable {
		t.Fatalf("directory was not repaired: %+v", library.Paths)
	}
	if err := os.Rename(filepath.Join(dir, "library"), filepath.Join(dir, "old-library")); err != nil {
		t.Fatal(err)
	}
	outside := t.TempDir()
	if err := os.Symlink(outside, filepath.Join(dir, "library")); err != nil {
		t.Fatal(err)
	}
	callResearch(t, s, "PATCH", "/modules", moduleChange{Action: "repair", ModuleID: "paper-library", Path: "library/pdf", Revision: state.Revision}, 400)
	if _, err := os.Stat(filepath.Join(outside, "pdf")); !os.IsNotExist(err) {
		t.Fatalf("repair escaped research root: %v", err)
	}
}
