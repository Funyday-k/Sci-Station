package desktop

import (
	"context"
	"encoding/json"
	"errors"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"

	"scistation.local/desktop/internal/meeting"
)

func TestStudioSettingsAndVersionedFileThroughHTTP(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "settings.json"), []byte(`{"appearance":"light","allow_edits":true}`), 0600); err != nil {
		t.Fatal(err)
	}
	store, err := openSettings(dir)
	if err != nil {
		t.Fatal(err)
	}
	engine, err := meeting.New(t.TempDir(), func(context.Context, string, string, string, string) (string, error) {
		t.Error("file operations must not call a model")
		return "", nil
	}, func() meeting.Settings { return store.get().Settings })
	if err != nil {
		t.Fatal(err)
	}
	host := openNavigationFixture(t, t.TempDir())
	host.meetings, host.prefs = engine, store
	api := host.serve(8765)
	do := func(method, path, body string, trusted bool) *httptest.ResponseRecorder {
		req := httptest.NewRequest(method, "http://127.0.0.1:8765"+path, strings.NewReader(body))
		if trusted {
			req.Header.Set("X-Roundtable", "1")
			req.Header.Set("Content-Type", "application/json")
		}
		w := httptest.NewRecorder()
		api.ServeHTTP(w, req)
		return w
	}
	if w := do("POST", "/api/studio/settings", `{"appearance":"dark"}`, false); w.Code != 403 {
		t.Fatal(w.Code)
	}
	if w := do("GET", "/api/studio/settings", "", false); w.Code != 200 || !strings.Contains(w.Body.String(), `"color_theme":"iris"`) || !strings.Contains(w.Body.String(), `"text_size":"standard"`) || !strings.Contains(w.Body.String(), `"allow_edits":false`) {
		t.Fatal(w.Body)
	}
	if w := do("POST", "/api/studio/settings", `{"color_theme":"teal","models":{"codex":"sample"},"allow_edits":true}`, true); w.Code != 200 || !strings.Contains(w.Body.String(), `"appearance":"light"`) || !strings.Contains(w.Body.String(), `"allow_edits":false`) {
		t.Fatal(w.Body)
	}
	if w := do("POST", "/api/studio/settings", `{"text_size":"extra-large"}`, true); w.Code != 200 {
		t.Fatal(w.Body)
	}
	if w := do("POST", "/api/studio/settings", `{"appearance":"dark"}`, true); w.Code != 200 {
		t.Fatal(w.Body)
	}
	if w := do("POST", "/api/studio/settings", `{"color_theme":"unknown"}`, true); w.Code != 400 {
		t.Fatal(w.Body)
	}
	if w := do("POST", "/api/studio/settings", `{"text_size":"tiny"}`, true); w.Code != 400 {
		t.Fatal(w.Body)
	}
	if w := do("POST", "/api/studio/settings", `{"max_children":100,"models":{"codex":"wrong"}}`, true); w.Code != 400 {
		t.Fatal(w.Body)
	}
	loaded, err := openSettings(filepath.Dir(store.file))
	if err != nil {
		t.Fatal(err)
	}
	if p := loaded.get(); p.Appearance != "dark" || p.ColorTheme != "teal" || p.TextSize != "extra-large" || p.Models["codex"] != "sample" || p.Models["cursor"] == "" || p.AllowEdits {
		t.Fatal(p)
	}
	project, err := os.MkdirTemp("/private/tmp", "roundtable-api-")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(project)
	testMeetingProject(t, host, project)
	create, _ := json.Marshal(map[string]string{"topic": "Choose a project", "project": project})
	w := do("POST", "/api/studio/sessions", string(create), true)
	if w.Code != 201 {
		t.Fatal(w.Body)
	}
	var s meeting.Session
	if err = json.Unmarshal(w.Body.Bytes(), &s); err != nil {
		t.Fatal(err)
	}
	prefix := "/api/studio/sessions/" + s.ID
	if w = do("POST", prefix+"/file", `{"path":"meeting.md","text":"first\n","version":"missing"}`, true); w.Code != 200 {
		t.Fatal(w.Body)
	}
	if w = do("POST", prefix+"/file", `{"path":"meeting.md","text":"stale\n","version":"missing"}`, true); w.Code != 409 {
		t.Fatal(w.Body)
	}
	if w = do("GET", prefix+"/file?path=meeting.md", "", false); w.Code != 200 || !strings.Contains(w.Body.String(), `first\n`) {
		t.Fatal(w.Body)
	}
	b, err := os.ReadFile(filepath.Join(project, "meeting.md"))
	if err != nil || string(b) != "first\n" {
		t.Fatalf("%q %v", b, err)
	}
}

