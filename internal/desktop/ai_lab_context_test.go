package desktop

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"scistation.local/desktop/internal/research"
)

const labSkillFixture = "---\nname: reduce-error\ndescription: Estimate the numerical uncertainty.\nauthor: Fixture\nrisk: readOnly\ncapabilities: [convergence, uncertainty]\nallowed_tools: [read_note]\n---\n\nCheck numerical convergence before reporting the estimate.\n"

func labSettingsFixture(t *testing.T) (*apiServer, string, research.Project, research.Project) {
	t.Helper()
	dir := t.TempDir()
	prefs, err := openSettings(dir)
	if err != nil {
		t.Fatal(err)
	}
	lab, err := research.New(dir)
	if err != nil {
		t.Fatal(err)
	}
	api := &apiServer{prefs: prefs, research: lab}
	create := func(name string) research.Project {
		r := httptest.NewRequest(http.MethodPost, "/api/research/projects", strings.NewReader(fmt.Sprintf(`{"name":%q}`, name)))
		w := httptest.NewRecorder()
		lab.ServeHTTP(w, r)
		if w.Code != 201 {
			t.Fatalf("create project: %d %s", w.Code, w.Body.String())
		}
		return scienceWorkflowDecode[research.Project](t, w.Body.Bytes())
	}
	return api, dir, create("Test project"), create("Other project")
}

func labContextRequest(t *testing.T, api *apiServer, method, path string, body any, status int) []byte {
	t.Helper()
	raw, err := json.Marshal(body)
	if err != nil {
		t.Fatal(err)
	}
	rec := labTestRequest(t, api, method, path, string(raw))
	if rec.Code != status {
		t.Fatalf("%s %s: %d want %d: %s", method, path, rec.Code, status, rec.Body.String())
	}
	return rec.Body.Bytes()
}

func TestLabMarkdownSkillRequiresReviewTrustAndEnable(t *testing.T) {
	api, dir, p, q := labSettingsFixture(t)
	read := func(project string) labContextResponse {
		return scienceWorkflowDecode[labContextResponse](t, labContextRequest(t, api, "GET", "context?project="+project, nil, 200))
	}
	preview := scienceWorkflowDecode[research.LabSkillText](t, labContextRequest(t, api, "POST", "context/preview",
		labContextEdit{ProjectID: p.ID, Markdown: labSkillFixture}, 200))
	if preview.ID != "reduce-error" || len(preview.Digest) != 64 || len(preview.Capabilities) != 2 ||
		!strings.HasPrefix(preview.Body, "Check numerical convergence") || len(read(p.ID).Skills) != 0 {
		t.Fatalf("preview not read-only or invalid: %+v", preview)
	}
	edit := labContextEdit{ProjectID: p.ID, Revision: 1, Operation: "install", ID: preview.ID, Digest: preview.Digest, Markdown: labSkillFixture}
	labContextRequest(t, api, "PATCH", "context", edit, 403)
	edit.Confirmed = true
	edit.Markdown += "Changed after review."
	labContextRequest(t, api, "PATCH", "context", edit, 409)
	edit.Markdown = labSkillFixture
	labContextRequest(t, api, "PATCH", "context", edit, 200)
	labContextRequest(t, api, "PATCH", "context", edit, 409)
	got := read(p.ID)
	if got.Revision != 2 || len(got.Skills) != 1 || got.Skills[0].Body != "" || got.Skills[0].Enabled || got.Skills[0].Trusted {
		t.Fatalf("installed state: %+v", got)
	}
	ref := labContextEdit{ProjectID: p.ID, ID: preview.ID, Digest: preview.Digest}
	labContextRequest(t, api, "POST", "context/resolve", ref, 409)
	labContextRequest(t, api, "POST", "context/skill", ref, 200)
	edit = ref
	edit.Confirmed, edit.Revision, edit.Operation, edit.Value = true, 2, "enable", true
	labContextRequest(t, api, "PATCH", "context", edit, 200)
	labContextRequest(t, api, "POST", "context/resolve", ref, 409)
	edit.Revision, edit.Operation = 3, "trust"
	labContextRequest(t, api, "PATCH", "context", edit, 200)
	resolved := scienceWorkflowDecode[research.LabSkillText](t, labContextRequest(t, api, "POST", "context/resolve", ref, 200))
	if resolved.Body != preview.Body || resolved.Digest != preview.Digest {
		t.Fatal(resolved)
	}
	ref.ProjectID = q.ID
	labContextRequest(t, api, "POST", "context/resolve", ref, 409)
	if len(read(q.ID).Skills) != 0 {
		t.Fatal("skill settings leaked to another project")
	}
	lab, err := research.New(dir)
	if err != nil {
		t.Fatal(err)
	}
	api.research = lab
	ref.ProjectID = p.ID
	labContextRequest(t, api, "POST", "context/resolve", ref, 200)
	edit.Revision, edit.Value = 4, false
	labContextRequest(t, api, "PATCH", "context", edit, 200)
	labContextRequest(t, api, "POST", "context/resolve", ref, 409)
	edit.Revision, edit.Operation = 5, "remove"
	labContextRequest(t, api, "PATCH", "context", edit, 200)
	if len(read(p.ID).Skills) != 0 {
		t.Fatal("removed skill remained visible")
	}
}

