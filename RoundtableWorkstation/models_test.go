package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"scistation.local/desktop/internal/deliberation"
	"scistation.local/desktop/internal/gateway"
	"scistation.local/desktop/internal/meeting"
)

func TestStudioManagedCatalogAndRequests(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(home, ".config"))
	write := func(name, contents string) {
		t.Helper()
		if err := os.MkdirAll(filepath.Dir(name), 0700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(name, []byte(contents), 0600); err != nil {
			t.Fatal(err)
		}
	}
	spec := filepath.Join(home, "Demo.app", "Contents", "Resources", "sci-station.agent.js")
	write(spec, "// fixture")
	registry := filepath.Join(home, ".config", "magpie", "plugins.json")
	write(registry, `{"plugins":[{"spec":"`+spec+`"}]}`)
	connection := filepath.Join(home, ".config", "sci-station", "connection.json")
	var postCount atomic.Int32
	var auth atomic.Value
	auth.Store("")
	started := make(chan struct{})
	const modelJSON = `{"data":[
	  {"id":"reviewers","owned_by":"group","supported_reasoning_levels":[{"effort":"low"}]},
	  {"id":"work/alpha","display_name":"Alpha","owned_by":"work","native_endpoints":["/v1/responses"],"reasoning_levels":["medium","high"]},
	  {"id":"work/beta","display_name":"Beta","owned_by":"work","native_endpoints":["/v1/messages"]},
	  {"id":"codex/sample","native_endpoints":["/v1/responses"]},
	  {"id":"cursor/sample","native_endpoints":["/v1/chat/completions"]},
	  {"id":"work/picture","kind":"image"}
	]}`
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		auth.Store(r.Header.Get("Authorization"))
		if r.Method == "GET" && r.URL.Path == "/v1/models" {
			io.WriteString(w, modelJSON)
			return
		}
		postCount.Add(1)
		var body map[string]any
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Error(err)
			return
		}
		model, _ := body["model"].(string)
		switch model {
		case "work/alpha", "codex/sample":
			if r.URL.Path != "/v1/responses" {
				t.Errorf("responses model sent to %s", r.URL.Path)
			}
			if model == "work/alpha" && (body["instructions"] != "test instructions" || body["reasoning"].(map[string]any)["effort"] != "high") {
				t.Errorf("responses fields: %v", body)
			}
			io.WriteString(w, `{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"ready"}]}]}`)
		case "reviewers", "work/beta", "cursor/sample":
			if r.URL.Path != "/v1/chat/completions" {
				t.Errorf("chat model sent to %s", r.URL.Path)
			}
			if model == "reviewers" && body["reasoning_effort"] != "low" {
				t.Errorf("lost routed effort %v", body)
			}
			if model == "work/beta" && body["reasoning_effort"] != nil {
				t.Error("auto effort was sent")
			}
			msgs := body["messages"].([]any)
			last := msgs[len(msgs)-1].(map[string]any)["content"]
			if last == "wait" {
				close(started)
				<-r.Context().Done()
				return
			}
			io.WriteString(w, `{"choices":[{"finish_reason":"stop","message":{"content":"ready"}}]}`)
		default:
			t.Errorf("unexpected model request %q", model)
		}
	}))
	defer upstream.Close()
	connect := func(model string, legacyKey string) {
		fields := map[string]string{"baseURL": upstream.URL + "/v1", "model": model}
		if legacyKey != "" {
			fields["gatewayKey"] = legacyKey
		}
		b, err := json.Marshal(fields)
		if err != nil {
			t.Fatal(err)
		}
		write(connection, string(b))
	}
	connect("reviewers", "")
	store, err := openSettings(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	a := &apiServer{prefs: store}
	w := httptest.NewRecorder()
	a.models(w, httptest.NewRequest("GET", "/api/studio/models", nil))
	var c gateway.Catalog
	if err = json.Unmarshal(w.Body.Bytes(), &c); w.Code != 200 || err != nil || c.DefaultModel != "reviewers" || len(c.Models) != 5 || strings.Contains(w.Body.String(), "fixture-") {
		t.Fatalf("catalog response %v %d", err, w.Code)
	}
	if !slices.Equal(c.Models[0].Efforts, []string{"auto", "low"}) || !slices.Equal(c.Models[2].Efforts, []string{"auto"}) {
		t.Fatal(c.Models)
	}
	if postCount.Load() != 0 || auth.Load() != "Bearer magpie-sci-station" {
		t.Fatal("catalog used the wrong key or called a model")
	}
	validated, err := a.validateMembers(context.Background(), []meeting.Member{{ID: "forged", Model: "work/alpha", Source: "fake", Label: "fake", Effort: "high"}, {Model: "work/beta"}, {Model: "reviewers", Effort: "low"}})
	if err != nil || validated[0].ID != "" || validated[0].Label != "Alpha" || validated[0].Source != "work" || validated[1].Effort != "auto" {
		t.Fatalf("validation %v %v", validated, err)
	}
	if _, err = a.validateMembers(context.Background(), []meeting.Member{{Model: "work/beta", Effort: "high"}}); err == nil {
		t.Fatal("accepted an unsupported effort")
	}
	g := studioGateway(store)
	connect("work/alpha", "magpie-sci-station")
	c, err = g.Catalog(context.Background())
	if err != nil || c.DefaultModel != "work/alpha" || auth.Load() != "Bearer magpie-sci-station" {
		t.Fatal("cached agent config", err)
	}
	for _, m := range validated {
		res, err := g.Generate(context.Background(), m.Model, m.Effort, "test instructions", "test prompt", "test-session")
		if err != nil || res != "ready" {
			t.Fatalf("model %s: %v %q", m.Model, err, res)
		}
	}
	call := gatewayCall(g)
	for _, seat := range []string{"codex", "cursor"} {
		if _, err := call(deliberation.WithInstructions(context.Background(), "protocol"), seat, "sample", "prompt", "unused"); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := call(context.Background(), "cursor", "missing", "prompt", "unused"); err == nil {
		t.Fatal("substituted a missing legacy seat")
	}
	if postCount.Load() != 5 {
		t.Fatal("unexpected request count", postCount.Load())
	}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { _, err := g.Generate(ctx, "work/beta", "auto", "", "wait", "cancel"); done <- err }()
	select {
	case <-started:
	case <-time.After(time.Second):
		cancel()
		t.Fatal("mock did not receive cancellable request")
	}
	cancel()
	select {
	case err := <-done:
		if !errors.Is(err, context.Canceled) {
			t.Fatal(err)
		}
	case <-time.After(time.Second):
		t.Fatal("request did not cancel")
	}
	connect("work/alpha", "fixture-private-key")
	auth.Store("")
	if _, err = g.Catalog(context.Background()); err == nil || strings.Contains(err.Error(), "fixture-private-key") || auth.Load() != "" {
		t.Fatal("unexpected request or credential disclosure for an unsupported connection")
	}
	connect("work/alpha", "")
	write(registry, `{"plugins":[{"spec":"`+spec+`","off":true}]}`)
	w = httptest.NewRecorder()
	a.models(w, httptest.NewRequest("GET", "/api/studio/models", nil))
	if w.Code != 502 || strings.Contains(w.Body.String(), "fixture-") {
		t.Fatalf("stale connection: status %d", w.Code)
	}
	if _, err = g.Generate(context.Background(), "work/beta", "auto", "", "test", "disconnected"); err == nil || postCount.Load() != 6 {
		t.Fatal("disconnected agent still used the gateway")
	}
}

// Exercise the same HTTP routes and gateway adapter used by the desktop window.
func TestStudioModelMembersThroughHTTP(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	t.Setenv("XDG_CONFIG_HOME", t.TempDir())
	const model = "one/model"
	var parentStep, posts atomic.Int32
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/v1/models" {
			io.WriteString(w, `{"data":[{"id":"one/model","owned_by":"one","display_name":"Selected","reasoning_levels":["high"]}]}`)
			return
		}
		posts.Add(1)
		var payload struct {
			Model    string                           `json:"model"`
			Effort   string                           `json:"reasoning_effort"`
			Messages []struct{ Role, Content string } `json:"messages"`
		}
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			t.Error(err)
			return
		}
		if payload.Model != model || r.URL.Path != "/v1/chat/completions" || len(payload.Messages) == 0 {
			t.Error("wrong request")
			return
		}
		last := payload.Messages[len(payload.Messages)-1]
		var output string
		switch {
		case strings.HasPrefix(last.Content, "AGENDA DRAFT REQUEST"):
			if payload.Effort != "high" || !strings.Contains(last.Content, "Update this note") {
				t.Error("wrong draft context or chair")
			}
			output = `{"agenda":[{"title":"Check the revised note against the original","kind":"implementation"}]}`
		case strings.HasPrefix(last.Content, "TITLE REQUEST:"):
			if payload.Effort != "high" || len(payload.Messages) != 1 {
				t.Error("wrong title fields")
			}
			output = "Update the note"
		case strings.HasPrefix(last.Content, "PRIVATE TASK:"):
			if payload.Effort != "high" || !strings.Contains(payload.Messages[0].Content, "PRIVATE read-only child") {
				t.Error("wrong child request")
			}
			output = `{"action":"say","display_name":"Rhea","text":"private evidence"}`
		case payload.Effort == "high":
			actions := []string{`{"action":"read","path":"note.md"}`, `{"action":"delegate","name":"Ignored Parent Name","task":"inspect the note"}`, `{"action":"write","path":"note.md","text":"updated"}`, `{"action":"say","text":"Updated the note."}`}
			step := int(parentStep.Add(1)) - 1
			if step >= len(actions) {
				t.Error("unexpected parent step")
				return
			}
			output = actions[step]
		case payload.Effort == "":
			if !strings.Contains(last.Content, "updated") || strings.Contains(last.Content, "private evidence") {
				t.Error("second seat context mismatch")
			}
			output = `{"action":"say","text":"Verified the note."}`
		default:
			t.Error("unexpected effort")
			return
		}
		json.NewEncoder(w).Encode(map[string]any{"choices": []any{map[string]any{"finish_reason": "stop", "message": map[string]string{"content": output}}}})
	}))
	defer upstream.Close()
	store, err := openSettings(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	port, err := strconv.Atoi(strings.TrimPrefix(upstream.URL, "http://127.0.0.1:"))
	if err != nil {
		t.Fatal(err)
	}
	store.prefs.MagpiePort = port
	engine, err := meeting.New(t.TempDir(), gatewayCall(studioGateway(store)), func() meeting.Settings { return store.get().Settings })
	if err != nil {
		t.Fatal(err)
	}
	defer engine.Shutdown(context.Background())
	api := (&apiServer{prefs: store, meetings: engine}).serve(8765)
	do := func(method, path string, body any, want int) []byte {
		t.Helper()
		data, err := json.Marshal(body)
		if err != nil {
			t.Fatal(err)
		}
		req := httptest.NewRequest(method, "http://127.0.0.1:8765/api/studio/"+path, bytes.NewReader(data))
		req.Header.Set("X-Roundtable", "1")
		req.Header.Set("Content-Type", "application/json")
		w := httptest.NewRecorder()
		api.ServeHTTP(w, req)
		if w.Code != want {
			t.Fatalf("%s %s: %d %s", method, path, w.Code, w.Body)
		}
		return w.Body.Bytes()
	}
	dir, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	note := filepath.Join(dir, "note.md")
	if err = os.WriteFile(note, []byte("old"), 0600); err != nil {
		t.Fatal(err)
	}
	do("GET", "models", nil, 200)
	b := map[string]any{"topic": "Update this note", "project": dir, "preset": "work", "members": []map[string]string{{"model": model, "effort": "high", "label": "spoofed"}, {"model": model}}}
	var s meeting.Session
	if err = json.Unmarshal(do("POST", "sessions", b, 201), &s); err != nil {
		t.Fatal(err)
	}
	if s.AgendaDraftStatus != "drafting" || s.Members[0].Label != "Selected" || s.Members[1].ID != "member-2" {
		t.Fatal("bad initial state")
	}
	path := "sessions/" + s.ID
	for deadline := time.Now().Add(3 * time.Second); s.AgendaDraftStatus == "drafting" && time.Now().Before(deadline); {
		if err = json.Unmarshal(do("GET", path, nil, 200), &s); err != nil {
			t.Fatal(err)
		}
		time.Sleep(time.Millisecond)
	}
	if s.AgendaDraftStatus != "ready" || len(s.Agenda) != 1 || s.Agenda[0].Source != "chair" || len(s.Rounds) != 0 || posts.Load() != 1 {
		t.Fatalf("initial agenda missing: %+v", s)
	}
	do("POST", path+"/title", map[string]any{}, 200)
	do("POST", path+"/run", map[string]any{"expected_round": 0}, 202)
	for deadline := time.Now().Add(3 * time.Second); time.Now().Before(deadline); {
		if err = json.Unmarshal(do("GET", path, nil, 200), &s); err != nil {
			t.Fatal(err)
		}
		if s.Status != "running" {
			break
		}
		time.Sleep(5 * time.Millisecond)
	}
	if s.Status != "ready" || len(s.Rounds) != 1 || len(s.Rounds[0].Turns) != 2 || s.Title != "Update the note" {
		t.Fatalf("meeting failed: %v", s.Rounds)
	}
	ts := s.Rounds[0].Turns
	if len(ts[0].Children) != 1 || ts[0].Children[0].Effort != "high" || ts[0].Effort != "high" || ts[1].Effort != "auto" || len(ts[0].Changes) != 1 || posts.Load() != 8 {
		t.Fatalf("lost actions, members or efforts: %v", ts)
	}
	if ts[0].Children[0].Name != "Rhea" {
		t.Fatalf("lost the child name from the gateway response: %+v", ts[0].Children[0])
	}
	if data, err := os.ReadFile(note); err != nil || string(data) != "updated" {
		t.Fatal("missing project edit", err)
	}
	b["members"] = []map[string]string{{"model": model, "effort": "fake"}}
	do("POST", "sessions", b, 400)
	var roster struct {
		Members []meeting.Member `json:"members"`
	}
	if err := json.Unmarshal(do("GET", path+"/members", nil, 200), &roster); err != nil || len(roster.Members) != 2 || roster.Members[0].Model != model {
		t.Fatal(roster, err)
	}
	change := map[string]any{"seat_id": s.Seats[0], "model": "absent/model", "effort": "auto", "expected_version": 0}
	do("POST", path+"/members", change, 400)
	change["model"], change["effort"] = model, "fake"
	do("POST", path+"/members", change, 400)
	change["effort"] = "auto"
	var changed meeting.Session
	if err := json.Unmarshal(do("POST", path+"/members", change, 200), &changed); err != nil || changed.Members[0].Effort != "auto" || changed.Members[0].Version != 1 || changed.Members[0].Label != "Selected" || changed.Rounds[0].Turns[0].Effort != "high" || posts.Load() != 8 {
		t.Fatal(changed.Members, err)
	}
	change["effort"] = "high"
	var conflict struct {
		Session meeting.Session `json:"session"`
		Error   string          `json:"error"`
	}
	if err := json.Unmarshal(do("POST", path+"/members", change, 409), &conflict); err != nil || conflict.Error == "" || conflict.Session.ID != s.ID || conflict.Session.Members[0].Effort != "auto" {
		t.Fatal(conflict, err)
	}

}
