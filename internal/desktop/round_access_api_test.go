package desktop

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"

	"scistation.local/desktop/internal/meeting"
)

func TestStudioRoundAccessAndUnicodeInputLimits(t *testing.T) {
	store, err := openSettings(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	engine, err := meeting.New(t.TempDir(), func(context.Context, string, string, string, string) (string, error) {
		return `{"action":"say","text":"done"}`, nil
	}, func() meeting.Settings { return store.get().Settings })
	if err != nil {
		t.Fatal(err)
	}
	project, err := os.MkdirTemp("/private/tmp", "roundtable-text-limit-")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.RemoveAll(project) })
	t.Cleanup(func() {
		if err := engine.Shutdown(context.Background()); err != nil {
			t.Error(err)
		}
	})
	api := (&apiServer{prefs: store, meetings: engine}).serve(8765)
	post := func(path string, data map[string]any, want int) *httptest.ResponseRecorder {
		t.Helper()
		body, err := json.Marshal(data)
		if err != nil {
			t.Fatal(err)
		}
		r := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:8765/api/studio"+path, strings.NewReader(string(body)))
		r.Header.Set("X-Roundtable", "1")
		r.Header.Set("Content-Type", "application/json")
		w := httptest.NewRecorder()
		api.ServeHTTP(w, r)
		if w.Code != want {
			t.Fatalf("%s returned %d, want %d: %.500s", path, w.Code, want, w.Body.String())
		}
		return w
	}
	limit := strings.Repeat("中😀", 6000)
	create := map[string]any{"topic": limit + "😀", "project": project, "seats": []string{"codex"}}
	post("/sessions", create, http.StatusBadRequest)
	create["topic"] = limit
	var session meeting.Session
	if err := json.Unmarshal(post("/sessions", create, http.StatusCreated).Body.Bytes(), &session); err != nil {
		t.Fatal(err)
	}
	if session.Topic != limit {
		t.Fatal("created topic did not retain all code points")
	}
	path := "/sessions/" + session.ID + "/run"
	run := map[string]any{"note": limit + "😀", "expected_round": 0, "allow_edits": false}
	post(path, run, http.StatusBadRequest)
	run["note"], run["allow_edits"] = limit, "false"
	post(path, run, http.StatusBadRequest)
	run["allow_edits"] = false
	if err := json.Unmarshal(post(path, run, http.StatusAccepted).Body.Bytes(), &session); err != nil {
		t.Fatal(err)
	}
	if len(session.Rounds) != 1 || session.Rounds[0].Note != limit || session.Rounds[0].Settings.AllowEdits {
		t.Fatal("accepted round did not preserve message and effective read-only snapshot")
	}
}
