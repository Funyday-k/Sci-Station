package desktop

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	"scistation.local/desktop/internal/cliedit"
	"scistation.local/desktop/internal/meeting"
	"scistation.local/desktop/internal/research"
)

func openNavigationFixture(t *testing.T, dir string) *apiServer {
	t.Helper()
	prefs, err := openSettings(dir)
	if err != nil {
		t.Fatal(err)
	}
	service, err := research.New(filepath.Join(dir, "research"))
	if err != nil {
		t.Fatal(err)
	}
	return &apiServer{prefs: prefs, research: service}
}

func navigationRequest(t *testing.T, api *apiServer, method, path, body string, want int) *httptest.ResponseRecorder {
	t.Helper()
	r := httptest.NewRequest(method, "http://127.0.0.1:8765"+path, strings.NewReader(body))
	r.Header.Set("X-Roundtable", "1")
	r.Header.Set("Content-Type", "application/json")
	result := httptest.NewRecorder()
	api.serve(8765).ServeHTTP(result, r)
	if result.Code != want {
		t.Fatalf("%s %s: %d %s", method, path, result.Code, result.Body.String())
	}
	return result
}

func TestWorkspaceShellServesEachDomainInOneLayout(t *testing.T) {
	api := openNavigationFixture(t, t.TempDir())
	for route, surface := range workspaceSurfaces {
		page := navigationRequest(t, api, "GET", route, "", 200).Body.String()
		for _, component := range []string{"<!doctype html>", `class="workspace-bar"`, `id="workspace-sidebar"`, `id="workspace-nav-toggle"`, `id="workspace-context"`, "<nav data-workspace-nav ", "<nav data-workspace-settings ", `id="rail-close"`, `data-workspace-surface="` + surface.name + `"`, `src="/static/workspace-nav.js"`} {
			if strings.Count(page, component) != 1 {
				t.Errorf("%s: missing or duplicate %s", route, component)
			}
		}
		// Slots arrive in the initial document, including when scripts have not run.
		contextStart := strings.Index(page, `id="workspace-context"`)
		toolbar := strings.Index(page, `class="workspace-bar"`)
		content := strings.Index(page, `class="workspace-region"`)
		if !(contextStart >= 0 && contextStart < toolbar && toolbar < content) {
			t.Fatalf("%s: unexpected shell order", route)
		}
		sessions := strings.Index(page, `id="workspace-session-sidebar"`)
		switch surface.name {
		case "lab", "studio":
			if sessions < contextStart || sessions > toolbar {
				t.Fatalf("%s: missing independent conversation sidebar", route)
			}
			first := page[contextStart:sessions]
			second := page[sessions:toolbar]
			if !strings.Contains(first, `id="workspace-projects"`) || strings.Contains(second, `id="workspace-projects"`) {
				t.Errorf("%s: project tree must stay in primary navigation", route)
			}
			history := `id="lab-history"`
			if surface.name == "studio" {
				history = `id="studio-session-sidebar"`
				if !strings.Contains(first, `id="settings-tab-models"`) || strings.Contains(second, `class="settings-nav"`) {
					t.Error("settings categories must stay outside conversation navigation")
				}
			}
			if !strings.Contains(second, history) || strings.Contains(first, history) {
				t.Errorf("%s: conversation history must be in the second sidebar", route)
			}
		default:
			if sessions >= 0 {
				t.Errorf("%s: unexpected conversation sidebar", route)
			}
		}
		if surface.name == "research" && !strings.Contains(page[toolbar:content], `id="search-open"`) {
			t.Error("research search must be mounted in the shared toolbar")
		}
		if strings.Contains(page, `id="workspace-ai-modes"`) != (surface.name == "lab" || surface.name == "studio") {
			t.Errorf("%s: unexpected AI mode selector", route)
		}
		if strings.Contains(page, "{{template") || strings.Contains(page, "<iframe") {
			t.Errorf("%s: unmounted domain", route)
		}
		if strings.Contains(page, `id="shell-inspect"`) || strings.Contains(page, `id="nav-toggle"`) {
			t.Errorf("%s: obsolete global inspector or duplicate navigation toggle", route)
		}
	}
	for _, view := range []string{"settings", "plugins"} {
		page := navigationRequest(t, api, "GET", "/studio?view="+view, "", 200).Body.String()
		if !strings.Contains(page, `<body class="settings-mode"`) ||
			!strings.Contains(page, `data-en-aria-label="Conversations" hidden inert>`) {
			t.Errorf("%s: settings mode must be active before scripts load", view)
		}
	}
	old := navigationRequest(t, api, "GET", "/static/reader.html?paper=abc", "", http.StatusTemporaryRedirect)
	if old.Header().Get("Location") != "/reader?paper=abc" {
		t.Fatal(old.Header())
	}
}

