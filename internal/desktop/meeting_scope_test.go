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
	"slices"
	"strings"
	"testing"
	"time"

	"scistation.local/desktop/internal/meeting"
	"scistation.local/desktop/internal/plugins"
	"scistation.local/desktop/internal/research"
)

func meetingProjectService(t *testing.T, approvedPaths ...string) *research.Service {
	t.Helper()
	service, err := research.New(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	service.SetPathValidator(func(path string) bool { return slices.Contains(approvedPaths, path) })
	return service
}

func changeMeetingProjectDirectory(t *testing.T, host *apiServer, project research.Project, path string) research.Project {
	t.Helper()
	var updated research.Project
	rootFixtureRequest(t, host, http.MethodPost, "/api/research/projects/"+project.ID+"/directory",
		map[string]any{"revision": project.Revision, "path": path}, http.StatusOK, &updated)
	return updated
}

func TestScopedRoundtablePersistsPublicDiscussionAndReport(t *testing.T) {
	const (
		point    = "r1-s1-p1"
		document = "measurement.txt"
	)
	dir, other := projectTestDir(t), projectTestDir(t)
	if err := os.WriteFile(filepath.Join(dir, document), []byte("Isolated input only"), 0600); err != nil {
		t.Fatal(err)
	}
	projects := meetingProjectService(t, dir, other)
	project, err := projects.EnsureDirectoryProject(dir)
	if err != nil {
		t.Fatal(err)
	}
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
	open := func(fn func(context.Context, string, string, string, string) (string, error)) (*apiServer, http.Handler) {
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
		return api, api.serve(8765)
	}
	host, handler := open(call)
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
	request("POST", "/sessions", map[string]any{"topic": "Unknown project", "projectId": "missing"}, 404)
	request("POST", "/sessions", map[string]any{"topic": "Wrong directory", "project_id": project.ID, "project": other}, 403)
	request("POST", "/sessions", map[string]any{"topic": "Conflicting IDs", "projectId": project.ID, "project_id": "other"}, 400)
	request("POST", "/sessions", map[string]any{"topic": "Conflicting empty ID", "projectId": "", "project_id": project.ID}, 400)
	request("POST", "/sessions", map[string]any{"topic": "Unselected directory", "project": projectTestDir(t)}, 403)
	session := scienceWorkflowDecode[meeting.Session](t, request("POST", "/sessions",
		map[string]any{"topic": "Review the measurement", "projectId": project.ID, "project_id": project.ID, "seats": []string{"codex", "cursor"}}, 201))
	if session.ProjectID != project.ID || session.Project != dir {
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
	if err := host.meetings.Shutdown(t.Context()); err != nil {
		t.Fatal(err)
	}
	host, handler = open(func(context.Context, string, string, string, string) (string, error) {
		t.Error("reading an archived meeting must not call a model")
		return "", fmt.Errorf("fixture is offline")
	})
	list := scienceWorkflowDecode[struct{ Sessions []meeting.Summary }](t, request("GET", "/sessions", nil, 200))
	if len(list.Sessions) != 1 || list.Sessions[0].ProjectID != project.ID || list.Sessions[0].ID != session.ID {
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
	project = changeMeetingProjectDirectory(t, host, project, other)
	request("GET", path+"/files", nil, 403)
	changeMeetingProjectDirectory(t, host, project, "")
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

func TestUnscopedRoundtableKeepsProjectMaterialsSeparate(t *testing.T) {
	root := t.TempDir()
	science, err := research.New(filepath.Join(root, "research"))
	if err != nil {
		t.Fatal(err)
	}
	prompted := make(chan string, 1)
	engine, err := meeting.New(filepath.Join(root, "meetings"), func(_ context.Context, _, _, prompt, _ string) (string, error) {
		prompted <- prompt
		return `{"action":"say","text":"Scope fixture acknowledged."}`, nil
	}, func() meeting.Settings {
		return meeting.Settings{Models: map[string]string{"codex": "fixture"}, Timeout: 1, MaxSteps: 1}
	})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = engine.Shutdown(context.Background()) })
	engine.SetProjectAccess(science.WithProjectDirectory)
	server := (&apiServer{research: science, meetings: engine}).serve(8765)

	call := func(method, path string, input any, expected int) []byte {
		t.Helper()
		raw, err := json.Marshal(input)
		if err != nil {
			t.Fatal(err)
		}
		r := httptest.NewRequest(method, "http://localhost:8765/api/"+path, bytes.NewReader(raw))
		r.Header.Set("X-Roundtable", "1")
		r.Header.Set("Content-Type", "application/json")
		w := httptest.NewRecorder()
		server.ServeHTTP(w, r)
		if w.Code != expected {
			t.Fatalf("%s %s: got %d want %d: %s", method, path, w.Code, expected, w.Body)
		}
		return w.Body.Bytes()
	}
	newProject := func(name string) research.Project {
		return scienceWorkflowDecode[research.Project](t, call("POST", "research/projects", map[string]string{"name": name}, 201))
	}
	a, b := newProject("Fixture A"), newProject("Fixture B")
	store := func(name, value string) string {
		t.Helper()
		m, err := engine.StoreMaterial(name+".txt", strings.NewReader(value))
		if err != nil || m.ReadStatus != meeting.MaterialReadText {
			t.Fatalf("store %s: %+v %v", name, m, err)
		}
		return m.ID
	}
	aExcerpt := store("A excerpt", meeting.ProjectExcerptMarker+fmt.Sprintf(`{"projectId":%q}`, a.ID)+"\n\nPROJECT_A_BODY")
	bExcerpt := store("B excerpt", meeting.PaperExcerptMarker+fmt.Sprintf(`{"projectId":%q}`, b.ID)+"\n\nPROJECT_B_BODY")
	regular := store("Regular upload", "USER_UPLOAD")
	legacy := store("Legacy attachment", meeting.PaperExcerptMarker+`{"page":1}`+"\n\nLEGACY_ATTACHMENT")

	const sessions = "studio/sessions"
	input := func(p research.Project, attachments ...string) map[string]any {
		fields := map[string]any{"topic": "Roundtable scope fixture", "seats": []string{"codex"}, "material_ids": attachments}
		if p.ID == "" {
			fields["scope"] = "global"
		} else {
			fields["project_id"] = p.ID
		}
		return fields
	}
	create := func(p research.Project, attachments ...string) meeting.Session {
		return scienceWorkflowDecode[meeting.Session](t, call("POST", sessions, input(p, attachments...), 201))
	}

	call("POST", sessions, input(research.Project{}, regular, aExcerpt), 403)
	call("POST", sessions, input(a, aExcerpt, bExcerpt), 403)
	call("POST", sessions, input(b, aExcerpt), 403)
	aRoom, bRoom, unscoped := create(a, aExcerpt), create(b, bExcerpt), create(research.Project{}, regular, legacy)
	if aRoom.ProjectID != a.ID || bRoom.ProjectID != b.ID || unscoped.ProjectID != "" || unscoped.Project != "" {
		t.Fatalf("unstable session ownership: A %q; B %q; unscoped %q/%q", aRoom.ProjectID, bRoom.ProjectID, unscoped.ProjectID, unscoped.Project)
	}
	unscopedPath := sessions + "/" + unscoped.ID
	call("GET", unscopedPath+"/files", nil, 403)
	run := func(path, material string, expected int) {
		fields := map[string]any{"expected_round": 0, "allow_edits": true}
		if material != "" {
			fields["material_ids"] = []string{material}
		}
		call("POST", path+"/run", fields, expected)
	}
	run(unscopedPath, aExcerpt, 403)
	run(sessions+"/"+aRoom.ID, bExcerpt, 403)
	run(unscopedPath, "", 202)
	select {
	case prompt := <-prompted:
		if strings.Contains(prompt, "PROJECT_A_BODY") || strings.Contains(prompt, "PROJECT_B_BODY") ||
			!strings.Contains(prompt, "USER_UPLOAD") || !strings.Contains(prompt, "LEGACY_ATTACHMENT") ||
			!strings.Contains(prompt, `"catalog":[]`) || !strings.Contains(prompt, `"allow_edits":false`) {
			t.Fatal("unscoped model prompt did not preserve its attachment and permission boundary")
		}
	case <-time.After(2 * time.Second):
		t.Fatal("unscoped discussion never reached the offline fixture")
	}
	list := scienceWorkflowDecode[struct{ Sessions []meeting.Summary }](t, call("GET", sessions, nil, 200))
	if len(list.Sessions) != 3 {
		t.Fatalf("failed binding left an unexpected session: %+v", list.Sessions)
	}
	persisted := scienceWorkflowDecode[meeting.Session](t, call("GET", unscopedPath, nil, 200))
	if len(persisted.Materials) != 2 || persisted.Materials[0].ID != regular || persisted.Materials[1].ID != legacy {
		t.Fatalf("unscoped attachments changed after a rejected binding: %+v", persisted.Materials)
	}
}
