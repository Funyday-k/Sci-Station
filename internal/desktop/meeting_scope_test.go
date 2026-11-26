package desktop

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"scistation.local/desktop/internal/meeting"
	"scistation.local/desktop/internal/plugins"
	"scistation.local/desktop/internal/research"
)

// This fixture provides the project-directory authority independently of the
// session engine. The router, sessions, plugin registry and model workflow use
// their ordinary implementations.
type meetingProjectsFixture struct {
	http.Handler
	mu       sync.RWMutex
	projects map[string]string
}

func (p *meetingProjectsFixture) ProjectDirectory(id string) (string, error) {
	var result string
	err := p.WithProjectDirectory(id, func(dir string) error { result = dir; return nil })
	return result, err
}

func (p *meetingProjectsFixture) WithProjectDirectory(id string, use func(string) error) error {
	p.mu.RLock()
	defer p.mu.RUnlock()
	path, valid := p.projects[id]
	if !valid {
		return os.ErrNotExist
	}
	if path == "" {
		return os.ErrPermission
	}
	return use(path)
}

func (p *meetingProjectsFixture) ProjectForDirectory(path string) (research.Project, bool) {
	p.mu.RLock()
	defer p.mu.RUnlock()
	for id, dir := range p.projects {
		if dir == path {
			return research.Project{Entity: research.Entity{ID: id}, Path: dir}, true
		}
	}
	return research.Project{}, false
}

func (p *meetingProjectsFixture) EnsureDirectoryProject(string) (research.Project, error) {
	return research.Project{}, os.ErrPermission
}

func (p *meetingProjectsFixture) setDirectory(id, dir string) {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.projects[id] = dir
}

