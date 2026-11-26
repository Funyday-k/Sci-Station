package desktop

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"scistation.local/desktop/internal/meeting"
)

func TestReportHTTPFromOpenSessionToMarkdown(t *testing.T) {
	started := make(chan struct{})
	proceed := make(chan struct{})
	call := func(ctx context.Context, seat, model, prompt, _ string) (string, error) {
		switch {
		case strings.Contains(prompt, `"stage":"drafting"`), strings.Contains(prompt, `"stage":"revising"`):
			return `{"outcome":[{"text":"The drawing is still under review.","evidence":[{"id":"R1-T1","quote":"drawing needs review"}]}]}`, nil
		case strings.Contains(prompt, `"stage":"reviewing"`):
			return `{"accuracy":"Preserve the open decision.","readability":"Lead with the drawing.","evidence":[{"id":"R1-T1","quote":"drawing"}]}`, nil
		case strings.Contains(prompt, "AGENDA DRAFT REQUEST"):
			return `{"agenda":[{"title":"Review the drawing","kind":"discussion"}]}`, nil
		default:
			close(started)
			select {
			case <-proceed:
			case <-ctx.Done():
				return "", ctx.Err()
			}
			return `{"action":"say","text":"The drawing needs review."}`, nil
		}
	}
	e, err := meeting.New(t.TempDir(), call, func() meeting.Settings {
		return meeting.Settings{Models: map[string]string{"codex": "fixture"}, Timeout: 3, MaxSteps: 2}
	})
	if err != nil {
		t.Fatal(err)
	}
	p, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	s, err := e.Create("Inspect the drawing", p, []string{"codex"})
	if err != nil {
		t.Fatal(err)
	}
	h := (&apiServer{meetings: e}).serve(8765)
	do := func(method, path, body string, want int) *httptest.ResponseRecorder {
		t.Helper()
		req := httptest.NewRequest(method, "http://127.0.0.1:8765/api/studio/sessions/"+s.ID+path, strings.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("X-Roundtable", "1")
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)
		if rec.Code != want {
			t.Fatalf("%s %s: %d, want %d: %s", method, path, rec.Code, want, rec.Body.String())
		}
		return rec
	}
	get := func() *meeting.Session {
		t.Helper()
		var session meeting.Session
		if err := json.Unmarshal(do("GET", "", "", 200).Body.Bytes(), &session); err != nil {
			t.Fatal(err)
		}
		return &session
	}
	poll := func(match func(*meeting.Session) bool) *meeting.Session {
		t.Helper()
		deadline := time.Now().Add(3 * time.Second)
		for time.Now().Before(deadline) {
			s := get()
			if match(s) {
				return s
			}
			time.Sleep(time.Millisecond)
		}
		t.Fatal("HTTP lifecycle did not complete")
		return nil
	}
	do("GET", "/report.md", "", 409)
	do("GET", "/report", "", 405)
	do("POST", "/report", `{"action":"finish"}`, 400)
	do("POST", "/report", fmt.Sprintf(`{"action":"finish","expected_round":0,"agenda_version":%d}`, s.AgendaVersion), 409)
	do("POST", "/run", `{"expected_round":0}`, 202)
	select {
	case <-started:
	case <-time.After(time.Second):
		t.Fatal("round did not run")
	}
	do("POST", "/report", fmt.Sprintf(`{"action":"finish","expected_round":1,"agenda_version":%d}`, s.AgendaVersion), 409)
	close(proceed)
	s = poll(func(x *meeting.Session) bool { return x.Status != "running" })
	req := fmt.Sprintf(`{"action":"finish","expected_round":1,"agenda_version":%d}`, s.AgendaVersion)
	do("POST", "/report", req, 202)
	s = poll(func(x *meeting.Session) bool {
		return x.Report != nil && (x.Report.Status == "ready" || x.Report.Status == "failed")
	})
	if s.Report.Status != "ready" || s.Report.ReviewMode != "self" {
		t.Fatal(s.Report)
	}
	do("POST", "/report", req, 200)
	do("POST", "/run", `{"expected_round":1}`, 409)
	do("POST", "/file", `{"path":"test.md","text":"unexpected","version":"missing"}`, 409)
	rec := do("GET", "/report.md", "", 200)
	if rec.Body.String() != s.Report.Markdown || !strings.HasPrefix(rec.Header().Get("Content-Type"), "text/markdown") || !strings.Contains(rec.Header().Get("Content-Disposition"), s.ID) {
		t.Fatal("download does not match the saved report")
	}
}
