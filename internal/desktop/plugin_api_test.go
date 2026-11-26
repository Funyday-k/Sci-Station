package desktop

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"scistation.local/desktop/internal/meeting"
	"scistation.local/desktop/internal/plugins"
)

func TestPluginActionProjectsOnlyGrantedContent(t *testing.T) {
	n := 2
	s := &meeting.Session{Topic: "Reading circle", Project: "/private/project", Status: "running",
		Members: []meeting.Member{{ID: "s1", Label: "评审席"}, {ID: "s2", Label: "评审席"}},
		Report:  &meeting.MeetingReport{Status: "drafting", Markdown: "private draft", ReviewNotes: "private review"},
		Rounds: []meeting.Round{
			{Number: 1, Note: "host note", Turns: []meeting.Turn{
				{Seat: "s1", Model: "model", Text: "published one", Status: "done", Children: []meeting.Child{{Text: "private child"}}},
				{Text: "incomplete speech", Status: "error"},
			}},
			{Number: 2, Turns: []meeting.Turn{{Seat: "s2", Text: "published two", Status: "done"}}},
			{Number: 3, Turns: []meeting.Turn{{Seat: "s1", Text: "not yet published", Status: "done"}, {Seat: "s2", Status: "running"}}},
		},
	}
	act := plugins.Action{ID: "count", Input: "public_turns"}
	input, err := pluginInput(s, act, pluginActionRequest{})
	if err != nil {
		t.Fatal(err)
	}
	var data map[string]json.RawMessage
	if err := json.Unmarshal(input, &data); err != nil {
		t.Fatal(err)
	}
	if len(data) != 3 || data["topic"] == nil || data["action"] == nil {
		t.Fatalf("unexpected envelope: %s", input)
	}
	var turns []pluginPublicTurn
	if err := json.Unmarshal(data["turns"], &turns); err != nil {
		t.Fatal(err)
	}
	if len(turns) != 2 || turns[1].Text != "published two" || turns[0].Text != "published one" {
		t.Fatalf("wrong published turns: %s", input)
	}
	if turns[0].Seat != "s1" || turns[0].SeatName != "评审席 · 席位 1" || turns[1].SeatName != "评审席 · 席位 2" {
		t.Fatalf("lost public seat identity: %s", input)
	}
	for _, secret := range []string{"host note", "private", "incomplete speech", "not yet published"} {
		if strings.Contains(string(input), secret) {
			t.Fatalf("unexpected data: %s", secret)
		}
	}
	input, err = pluginInput(s, act, pluginActionRequest{FromRound: &n})
	if err != nil || strings.Contains(string(input), "published one") || !strings.Contains(string(input), "published two") {
		t.Fatalf("range: %s %v", input, err)
	}
	third := 3
	if _, err := pluginInput(s, act, pluginActionRequest{ToRound: &third}); err == nil {
		t.Fatal("unpublished round accepted")
	}
	s.Rounds[0].Turns[0].Text = strings.Repeat("x", plugins.MaxInputBytes)
	if _, err := pluginInput(s, act, pluginActionRequest{}); err == nil {
		t.Fatal("oversized transcript was silently accepted")
	}
	act.Input = "report"
	if _, err := pluginInput(s, act, pluginActionRequest{}); err == nil {
		t.Fatal("draft report exposed")
	}
	s.Report.Status, s.Report.Markdown = "ready", "final report"
	input, err = pluginInput(s, act, pluginActionRequest{})
	if err != nil || strings.Contains(string(input), "turns") || strings.Contains(string(input), "private") || !strings.Contains(string(input), "final report") {
		t.Fatalf("report projection: %s %v", input, err)
	}
	if _, err := pluginInput(s, act, pluginActionRequest{FromRound: &n}); err == nil {
		t.Fatal("report accepted a round range")
	}
}

func TestMarketReadIsOfflineAndChangesUseStudioGuard(t *testing.T) {
	store, err := plugins.NewStore(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	server := (&apiServer{plugins: store}).serve(8765)
	call := func(method, path, body string, guard bool) *httptest.ResponseRecorder {
		req := httptest.NewRequest(method, "http://127.0.0.1:8765/api/studio/"+path, strings.NewReader(body))
		if guard {
			req.Header.Set("Content-Type", "application/json")
			req.Header.Set("X-Roundtable", "1")
		}
		w := httptest.NewRecorder()
		server.ServeHTTP(w, req)
		return w
	}
	w := call(http.MethodGet, "plugins", "", false)
	if w.Code != 200 || !strings.Contains(w.Body.String(), "builtin") {
		t.Fatalf("initial catalog: %d %s", w.Code, w.Body.String())
	}
	if w = call(http.MethodPost, "plugins", `{"action":"install"}`, false); w.Code != 403 {
		t.Fatalf("unguarded mutation: %d", w.Code)
	}
	if w = call(http.MethodGet, "sessions/whatever/plugin-action", "", false); w.Code != 405 {
		t.Fatalf("GET executed: %d", w.Code)
	}
}

func TestPluginSaveUsesOnlyNativePickerDestination(t *testing.T) {
	api := &apiServer{}
	root := t.TempDir()
	payload := func(filename string) string {
		b, err := json.Marshal(map[string]string{"filename": filename, "text": "发言：2\n", "format": "text"})
		if err != nil {
			t.Fatal(err)
		}
		return string(b)
	}
	post := func(name string) *httptest.ResponseRecorder {
		req := httptest.NewRequest("POST", "http://127.0.0.1:8765/api/studio/plugins/save-output", strings.NewReader(payload(name)))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("X-Roundtable", "1")
		w := httptest.NewRecorder()
		api.serve(8765).ServeHTTP(w, req)
		return w
	}
	if w := post("result.txt"); w.Code != 200 || !strings.Contains(w.Body.String(), "browser_download") {
		t.Fatal(w.Code, w.Body.String())
	}
	calls := 0
	selected := ""
	api.setSavePicker(func(name, ext string) (string, error) {
		calls++
		if name != "result.txt" || ext != "txt" {
			t.Fatalf("bad suggested name %q %q", name, ext)
		}
		return selected, nil
	})
	if w := post("../result.txt"); w.Code != 400 || calls != 0 {
		t.Fatal("accepted a caller-supplied path")
	}
	if w := post("result.txt"); w.Code != 200 || !strings.Contains(w.Body.String(), `"saved":false`) {
		t.Fatal("cancellation", w.Body.String())
	}
	selected = filepath.Join(root, "host-chosen.txt")
	if w := post("result.txt"); w.Code != 200 || !strings.Contains(w.Body.String(), `"saved":true`) {
		t.Fatal(w.Code, w.Body.String())
	}
	b, err := os.ReadFile(selected)
	if err != nil || string(b) != "发言：2\n" {
		t.Fatal(string(b), err)
	}
}