func TestScopedRoundtablePersistsPublicDiscussionAndReport(t *testing.T) {
	const (
		projectID = "research-fixture"
		point     = "r1-s1-p1"
		document  = "measurement.txt"
	)
	mkdir := func() string {
		t.Helper()
		p, err := filepath.EvalSymlinks(t.TempDir())
		if err != nil {
			t.Fatal(err)
		}
		return p
	}
	dir, other := mkdir(), mkdir()
	if err := os.WriteFile(filepath.Join(dir, document), []byte("Isolated input only"), 0600); err != nil {
		t.Fatal(err)
	}
	projects := &meetingProjectsFixture{projects: map[string]string{projectID: dir, "other": other}}
	sessionsDir, pluginsDir := t.TempDir(), t.TempDir()
	call := func(_ context.Context, seat, _, prompt, _ string) (string, error) {
		switch {
		case strings.Contains(prompt, "AGENDA DRAFT REQUEST"):
			return `{"agenda":[{"title":"Check the measurement","kind":"discussion"}]}`, nil
		case strings.Contains(prompt, `"stage":"drafting"`), strings.Contains(prompt, `"stage":"revising"`):
			return `{"outcome":[{"text":"Check the measurement before proceeding.","evidence":[{"id":"R1-T1","quote":"Check the measurement."}]}]}`, nil
		case strings.Contains(prompt, `"stage":"reviewing"`):
			if seat != "cursor" {
				t.Errorf("expected a different seat to review, got %q", seat)
			}
			return `{"accuracy":"The claim matches the transcript.","readability":"Lead with the measurement.","evidence":[{"id":"R1-T1","quote":"Check the measurement."}]}`, nil
		case strings.Contains(prompt, `"phase":"challenge"`):
			if seat == "cursor" {
				return `{"action":"say","text":"I support the measurement check.","positions":[{"point_id":"r1-s1-p1","stance":"support","reason":"I support the measurement check."}]}`, nil
			}
			return `{"action":"say","text":"The sample is ready for inspection."}`, nil
		case strings.Contains(prompt, `"phase":"proposal"`):
			if !strings.Contains(prompt, document) || !strings.Contains(prompt, "org.magpie.deliberation-checklist") {
				t.Error("project catalog or enabled plugin guidance missing")
			}
			if seat == "codex" {
				return `{"action":"say","text":"Check the measurement.","points":[{"text":"Check the measurement.","stance":"support","reason":"Check the measurement."}]}`, nil
			}
			return `{"action":"say","text":"Retain the original record."}`, nil
		default:
			return "", fmt.Errorf("unexpected model request by %s", seat)
		}
	}
	open := func(fn func(context.Context, string, string, string, string) (string, error)) (*meeting.Engine, http.Handler) {
		t.Helper()
		engine, err := meeting.New(sessionsDir, fn, func() meeting.Settings {
			return meeting.Settings{Models: map[string]string{"codex": "fixture-lead", "cursor": "fixture-peer"}, Timeout: 2, MaxSteps: 2}
		})
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { _ = engine.Shutdown(context.Background()) })
		market, err := plugins.NewStore(pluginsDir)
		if err != nil {
			t.Fatal(err)
		}
		api := &apiServer{meetings: engine, research: projects, plugins: market}
		engine.SetPluginGuidance(api.pluginGuidance)
		return engine, api.serve(8765)
	}
	engine, handler := open(call)
	request := func(method, path string, payload any, want int) []byte {
		t.Helper()
		body, err := json.Marshal(payload)
		if err != nil {
			t.Fatal(err)
		}
		r := httptest.NewRequest(method, "http://127.0.0.1:8765/api/studio"+path, bytes.NewReader(body))
		r.Header.Set("Content-Type", "application/json")
		r.Header.Set("X-Roundtable", "1")
		resp := httptest.NewRecorder()
		handler.ServeHTTP(resp, r)
		if resp.Code != want {
			t.Fatalf("%s %s: got %d, want %d: %s", method, path, resp.Code, want, resp.Body)
		}
		return resp.Body.Bytes()
	}
	getMarket := func() plugins.View {
		return scienceWorkflowDecode[plugins.View](t, request("GET", "/plugins", nil, 200))
	}
	for _, item := range getMarket().Available {
		request("POST", "/plugins", map[string]any{
			"action": "install", "source_id": item.SourceID, "id": item.ID, "version": item.Version,
			"sha256": item.SHA256, "grants": item.Capabilities,
		}, 200)
	}
	request("POST", "/sessions", map[string]any{"topic": "Unknown project", "project_id": "missing"}, 404)
	request("POST", "/sessions", map[string]any{"topic": "Wrong directory", "project_id": projectID, "project": other}, 403)
	request("POST", "/sessions", map[string]any{"topic": "Unselected directory", "project": mkdir()}, 403)
	session := scienceWorkflowDecode[meeting.Session](t, request("POST", "/sessions",
		map[string]any{"topic": "Review the measurement", "project_id": projectID, "seats": []string{"codex", "cursor"}}, 201))
	if session.ProjectID != projectID || session.Project != dir {
		t.Fatalf("wrong session scope: %q %q", session.ProjectID, session.Project)
	}
	path := "/sessions/" + session.ID
	poll := func(match func(meeting.Session) bool) meeting.Session {
		t.Helper()
		deadline := time.Now().Add(4 * time.Second)
		var current meeting.Session
		for time.Now().Before(deadline) {
			current = scienceWorkflowDecode[meeting.Session](t, request("GET", path, nil, 200))
			if match(current) {
				return current
			}
			time.Sleep(2 * time.Millisecond)
		}
		t.Fatalf("roundtable stalled: %+v", current)
		return current
	}
	request("GET", path+"/file?path="+document, nil, 200)
	request("POST", path+"/agenda", map[string]any{"action": "draft", "expected_version": session.AgendaVersion}, 202)
	session = poll(func(s meeting.Session) bool { return s.AgendaDraftStatus == "ready" })
	if len(session.Agenda) == 0 || session.Agenda[len(session.Agenda)-1].Title != "Check the measurement" {
		t.Fatal("chief agenda was not published", session.Agenda)
	}
	boardPayload := map[string]any{"op": "rename_board", "title": "Host measurement board", "expected_version": session.Board.Version}
	request("POST", path+"/board", boardPayload, 200)
	boardPayload["title"] = "Stale board"
	request("POST", path+"/board", boardPayload, 409)
	for i, phase := range []string{"proposal", "challenge"} {
		request("POST", path+"/run", map[string]any{"expected_round": i, "agenda_version": session.AgendaVersion, "preset": "review", "phase": phase}, 202)
		session = poll(func(s meeting.Session) bool { return s.Status != "running" })
		round := session.Rounds[i]
		if len(round.Turns) != 2 || len(round.PluginGuidance) != 1 || session.Status != "ready" {
			t.Fatalf("round %s did not persist both seats and its plugin snapshot: %+v", phase, round)
		}
	}
	proposal := session.Rounds[0].Turns[0]
	votes := session.Rounds[1].Turns[1].Positions
	if len(proposal.Points) != 1 || proposal.Points[0].ID != point || len(votes) != 1 || votes[0].PointID != point || votes[0].Stance != "support" {
		t.Fatalf("point/vote linkage was lost: %+v %+v", proposal.Points, votes)
	}
	request("POST", path+"/report", map[string]any{"action": "finish", "expected_round": 2, "agenda_version": session.AgendaVersion}, 202)
	session = poll(func(s meeting.Session) bool {
		return s.Report != nil && (s.Report.Status == "ready" || s.Report.Status == "failed")
	})
	if session.Report.Status != "ready" || session.Report.ReviewMode != "peer" || session.Board.Title != "Host measurement board" {
		t.Fatalf("reviewed meeting report or host board missing: %+v / %+v", session.Report, session.Board)
	}
	if err := engine.Shutdown(t.Context()); err != nil {
		t.Fatal(err)
	}
	_, handler = open(func(context.Context, string, string, string, string) (string, error) {
		t.Error("reading an archived meeting must not call a model")
		return "", fmt.Errorf("fixture is offline")
	})
	list := scienceWorkflowDecode[struct{ Sessions []meeting.Summary }](t, request("GET", "/sessions", nil, 200))
	if len(list.Sessions) != 1 || list.Sessions[0].ProjectID != projectID || list.Sessions[0].ID != session.ID {
		t.Fatalf("restart lost project identity: %+v", list.Sessions)
	}
	if report := string(request("GET", path+"/report.md", nil, 200)); report != session.Report.Markdown || !strings.Contains(report, "Check the measurement") {
		t.Fatalf("archived report missing cited text: %s", report)
	}
	var counter plugins.InstalledPlugin
	for _, item := range getMarket().Installed {
		if len(item.Actions) > 0 {
			counter = item
			break
		}
	}
	if !counter.Enabled {
		t.Fatal("public-turn extension did not reopen offline")
	}
	action := request("POST", path+"/plugin-action", pluginActionRequest{
		PluginID: counter.ID, SourceID: counter.SourceID, SHA256: counter.SHA256, Version: counter.Version,
		ActionID: counter.Actions[0].ID,
	}, 200)
	if !strings.Contains(string(action), "codex") || !strings.Contains(string(action), "cursor") {
		t.Fatalf("plugin result lost the two seats: %s", action)
	}
	projects.setDirectory(projectID, other)
	request("GET", path+"/files", nil, 403)
	projects.setDirectory(projectID, "")
	request("GET", path+"/file?path="+document, nil, 403)
	request("GET", path+"/export.md", nil, 200)
}