func TestWorkspaceRouteRecoveryIsScopedAndOrdered(t *testing.T) {
	root := t.TempDir()
	api := openNavigationFixture(t, root)
	const endpoint = "/api/workspace/navigation"
	save := func(event, route string) {
		navigationRequest(t, api, "POST", endpoint, `{"route":`+route+`,"event":`+event+`}`, 204)
	}
	file := api.navigationPath()
	if err := os.WriteFile(file, []byte(`{"version":1,"future":{"a":1}}`), 0600); err != nil {
		t.Fatal(err)
	}
	save("20", `"/research?view=tasks&task=task-1#selection"`)
	save("10", `"/lab"`)
	for _, route := range []string{`"//host/reader"`, `"/api/studio/settings"`, `"https://host/reader"`, `"/resume"`} {
		navigationRequest(t, api, "POST", endpoint, `{"event":30,"route":`+route+`}`, 400)
	}
	api = openNavigationFixture(t, root)
	redirect := navigationRequest(t, api, "GET", "/resume", "", 303)
	link, err := url.Parse(redirect.Header().Get("Location"))
	if err != nil {
		t.Fatal(err)
	}
	if link.Path != "/research" || link.Query().Get("task") != "task-1" || link.Fragment != "selection" {
		t.Fatal(link)
	}
	data, err := os.ReadFile(file)
	if err != nil || !strings.Contains(string(data), `"future":{"a":1}`) {
		t.Fatal(string(data), err)
	}
	other := openNavigationFixture(t, t.TempDir())
	if loc := navigationRequest(t, other, "GET", "/resume", "", 303).Header().Get("Location"); loc != "/research" {
		t.Fatal(loc)
	}
	if err := os.WriteFile(file, []byte(`{"version":2,"future":true}`), 0600); err != nil {
		t.Fatal(err)
	}
	if loc := navigationRequest(t, api, "GET", "/resume", "", 303).Header().Get("Location"); loc != "/research" {
		t.Fatal(loc)
	}
	navigationRequest(t, api, "POST", endpoint, `{"event":40,"route":"/lab"}`, 500)
	if data, err = os.ReadFile(file); err != nil || string(data) != `{"version":2,"future":true}` {
		t.Fatal(string(data), err)
	}
}

func TestWorkspaceRouteRecoveryKeepsCalendarDate(t *testing.T) {
	for _, tc := range []struct {
		name, route, want string
	}{
		{"leap day", "/tools?tab=calendar&date=2028-02-29", "/tools?date=2028-02-29&tab=calendar"},
		{"impossible day", "/tools?tab=calendar&date=2027-02-29", "/tools?tab=calendar"},
		{"malformed", "/tools?tab=calendar&date=2028-2-09", "/tools?tab=calendar"},
		{"zero year", "/tools?tab=calendar&date=0000-01-01", "/tools?tab=calendar"},
		{"repeated date", "/tools?tab=calendar&date=2028-02-29&date=2028-03-01", "/tools?tab=calendar"},
		{"other tab", "/tools?tab=discover&date=2028-02-29", "/tools?tab=discover"},
		{"other page", "/research?tab=calendar&view=tasks&date=2028-02-29", "/research?tab=calendar&view=tasks"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			root := t.TempDir()
			api := openNavigationFixture(t, root)
			body, err := json.Marshal(map[string]any{"event": 1, "route": tc.route})
			if err != nil {
				t.Fatal(err)
			}
			navigationRequest(t, api, "POST", "/api/workspace/navigation", string(body), http.StatusNoContent)
			api = openNavigationFixture(t, root)
			restored := navigationRequest(t, api, "GET", "/resume", "", http.StatusSeeOther)
			if got := restored.Header().Get("Location"); got != tc.want {
				t.Fatalf("restored %q, want %q", got, tc.want)
			}
		})
	}
}

func TestWorkspaceResolutionFallsBackBeforeDomainLoads(t *testing.T) {
	api := openNavigationFixture(t, t.TempDir())
	projectResp := navigationRequest(t, api, "POST", "/api/research/projects", `{"name":"Navigation fixture"}`, 201)
	var p research.Project
	if err := json.Unmarshal(projectResp.Body.Bytes(), &p); err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct{ path, expected string }{
		{"/reader?project=missing&paper=absent", "/research?view=projects"},
		{"/lab?project=missing", "/research?view=projects"},
		{"/studio?project=missing", "/research?view=projects"},
		{"/reader?project=" + p.ID + "&paper=absent", "/research?view=papers&project=" + p.ID},
	} {
		result := navigationRequest(t, api, "GET", tc.path, "", 307)
		if got := result.Header().Get("Location"); got != tc.expected {
			t.Errorf("%s: %s", tc.path, got)
		}
	}
	config := navigationRequest(t, api, "GET", "/api/research/modules?project="+p.ID, "", 200)
	var state struct{ Revision string }
	if err := json.Unmarshal(config.Body.Bytes(), &state); err != nil {
		t.Fatal(err)
	}
	navigationRequest(t, api, "PATCH", "/api/research/modules?project="+p.ID, `{"action":"set","id":"ai-lab","enabled":false,"revision":"`+state.Revision+`"}`, 200)
	result := navigationRequest(t, api, "GET", "/lab?project="+p.ID, "", http.StatusTemporaryRedirect)
	if result.Header().Get("Location") != "/research?project="+p.ID {
		t.Fatal(result.Header())
	}
	navigationRequest(t, api, "DELETE", "/api/research/projects/"+p.ID+"?revision="+strconv.Itoa(p.Revision), "", 204)
	if dest := navigationRequest(t, api, "GET", "/lab?project="+p.ID, "", 307).Header().Get("Location"); dest != "/research?view=projects" {
		t.Fatal(dest)
	}

}

