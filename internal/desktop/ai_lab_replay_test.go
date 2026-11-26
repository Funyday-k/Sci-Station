package desktop

import (
	"archive/zip"
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http/httptest"
	"strings"
	"testing"

	"scistation.local/desktop/internal/meeting"
)

func TestLabExportOmitsPromptsPathsAndProviderDetails(t *testing.T) {
	const private = "private-fixture-marker"
	room := &meeting.Session{Topic: private, Title: private, ProjectID: private, Project: "/test/" + private, Status: "ready",
		Events: []meeting.Event{{ID: 5, Type: "round_started", At: "2026-11-25T01:02:03Z", Detail: private, RawExcerpt: private, Seat: private, FileVersion: private},
			{ID: 7, Type: "board_" + private, At: private}, {ID: 9, Type: private}}, Materials: []meeting.Material{
			{Name: private, Excerpt: "Sci-Station · 论文原文摘录 v1\n" + private}, {Name: private, Excerpt: "Sci-Station · 项目原文摘录 v1\n" + private}},
		Rounds: []meeting.Round{{Number: 1, Note: private, Turns: []meeting.Turn{{Model: private, Error: private, Text: private}}},
			{Number: 2, LabRun: &meeting.LabRunRecord{Version: 1, RetryOfRound: 1, PromptDigest: private},
				PromptOverride: &meeting.PromptOverride{ID: private, Digest: private, Body: private}}}}
	data, err := labReplayBundle(room)
	if err != nil {
		t.Fatal(err)
	}
	archive, err := zip.NewReader(bytes.NewReader(data), int64(len(data)))
	if err != nil {
		t.Fatal(err)
	}
	files := map[string][]byte{}
	for _, file := range archive.File {
		r, err := file.Open()
		if err != nil {
			t.Fatal(err)
		}
		b, err := io.ReadAll(r)
		r.Close()
		if err != nil {
			t.Fatal(err)
		}
		if bytes.Contains(b, []byte(private)) {
			t.Fatalf("private field escaped into %s", file.Name)
		}
		files[file.Name] = b
	}
	var replay struct{ Events []replayEvent }
	if err = json.Unmarshal(files["replay.json"], &replay); err != nil || len(replay.Events) != 3 || replay.Events[0].ID != 5 || replay.Events[1].Kind != "board" || replay.Events[2].Kind != "other" {
		t.Fatal("lost timeline", err)
	}
	for _, needle := range []string{`"runtime":"roundtable-go"`, `"paper_excerpts":1`, `"project_excerpts":1`} {
		if !bytes.Contains(files["provenance.json"], []byte(needle)) {
			t.Fatalf("missing provenance %s", needle)
		}
	}
	if !bytes.Contains(files["checkpoint.json"], []byte(`"rounds":2`)) || files["manifest.json"] == nil ||
		!bytes.Contains(files["replay.json"], []byte(`"retry_of_round":{"2":1}`)) {
		t.Fatal("missing checkpoint or manifest")
	}
}

func TestLabDiagnosticExportRequiresBoundScopeAndWorksOffline(t *testing.T) {
	dir := t.TempDir()
	prefs, err := openSettings(dir)
	if err != nil {
		t.Fatal(err)
	}
	engine, err := meeting.New(dir, func(context.Context, string, string, string, string) (string, error) {
		t.Fatal("offline export contacted model")
		return "", nil
	}, func() meeting.Settings { return prefs.get().Settings })
	if err != nil {
		t.Fatal(err)
	}
	defer engine.Shutdown(context.Background())
	s, err := engine.CreateScopedWithMaterials("Fixture", meeting.ProjectScope{Global: true}, []string{"codex"}, nil)
	if err != nil {
		t.Fatal(err)
	}
	api := &apiServer{prefs: prefs, meetings: engine}
	for _, tc := range []struct {
		method, query string
		code          int
	}{{"GET", "", 404}, {"GET", "?project=wrong", 404}, {"POST", "?scope=global", 200}, {"GET", "?scope=global", 200}} {
		r := httptest.NewRequest(tc.method, "/api/research/lab/replay/"+s.ID+tc.query, strings.NewReader("{}"))
		w := httptest.NewRecorder()
		api.serveAILab(w, r)
		if w.Code != tc.code {
			t.Fatal(tc, w.Code)
		}
		if tc.code == 200 && tc.method == "GET" && w.Header().Get("Content-Type") != "application/zip" {
			t.Fatal("missing downloadable ZIP")
		}
		if tc.code == 200 && tc.method == "POST" && !strings.Contains(w.Body.String(), "browser_download") {
			t.Fatal(w.Body.String())
		}
	}
}