func TestGlobalRoundtableHasNoDirectoryGrant(t *testing.T) {
	e, err := meeting.New(t.TempDir(), func(_ context.Context, _, _, prompt, _ string) (string, error) {
		if !strings.Contains(prompt, `"allow_edits":false`) || !strings.Contains(prompt, `"catalog":[]`) {
			t.Errorf("global discussion received project file access")
		}
		return `{"action":"say","text":"Shared question answered."}`, nil
	}, func() meeting.Settings {
		return meeting.Settings{Models: map[string]string{"codex": "fixture"}, AllowEdits: true, Timeout: 1, MaxSteps: 1}
	})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = e.Shutdown(context.Background()) })
	a := (&apiServer{meetings: e}).serve(8765)
	request := func(method, path, body string, want int) meeting.Session {
		t.Helper()
		req := httptest.NewRequest(method, "http://localhost:8765/api/studio"+path, strings.NewReader(body))
		req.Header.Set("X-Roundtable", "1")
		req.Header.Set("Content-Type", "application/json")
		w := httptest.NewRecorder()
		a.ServeHTTP(w, req)
		if w.Code != want {
			t.Fatalf("%s %s: want %d got %d: %s", method, path, want, w.Code, w.Body)
		}
		if want >= 400 {
			return meeting.Session{}
		}
		return scienceWorkflowDecode[meeting.Session](t, w.Body.Bytes())
	}
	request("POST", "/sessions", `{"topic":"Bad scope","scope":"global","project_id":"one"}`, 400)
	s := request("POST", "/sessions", `{"topic":"Shared question","scope":"global","seats":["codex"]}`, 201)
	path := "/sessions/" + s.ID
	request("GET", path+"/files", "", 403)
	request("POST", path+"/file", `{"path":"unexpected.txt","text":"no","version":"missing"}`, 403)
	request("POST", path+"/run", `{"expected_round":0,"allow_edits":true}`, 202)
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		s = request("GET", path, "", 200)
		if s.Status != "running" {
			if s.Status != "ready" || s.Project != "" || s.ProjectID != "" || s.Rounds[0].Settings.AllowEdits {
				t.Fatal("global run did not complete without project permissions", s)
			}
			return
		}
		time.Sleep(time.Millisecond)
	}
	t.Fatal("global round did not settle")
}
