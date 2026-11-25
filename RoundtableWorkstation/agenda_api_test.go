package main

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"

	"scistation.local/desktop/internal/meeting"
)

func TestStudioAgendaActionsAndStaleRunThroughHTTP(t *testing.T) {
	e, err := meeting.New(t.TempDir(), func(context.Context, string, string, string, string) (string, error) {
		t.Error("agenda edits and stale runs must not call a model")
		return "", nil
	}, func() meeting.Settings { return meeting.Settings{} })
	if err != nil {
		t.Fatal(err)
	}
	project, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	s, err := e.CreateConfigured("Prepare a rollout", project, []meeting.Member{{Model: "fixture"}}, "review", meeting.AgendaInput{Title: "Review the plan"})
	if err != nil {
		t.Fatal(err)
	}
	handler := (&apiServer{meetings: e}).serve(8765)
	do := func(method, suffix string, data any, status int) *httptest.ResponseRecorder {
		t.Helper()
		body, err := json.Marshal(data)
		if err != nil {
			t.Fatal(err)
		}
		req := httptest.NewRequest(method, "http://127.0.0.1:8765/api/studio/sessions/"+s.ID+"/"+suffix, strings.NewReader(string(body)))
		req.Header.Set("X-Roundtable", "1")
		req.Header.Set("Content-Type", "application/json")
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)
		if rec.Code != status {
			t.Fatalf("%s %s: got %d want %d: %s", method, suffix, rec.Code, status, rec.Body.String())
		}
		return rec
	}
	if allow := do(http.MethodGet, "agenda", nil, 405).Header().Get("Allow"); allow != "POST" {
		t.Fatal(allow)
	}
	do("POST", "agenda", map[string]any{"action": "complete", "item_id": s.Agenda[0].ID}, 400)
	rec := do("POST", "agenda", map[string]any{"action": "add", "title": "Implement the agreed plan", "kind": "implementation", "expected_version": s.AgendaVersion}, 200)
	var next meeting.Session
	if err = json.Unmarshal(rec.Body.Bytes(), &next); err != nil || len(next.Agenda) != 2 {
		t.Fatal(next, err)
	}
	do("POST", "agenda", map[string]any{"action": "select", "item_id": next.Agenda[1].ID, "expected_version": s.AgendaVersion}, 409)
	do("POST", "run", map[string]any{"expected_round": 0, "agenda_version": s.AgendaVersion}, 409)
	rec = do("POST", "agenda", map[string]any{"action": "select", "item_id": next.Agenda[1].ID, "expected_version": next.AgendaVersion, "kind": "discussion"}, 200)
	if err = json.Unmarshal(rec.Body.Bytes(), &next); err != nil || next.ActiveAgendaID != next.Agenda[1].ID || next.Agenda[1].Kind != "discussion" || len(next.Rounds) != 0 {
		t.Fatal(next, err)
	}
}