func TestWorkspaceAIScopesFollowModuleSettings(t *testing.T) {
	instance, err := startWorkspace(t.TempDir(), 0, false, true)
	if err != nil {
		t.Fatal(err)
	}
	defer instance.close()
	api := instance.api
	p := scienceWorkflowDecode[research.Project](t, navigationRequest(t, api, "POST", "/api/research/projects", `{"name":"Module fixture"}`, 201).Body.Bytes())
	room := scienceWorkflowDecode[struct{ ID string }](t, navigationRequest(t, api, "POST", "/api/studio/sessions",
		`{"topic":"Synthetic project discussion","seats":["codex"],"project_id":"`+p.ID+`"}`, 201).Body.Bytes())
	global := scienceWorkflowDecode[struct{ ID string }](t, navigationRequest(t, api, "POST", "/api/studio/sessions",
		`{"topic":"Synthetic global discussion","seats":["codex"],"scope":"global"}`, 201).Body.Bytes())
	set := func(project string, enabled bool) {
		t.Helper()
		path := "/api/research/modules"
		if project != "" {
			path += "?project=" + project
		}
		config := scienceWorkflowDecode[struct{ Revision string }](t, navigationRequest(t, api, "GET", path, "", 200).Body.Bytes())
		navigationRequest(t, api, "PATCH", path, `{"action":"set","id":"ai-lab","enabled":`+strconv.FormatBool(enabled)+`,"revision":"`+config.Revision+`"}`, 200)
	}
	check := func(path, expected string) {
		t.Helper()
		target, err := url.Parse(path)
		if err != nil {
			t.Fatal(err)
		}
		result, err := api.resolveWorkspaceRoute(target)
		if err != nil || result != expected {
			t.Fatalf("%s: got %q, %v; want %q", path, result, err, expected)
		}
	}
	editScope := cliedit.Scope{ProjectID: p.ID, Directory: p.Path, MeetingID: room.ID}
	if err := api.checkEditScope(editScope); err != nil {
		t.Fatal(err)
	}
	set(p.ID, false)
	if err := api.checkEditScope(editScope); !errors.Is(err, meeting.ErrAIDisabled) {
		t.Fatalf("disabled project edit: %v", err)
	}
	for _, path := range []string{"/studio?project=" + p.ID, "/lab?project=" + p.ID, "/lab?run=" + room.ID, "/studio?session=" + room.ID} {
		check(path, "/research?project="+p.ID)
	}
	check("/studio?session="+global.ID, "/studio?session="+global.ID)
	check("/studio?view=settings&project="+p.ID, "/studio?view=settings&project="+p.ID)
	check("/studio?view=plugins", "/studio?view=plugins")
	navigationRequest(t, api, "POST", "/api/studio/sessions/"+room.ID+"/run", `{"expected_round":0}`, 409)
	navigationRequest(t, api, "POST", "/api/studio/sessions", `{"topic":"Synthetic project discussion","project_id":"`+p.ID+`","seats":["codex"]}`, 409)
	set("", false)
	for _, path := range []string{"/studio", "/lab", "/studio?scope=global", "/lab?run=" + global.ID} {
		check(path, "/research")
	}
	set(p.ID, true)
	check("/studio?session="+room.ID, "/studio?project="+p.ID+"&session="+room.ID)
	check("/lab?run="+room.ID, "/lab?project="+p.ID+"&run="+room.ID)
}

func TestNavigationRestoresEvidenceLocatorsWithoutReplayingCommands(t *testing.T) {
	api := openNavigationFixture(t, t.TempDir())
	record := navigationRequest(t, api, "POST", "/api/research/projects", `{"name":"Evidence navigation fixture"}`, 201)
	var project research.Project
	if err := json.Unmarshal(record.Body.Bytes(), &project); err != nil {
		t.Fatal(err)
	}
	for i, route := range []string{
		"/research?view=materials&material=material-a&offset=13&end=25&fingerprint=source",
		"/research?view=notes&note=note-a&offset=4&end=16&revision=2&line=2&column=1",
	} {
		original, err := url.Parse(route + "&project=" + project.ID)
		if err != nil {
			t.Fatal(err)
		}
		body, _ := json.Marshal(map[string]any{"event": i + 1, "route": original.String() + "&command=newProject"})
		navigationRequest(t, api, "POST", "/api/workspace/navigation", string(body), 204)
		restored, err := url.Parse(navigationRequest(t, api, "GET", "/resume", "", 303).Header().Get("Location"))
		if err != nil || restored.Path != original.Path || restored.Query().Encode() != original.Query().Encode() {
			t.Fatalf("restored %v, want %v", restored, original)
		}
	}
}
