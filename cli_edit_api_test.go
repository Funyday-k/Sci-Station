package main

import (
	"context"
	"encoding/json"
	"net/http/httptest"
	"path/filepath"
	"scistation.local/desktop/internal/meeting"
	"scistation.local/desktop/internal/research"
	"strings"
	"testing"

	"scistation.local/desktop/internal/cliedit"
)

func TestCLIEditRequiresCurrentNativeView(t *testing.T) {
	a := &apiServer{desktop: true}
	access := func(proof string) int {
		r := httptest.NewRequest("GET", "http://127.0.0.1:8123/api/studio/sessions/one/cli-edits", nil)
		r.Header.Set("X-Roundtable", "1")
		r.Header.Set(cliEditHeader, proof)
		w := httptest.NewRecorder()
		a.serveCLIEdits(w, r, "one")
		return w.Code
	}
	if access("") != 403 || access("browser") != 403 {
		t.Fatal("loopback browser could see CLI controls")
	}
	script := a.cliEditWindowScript("http://127.0.0.1:8123")
	if !strings.Contains(script, `location.pathname!=="/studio"`) || !strings.Contains(script, `window.top!==window`) || !strings.Contains(script, `location.origin!=="http://127.0.0.1:8123"`) {
		t.Fatal("native proof injection was not scoped")
	}
	proof := a.cliEdits.windowProof
	if proof == "" || access(proof) != 503 {
		t.Fatal("native proof not recognized")
	}
	_ = a.cliEditWindowScript("http://127.0.0.1:8123")
	if access(proof) != 403 {
		t.Fatal("previous navigation retained authority")
	}
	proof = a.cliEdits.windowProof
	a.forgetCLIEditWindow()
	if access(proof) != 403 {
		t.Fatal("closed root retained authority")
	}
	a.desktop = false
	if a.cliEditWindowScript("http://127.0.0.1:8123") != "" {
		t.Fatal("headless issued proof")
	}
}
func TestCLIEditAPIUsesRecordedMeetingAndExactNativeRequest(t *testing.T) {
	dir, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	// Exercise the real host router and research/meeting stores. Only the CLI
	// transport is a fixture. Its answer cannot be produced by a loopback client.
	host, shutdown := newCLIEditTestHost(t, dir)
	defer shutdown()
	ctx := context.Background()
	_ = host.cliEditWindowScript("http://127.0.0.1:8123")
	type op = map[string]any
	call := func(method, path string, value any, status int) op {
		t.Helper()
		b, err := json.Marshal(value)
		if err != nil {
			t.Fatal(err)
		}
		req := httptest.NewRequest(method, "http://127.0.0.1:8123"+path, strings.NewReader(string(b)))
		req.Header.Set("X-Roundtable", "1")
		req.Header.Set(cliEditHeader, host.cliEdits.windowProof)
		req.Header.Set("Content-Type", "application/json")
		out := httptest.NewRecorder()
		host.serve(8123).ServeHTTP(out, req)
		if out.Code != status {
			t.Fatalf("%s: got %d, want %d: %s", path, out.Code, status, out.Body.String())
		}
		var body op
		if err = json.Unmarshal(out.Body.Bytes(), &body); err != nil {
			t.Fatal(err)
		}
		return body
	}
	p := call("POST", "/api/research/projects", op{"name": "Approval fixture"}, 201)
	pid := p["id"].(string)
	session := call("POST", "/api/studio/sessions", op{"topic": "Proof", "project_id": pid, "seats": []string{"codex"}}, 201)
	id := session["id"].(string)
	adapter := func(ctx context.Context, _ string, scope cliedit.Scope, sink cliedit.Sink) error {
		if scope.MeetingID != id || scope.ProjectID != pid || scope.MeetingRound != 0 {
			return context.Canceled
		}
		if err := sink.Running("thread", "turn"); err != nil {
			return err
		}
		_, err := sink.Approval(ctx, cliedit.Request{ThreadID: "thread", TurnID: "turn", RequestID: "3", ItemID: "item", Changes: []cliedit.Change{{Path: "note.md", Kind: "add", Diff: "+fixture"}}})
		return err
	}
	host.cliEdits.lookup = func(_ context.Context, provider string) cliEditProvider {
		return cliEditProvider{ID: provider, Available: provider == "codex", run: adapter}
	}
	route := "/api/studio/sessions/" + id + "/cli-edits"
	call("POST", route, op{"action": "start", "projectId": "other", "provider": "codex", "meetingRound": 0, "prompt": "create", "paths": []string{"note.md"}}, 403)
	call("POST", route, op{"action": "start", "projectId": pid, "provider": "codex", "meetingRound": 0, "prompt": "create", "paths": []string{"../other"}}, 409)
	reply := call("POST", route, op{"action": "start", "projectId": pid, "provider": "codex", "meetingRound": 0, "prompt": "create", "paths": []string{"note.md"}}, 200)
	runID := reply["run"].(op)["id"].(string)
	defer host.cliEdits.jobs.Close(ctx)
	for attempts := 0; ; attempts++ {
		state := call("GET", route, nil, 200)["run"].(op)
		if state["status"] == "pending" {
			break
		}
		if attempts > 100 {
			t.Fatal("no pending review", state)
		}
	}
	decide := op{"action": "accept", "projectId": pid, "runId": runID, "threadId": "thread", "turnId": "turn", "requestId": "stale", "itemId": "item"}
	call("POST", route, decide, 409)
	decide["requestId"] = "3"
	decide["action"] = "decline"
	call("POST", route, decide, 200)
	call("POST", route, decide, 409)
}

func newCLIEditTestHost(t *testing.T, dir string) (*apiServer, func()) {
	t.Helper()
	prefs, err := openSettings(dir)
	if err != nil {
		t.Fatal(err)
	}
	lab, err := research.New(filepath.Join(dir, "research"))
	if err != nil {
		t.Fatal(err)
	}
	engine, err := meeting.New(filepath.Join(dir, "studio"), func(context.Context, string, string, string, string) (string, error) {
		t.Error("used model")
		return "", context.Canceled
	}, func() meeting.Settings { return prefs.get().Settings })
	if err != nil {
		t.Fatal(err)
	}
	return &apiServer{desktop: true, meetings: engine, research: lab, prefs: prefs}, func() { _ = engine.Shutdown(context.Background()) }
}
