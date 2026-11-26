package main

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"scistation.local/desktop/internal/meeting"
	"scistation.local/desktop/internal/research"
)

func TestLabThreadsAndDraftsUseWorkspaceSessionRegistry(t *testing.T) {
	root := t.TempDir()
	var modelCalls atomic.Int32
	started := make(chan struct{}, 1)
	model := func(ctx context.Context, _, _, _, _ string) (string, error) {
		modelCalls.Add(1)
		started <- struct{}{}
		<-ctx.Done()
		return "", ctx.Err()
	}
	open := func(root string) (*meeting.Engine, http.Handler) {
		t.Helper()
		prefs, err := openSettings(root)
		if err != nil {
			t.Fatal(err)
		}
		lab, err := research.New(filepath.Join(root, "research"))
		if err != nil {
			t.Fatal(err)
		}
		engine, err := meeting.New(filepath.Join(root, "meetings"), model, func() meeting.Settings { return prefs.get().Settings })
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { _ = engine.Shutdown(context.Background()) })
		return engine, (&apiServer{prefs: prefs, research: lab, meetings: engine}).serve(8765)
	}
	engine, handler := open(root)
	request := func(method, path string, payload any, status int) []byte {
		t.Helper()
		body, _ := json.Marshal(payload)
		r := httptest.NewRequest(method, "http://localhost:8765"+path, bytes.NewReader(body))
		r.Header.Set("X-Roundtable", "1")
		r.Header.Set("Content-Type", "application/json")
		w := httptest.NewRecorder()
		handler.ServeHTTP(w, r)
		if w.Code != status {
			t.Fatalf("%s %s: got %d, want %d: %s", method, path, w.Code, status, w.Body.String())
		}
		return w.Body.Bytes()
	}
	mkProject := func(name string) research.Project {
		t.Helper()
		return scienceWorkflowDecode[research.Project](t, request("POST", "/api/research/projects", map[string]string{"name": name}, 201))
	}
	first, second := mkProject("First"), mkProject("Second")
	rooms := "/api/studio/sessions"
	initialTopic := "Original evidence request\nPreserve fixed conditions."
	room := scienceWorkflowDecode[meeting.Session](t, request("POST", rooms, map[string]any{
		"topic": initialTopic, "project_id": first.ID, "seats": []string{"codex"},
	}, 201))
	session := rooms + "/" + room.ID
	lab := "/api/research/lab/"
	newDraft := lab + "draft?project=" + first.ID
	followup := newDraft + "&thread=" + room.ID
	global := lab + "draft?scope=global"
	thread := lab + "threads/" + room.ID + "?project=" + first.ID
	putDraft := func(path, text string, revision, want int) {
		t.Helper()
		request("PUT", path, meeting.LabDraft{Text: text, Revision: revision}, want)
	}
	readDraft := func(path string) meeting.LabDraft {
		t.Helper()
		return scienceWorkflowDecode[meeting.LabDraft](t, request("GET", path, nil, 200))
	}
	putDraft(newDraft, "Unsent new question", 0, 200)
	putDraft(followup, "Unsent follow-up", 0, 200)
	putDraft(global, "Separate global question", 0, 200)
	putDraft(followup, "Stale input", 0, 409)
	putDraft(followup, "Bearer fixturecredential123456789", 1, 400)
	request("GET", lab+"draft?project="+second.ID+"&thread="+room.ID, nil, 404)
	request("GET", global+"&thread="+room.ID, nil, 404)
	if d := readDraft(lab + "draft?project=" + second.ID); d != (meeting.LabDraft{}) {
		t.Fatal("second project received the first project's draft", d)
	}
	change := func(path, action, title string, revision, want int) []byte {
		t.Helper()
		return request("PATCH", path, map[string]any{"action": action, "title": title, "revision": revision}, want)
	}
	change(lab+"threads/"+room.ID+"?project="+second.ID, "rename", "Wrong project", 0, 404)
	change(thread, "rename", "Renamed evidence discussion", 0, 200)
	change(thread, "rename", "Stale name", 0, 409)

	request("POST", session+"/run", map[string]int{"expected_round": 0}, 202)
	select {
	case <-started:
	case <-time.After(3 * time.Second):
		t.Fatal("round did not start")
	}
	archived := scienceWorkflowDecode[meeting.Session](t, change(thread, "archive", "", 1, 200))
	if archived.Status != "running" || archived.CancelRequested || archived.Report != nil || archived.LabThread.ArchivedAt == "" {
		t.Fatal("archive changed the scheduler or report", archived)
	}
	request("POST", session+"/cancel", map[string]any{}, 202)
	if err := engine.Shutdown(t.Context()); err != nil {
		t.Fatal(err)
	}
	_, handler = open(root)
	summaries := scienceWorkflowDecode[struct {
		Sessions []meeting.Summary `json:"sessions"`
	}](t, request("GET", rooms, nil, 200))
	if len(summaries.Sessions) != 1 || summaries.Sessions[0].LabThread.ArchivedAt == "" || summaries.Sessions[0].Topic != initialTopic {
		t.Fatal("archive or original evidence lost after restart", summaries)
	}
	stored := request("GET", session, nil, 200)
	if strings.Contains(string(stored), "Unsent") {
		t.Fatal("unsent drafts leaked into the session archive")
	}
	request("POST", session+"/run", map[string]int{"expected_round": 1}, 409)
	next := scienceWorkflowDecode[meeting.Session](t, change(thread, "restore", "", 2, 200))
	if next.ID != room.ID || next.Topic != initialTopic || next.LabThread.Title != "Renamed evidence discussion" ||
		next.LabThread.ArchivedAt != "" || next.Status != "partial" || len(next.Rounds) != 1 {
		t.Fatal("restoring changed the original meeting", next)
	}
	for path, value := range map[string]string{
		newDraft: "Unsent new question", followup: "Unsent follow-up", global: "Separate global question",
	} {
		if draft := readDraft(path); draft.Text != value || draft.Revision != 1 {
			t.Fatal("draft not restored in its scope", path, draft)
		}
	}
	putDraft(followup, "", 1, 200)
	if draft := readDraft(followup); draft.Text != "" || draft.Revision != 2 {
		t.Fatal("discard did not clear text or retain compare-and-swap revision", draft)
	}
	if modelCalls.Load() != 1 {
		t.Fatal("thread metadata or draft replayed a model request")
	}
	_, handler = open(t.TempDir())
	if d := readDraft(global); d != (meeting.LabDraft{}) {
		t.Fatal("global draft crossed research roots", d)
	}
	entries, err := os.ReadDir(filepath.Join(root, "meetings", "lab-drafts"))
	if err != nil || len(entries) != 3 {
		t.Fatalf("unexpected draft files: %v %v", entries, err)
	}
	for _, entry := range entries {
		path := filepath.Join(root, "meetings", "lab-drafts", entry.Name())
		raw, err := os.ReadFile(path)
		if err != nil || bytes.Contains(raw, []byte("fixturecredential")) {
			t.Fatalf("draft storage error or credential persisted: %v", err)
		}
		if bytes.Contains(raw, []byte("Unsent new question")) {
			_, handler = open(root)
			for _, invalid := range []string{
				`{"schema_version":1,"revision":1}`,
				`{"schema_version":2,"revision":1,"text":"future version"}`,
				`{"schema_version":1,"revision":1,"text":"unknown field","future":true}`,
			} {
				if err := os.WriteFile(path, []byte(invalid), 0600); err != nil {
					t.Fatal(err)
				}
				request("GET", newDraft, nil, 400)
				putDraft(newDraft, "Cannot replace invalid record", 1, 400)
				if saved, err := os.ReadFile(path); err != nil || string(saved) != invalid {
					t.Fatalf("invalid draft was replaced: %v", err)
				}
			}
			if err := os.WriteFile(path, raw, 0600); err != nil {
				t.Fatal(err)
			}
			putDraft(newDraft, "Saved after recovery", 1, 200)
			if draft := readDraft(newDraft); draft.Text != "Saved after recovery" || draft.Revision != 2 {
				t.Fatalf("draft did not recover after restoration: %+v", draft)
			}
		}
	}
}
