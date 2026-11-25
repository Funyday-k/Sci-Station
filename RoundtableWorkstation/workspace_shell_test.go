package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

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
		for _, component := range []string{"<!doctype html>", `class="workspace-bar"`, "<nav data-workspace-nav ", `data-workspace-surface="` + surface.name + `"`, `src="/static/workspace-nav.js"`} {
			if strings.Count(page, component) != 1 {
				t.Errorf("%s: missing or duplicate %s", route, component)
			}
		}
		if strings.Contains(page, "{{template") || strings.Contains(page, "<iframe") {
			t.Errorf("%s: unmounted domain", route)
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