func TestLabMarkdownSkillRejectsNonTextCapabilitiesAndSecretLikeContent(t *testing.T) {
	api, _, p, _ := labSettingsFixture(t)
	for _, body := range []string{
		strings.Replace(labSkillFixture, "readOnly", "runsCode", 1),
		labSkillFixture + "-----BEGIN " + "PRIVATE KEY-----",
		strings.Replace(labSkillFixture, "reduce-error", "../another", 1),
		labSkillFixture + strings.Repeat("界", 64<<10),
	} {
		labContextRequest(t, api, "POST", "context/preview", labContextEdit{ProjectID: p.ID, Markdown: body}, 422)
	}
}

func TestLabMCPProjectSettingsScopeConsentAndFailureFallback(t *testing.T) {
	api, dir, p, q := labSettingsFixture(t)
	const endpoint = "https://public-fixture.example/mcp"
	edit := labContextEdit{Operation: "mcp", ProjectID: p.ID, Revision: 1, Value: true, Endpoint: endpoint + "?token=placeholder", Confirmed: true}
	labContextRequest(t, api, "PATCH", "context", edit, 422)
	edit.Endpoint, edit.Confirmed = endpoint, false
	labContextRequest(t, api, "PATCH", "context", edit, 403)
	edit.Confirmed = true
	config := scienceWorkflowDecode[labContextResponse](t, labContextRequest(t, api, "PATCH", "context", edit, 200))
	if !config.MCPEnabled || config.Endpoint != endpoint || config.Revision != 2 {
		t.Fatal(config)
	}
	calls := 0
	client := &http.Client{Transport: labTestTransport(func(w http.ResponseWriter, r *http.Request) {
		calls++
		var msg struct {
			Method string
		}
		if err := json.NewDecoder(r.Body).Decode(&msg); err != nil || msg.Method != "initialize" {
			t.Errorf("unexpected MCP fixture request")
		}
		http.Error(w, "fixture service unavailable", http.StatusServiceUnavailable)
	})}
	resources := func(project string, revision int, confirmed bool, status int) {
		t.Helper()
		body, err := json.Marshal(map[string]any{"projectId": project, "revision": revision, "confirmed": confirmed, "endpoint": endpoint})
		if err != nil {
			t.Fatal(err)
		}
		r := httptest.NewRequest("POST", "/api/research/lab/resources/list", bytes.NewReader(body))
		w := httptest.NewRecorder()
		api.serveLabResources(w, r, "resources/list", client)
		if w.Code != status {
			t.Fatalf("resources: %d want %d: %s", w.Code, status, w.Body.String())
		}
	}
	resources(q.ID, 1, true, 403)
	resources(p.ID, 1, true, 409)
	resources(p.ID, 2, false, 403)
	if calls != 0 {
		t.Fatal("unapproved resource attempted a connection")
	}
	resources(p.ID, 2, true, 422)
	if calls != 1 {
		t.Fatal("server error should stop lookup", calls)
	}
	lab, err := research.New(dir)
	if err != nil {
		t.Fatal(err)
	}
	api.research = lab
	persisted := scienceWorkflowDecode[labContextResponse](t, labContextRequest(t, api, "GET", "context?project="+p.ID, nil, 200))
	if persisted.Endpoint != endpoint || !persisted.MCPEnabled || persisted.Revision != 2 {
		t.Fatal("connection failure modified project settings", persisted)
	}
	edit.Revision, edit.Value = 2, false
	labContextRequest(t, api, "PATCH", "context", edit, 200)
	resources(p.ID, 3, true, 403)
	if calls != 1 {
		t.Fatal("disabled resource attempted a connection")
	}
}