func TestStudioTitleExplicitPOSTPersistsAndGETDoesNotGenerate(t *testing.T) {
	store, err := openSettings(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	var calls atomic.Int32
	var namedSeat atomic.Value
	engine, err := meeting.New(t.TempDir(), func(_ context.Context, seat, _, _, _ string) (string, error) {
		calls.Add(1)
		namedSeat.Store(seat)
		return "共享修改的审阅", nil
	}, func() meeting.Settings { return store.get().Settings })
	if err != nil {
		t.Fatal(err)
	}
	host := openNavigationFixture(t, t.TempDir())
	host.meetings, host.prefs = engine, store
	api := host.serve(8765)
	do := func(method, path, body string, trusted bool) *httptest.ResponseRecorder {
		r := httptest.NewRequest(method, "http://127.0.0.1:8765"+path, strings.NewReader(body))
		if trusted {
			r.Header.Set("X-Roundtable", "1")
			r.Header.Set("Content-Type", "application/json")
		}
		w := httptest.NewRecorder()
		api.ServeHTTP(w, r)
		return w
	}
	project, err := os.MkdirTemp("/private/tmp", "roundtable-title-api-")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(project)
	const topic = "Keep the complete original task, including its detailed constraints."
	testMeetingProject(t, host, project)
	body, _ := json.Marshal(map[string]any{"topic": topic, "project": project, "seats": []string{"cursor", "codex"}})
	w := do("POST", "/api/studio/sessions", string(body), true)
	if w.Code != 201 {
		t.Fatal(w.Body)
	}
	var created struct{ ID string }
	if err := json.Unmarshal(w.Body.Bytes(), &created); err != nil {
		t.Fatal(err)
	}
	prefix := "/api/studio/sessions/" + created.ID
	for _, path := range []string{"/api/studio/sessions", prefix} {
		if w := do("GET", path, "", false); w.Code != 200 {
			t.Fatalf("read %s: %d %s", path, w.Code, w.Body)
		}
	}
	if w := do("GET", prefix+"/title", "", false); w.Code != 405 || w.Header().Get("Allow") != "POST" {
		t.Fatalf("title GET = %d %v", w.Code, w.Header())
	}
	if calls.Load() != 0 {
		t.Fatal("create/list/get generated a title")
	}
	for _, request := range []struct {
		body    string
		trusted bool
		status  int
	}{{"{}", false, 403}, {"", true, 400}, {"null", true, 400}, {"[]", true, 400}, {`{"title":"local replacement"}`, true, 400}, {"{} {}", true, 400}} {
		if w := do("POST", prefix+"/title", request.body, request.trusted); w.Code != request.status {
			t.Errorf("title body %q trusted=%v = %d %s", request.body, request.trusted, w.Code, w.Body)
		}
	}
	r := httptest.NewRequest("POST", "http://127.0.0.1:8765"+prefix+"/title", strings.NewReader("{}"))
	r.Header.Set("X-Roundtable", "1")
	r.Header.Set("Content-Type", "application/json")
	r.Header.Set("Origin", "http://localhost:8765")
	w = httptest.NewRecorder()
	api.ServeHTTP(w, r)
	if w.Code != 403 || calls.Load() != 0 {
		t.Fatalf("source/JSON guards invoked model: status=%d calls=%d", w.Code, calls.Load())
	}
	for range 2 {
		w := do("POST", prefix+"/title", "{}", true)
		if w.Code != 200 {
			t.Fatal(w.Body)
		}
		var response map[string]string
		if err := json.Unmarshal(w.Body.Bytes(), &response); err != nil || response["title"] != "共享修改的审阅" || len(response) != 1 {
			t.Fatalf("title response: %v %v", response, err)
		}
	}
	if calls.Load() != 1 || namedSeat.Load() != "cursor" {
		t.Fatalf("title call count=%d first seat=%v", calls.Load(), namedSeat.Load())
	}
	w = do("GET", prefix, "", false)
	var saved map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &saved); err != nil || saved["title"] != "共享修改的审阅" || saved["topic"] != topic {
		t.Fatalf("persisted title/topic: %v %v", saved, err)
	}
	w = do("GET", "/api/studio/sessions", "", false)
	var listing struct{ Sessions []map[string]any }
	if err := json.Unmarshal(w.Body.Bytes(), &listing); err != nil || len(listing.Sessions) != 1 || listing.Sessions[0]["title"] != "共享修改的审阅" || listing.Sessions[0]["topic"] != topic {
		t.Fatalf("summary title/topic: %v %v", listing, err)
	}
	if calls.Load() != 1 {
		t.Fatal("subsequent GET invoked the model")
	}
}

func TestStudioTitleHTTPReportsMissingFailureAndShutdown(t *testing.T) {
	store, err := openSettings(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	var calls atomic.Int32
	engine, err := meeting.New(t.TempDir(), func(context.Context, string, string, string, string) (string, error) {
		calls.Add(1)
		return "", errors.New("fake CLI unavailable")
	}, func() meeting.Settings { return store.get().Settings })
	if err != nil {
		t.Fatal(err)
	}
	project, err := os.MkdirTemp("/private/tmp", "roundtable-title-errors-")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(project)
	session, err := engine.Create("Original task", project, []string{"codex"})
	if err != nil {
		t.Fatal(err)
	}
	api := (&apiServer{prefs: store, meetings: engine}).serve(8765)
	post := func(id string) *httptest.ResponseRecorder {
		r := httptest.NewRequest("POST", "http://127.0.0.1:8765/api/studio/sessions/"+id+"/title", strings.NewReader("{}"))
		r.Header.Set("X-Roundtable", "1")
		r.Header.Set("Content-Type", "application/json")
		w := httptest.NewRecorder()
		api.ServeHTTP(w, r)
		return w
	}
	if w := post(strings.Repeat("0", 32)); w.Code != 404 || calls.Load() != 0 {
		t.Fatalf("missing session = %d calls=%d", w.Code, calls.Load())
	}
	if w := post(session.ID); w.Code != 502 || calls.Load() != 1 || strings.Contains(w.Body.String(), "fake CLI") {
		t.Fatalf("failed title = %d calls=%d %s", w.Code, calls.Load(), w.Body)
	}
	if err := engine.Shutdown(context.Background()); err != nil {
		t.Fatal(err)
	}
	if w := post(session.ID); w.Code != 409 || calls.Load() != 1 {
		t.Fatalf("shutdown title = %d calls=%d %s", w.Code, calls.Load(), w.Body)
	}
}
