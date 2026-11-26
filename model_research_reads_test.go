package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"scistation.local/desktop/internal/deliberation"
	"scistation.local/desktop/internal/meeting"
	"scistation.local/desktop/internal/research"
)

type modelReadFixture struct {
	*connectorFixture
	engine  *meeting.Engine
	handler http.Handler
	scope   meeting.ProjectScope
}

func startModelReadTest(t *testing.T, f *connectorFixture, model func(context.Context, string, string, string, string) (string, error)) *modelReadFixture {
	t.Helper()
	service := f.api.research.(*research.Service)
	dir, err := service.ProjectDirectory(f.project)
	if err != nil {
		t.Fatal(err)
	}
	settings := f.api.prefs.meetingSettings()
	settings.ToolBudget = &meeting.ToolBudget{MaxCalls: 10, ContextChars: 90000, PerResult: 10000, TotalResults: 40000, AutoRead: true}
	engine, err := meeting.New(t.TempDir(), model, func() meeting.Settings { return settings })
	if err != nil {
		t.Fatal(err)
	}
	engine.SetResearchReads(f.api)
	engine.SetProjectAccess(service.WithProjectDirectory)
	t.Cleanup(func() { _ = engine.Shutdown(context.Background()) })
	f.api.meetings = engine
	return &modelReadFixture{f, engine, f.api.serve(8765), meeting.ProjectScope{ID: f.project, Directory: dir}}
}
func (f *modelReadFixture) reviewRequest(session, method, proof string, payload any, want int) []byte {
	f.t.Helper()
	b, _ := json.Marshal(payload)
	r := httptest.NewRequest(method, "http://127.0.0.1:8765/api/studio/sessions/"+session+"/read-review", bytes.NewReader(b))
	r.Header.Set("X-Roundtable", "1")
	r.Header.Set("Content-Type", "application/json")
	r.Header.Set("X-Sci-Station-Connector-Review", proof)
	w := httptest.NewRecorder()
	f.handler.ServeHTTP(w, r)
	if w.Code != want {
		f.t.Fatalf("review %s: %d want %d: %s", method, w.Code, want, w.Body)
	}
	return w.Body.Bytes()
}
func (f *modelReadFixture) pending(id, operation string) meeting.ReadReview {
	f.t.Helper()
	for deadline := time.Now().Add(5 * time.Second); time.Now().Before(deadline); {
		b := f.reviewRequest(id, "GET", f.api.minerCreds.reviewProof, nil, 200)
		var pending *meeting.ReadReview
		if err := json.Unmarshal(b, &pending); err != nil {
			f.t.Fatal(err)
		}
		if pending != nil {
			if pending.Operation != operation || pending.ProjectID != f.project || pending.Action != "research_read" {
				f.t.Fatal(pending)
			}
			return *pending
		}
		time.Sleep(5 * time.Millisecond)
	}
	room, err := f.engine.Get(id)
	f.t.Fatalf("missing %s review: %v %+v", operation, err, room)
	return meeting.ReadReview{}
}
func (f *modelReadFixture) decide(session string, pending meeting.ReadReview, decision string) {
	f.t.Helper()
	f.reviewRequest(session, "POST", f.api.minerCreds.reviewProof, map[string]any{"id": pending.ID, "action": decision, "project_id": f.project}, 204)
}
func (f *modelReadFixture) settled(id string) *meeting.Session {
	f.t.Helper()
	for deadline := time.Now().Add(5 * time.Second); time.Now().Before(deadline); {
		room, err := f.engine.Get(id)
		if err != nil {
			f.t.Fatal(err)
		}
		if room.Status != "running" {
			return room
		}
		time.Sleep(5 * time.Millisecond)
	}
	f.t.Fatal("round did not settle")
	return nil
}
func (f *modelReadFixture) start(seats []string) string {
	f.t.Helper()
	members := make([]meeting.Member, 0, len(seats))
	for _, seat := range seats {
		members = append(members, meeting.Member{Model: "offline/" + seat, Effort: "auto"})
	}
	room, err := f.engine.CreateScopedConfiguredWithMaterials("Read the selected research index", f.scope, members, "review", nil, nil)
	if err != nil {
		f.t.Fatal(err)
	}
	settingsRequest(f.t, f.handler, "POST", "sessions/"+room.ID+"/run", map[string]int{"expected_round": 0}, 202)
	return room.ID
}
func readFixtureFile(t *testing.T, path string) string {
	t.Helper()
	b, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return ""
	}
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}
func modelRegisteredStdio(t *testing.T) (*connectorFixture, string) {
	f := setupConnector(t)
	py, err := exec.LookPath("python3")
	if err != nil {
		t.Fatal(err)
	}
	script, log := filepath.Join(t.TempDir(), "papers.py"), filepath.Join(t.TempDir(), "requests")
	content := strings.Replace(connectorScript, `params["arguments"]["query"]`, `params["arguments"]["query"] + str(params["arguments"]["identifier"])`, 1)
	if err := os.WriteFile(script, []byte(content), 0600); err != nil {
		t.Fatal(err)
	}
	op := f.configure(research.LabConnector{ID: "papers", Transport: "stdio", Enabled: true, Program: py, Arguments: []string{script, log}, Tools: []string{"lookup", "write"}})
	op.Confirmed = true
	f.post("trust", op, 200)
	return f, log
}

func TestModelResearchRoundAndSingleSeatReview(t *testing.T) {
	for _, seats := range [][]string{{"codex"}, {"codex", "claude"}} {
		t.Run(strings.Join(seats, "-"), func(t *testing.T) {
			conn, log := modelRegisteredStdio(t)
			var count atomic.Int32
			model := func(ctx context.Context, seat, _, prompt, _ string) (string, error) {
				if seat != "member-1" {
					return `{"action":"say","text":"I reviewed the public statement."}`, nil
				}
				if !strings.Contains(prompt, "research_connections") || strings.Contains(prompt, log) || !strings.Contains(deliberation.InstructionsFrom(ctx), "research_read") {
					return "", errors.New("missing or excessive connector context")
				}
				switch count.Add(1) {
				case 1, 2:
					return `{"action":"research_read","connection":"papers","operation":"tools/list"}`, nil
				case 3:
					digest := regexp.MustCompile(`"definition":"([a-f0-9]{64})"`).FindStringSubmatch(prompt)
					if len(digest) != 2 {
						return "", errors.New("discovery missing")
					}
					return fmt.Sprintf(`{"action":"research_read","connection":"papers","operation":"tools/call","resource":"lookup","definition":"%s","arguments":{"query":"private-fixture-","identifier":9007199254740993}}`, digest[1]), nil
				default:
					if !strings.Contains(prompt, "private-fixture-9007199254740993") {
						return "", errors.New("approved structured arguments lost precision")
					}
					return `{"action":"say","text":"The user-approved paper was found."}`, nil
				}
			}
			f := startModelReadTest(t, conn, model)
			id := f.start(seats)
			pending := f.pending(id, "tools/list")
			if got := readFixtureFile(t, log); got != "" {
				t.Fatal("discovery started without approval", got)
			}
			if got := string(f.reviewRequest(id, "GET", "", nil, 200)); strings.TrimSpace(got) != "null" {
				t.Fatal("non-desktop review visible")
			}
			decision := map[string]any{"id": pending.ID, "action": "allow", "project_id": f.project}
			f.reviewRequest(id, "POST", f.api.minerCreds.labProof, decision, 403)
			decision["project_id"] = f.other
			f.reviewRequest(id, "POST", f.api.minerCreds.reviewProof, decision, 403)
			f.decide(id, pending, "deny")
			second := f.pending(id, "tools/list")
			if second.ID == pending.ID || readFixtureFile(t, log) != "" {
				t.Fatal("denied discovery reached service")
			}
			f.decide(id, second, "allow")
			pending = f.pending(id, "tools/call")
			if pending.ArgumentsJSON != `{"identifier":9007199254740993,"query":"private-fixture-"}` || pending.ProjectLabel == "" || pending.Definition == "" || pending.Destination == "" {
				t.Fatal(pending)
			}
			decision = map[string]any{"id": pending.ID, "action": "allow", "project_id": f.project, "arguments": map[string]string{"query": "altered"}}
			f.reviewRequest(id, "POST", f.api.minerCreds.reviewProof, decision, 400)
			if strings.Contains(readFixtureFile(t, log), "tools/call") {
				t.Fatal("changed parameters reached service")
			}
			f.decide(id, pending, "allow")
			delete(decision, "arguments")
			f.reviewRequest(id, "POST", f.api.minerCreds.reviewProof, decision, 409)
			room := f.settled(id)
			if room.Status != "ready" || len(room.Rounds[0].Turns) != len(seats) || strings.Count(readFixtureFile(t, log), "tools/call") != 1 {
				t.Fatalf("round %s %+v", room.Status, room.Events)
			}
			kinds := []string{}
			for _, event := range room.Events {
				if strings.Contains(event.Detail, "private-fixture-") || strings.Contains(event.Detail, log) {
					t.Fatal("unsafe audit", event)
				}
				kinds = append(kinds, event.Type)
			}
			if !slices.Contains(kinds, "mcp_read_denied") || !slices.Contains(kinds, "mcp_read_success") {
				t.Fatal(kinds)
			}
		})
	}
}
func TestModelResearchReadCancelAndRevoke(t *testing.T) {
	for _, cancel := range []bool{true, false} {
		t.Run(fmt.Sprint(cancel), func(t *testing.T) {
			conn, log := modelRegisteredStdio(t)
			var calls atomic.Int32
			f := startModelReadTest(t, conn, func(context.Context, string, string, string, string) (string, error) {
				if calls.Add(1) == 1 {
					return `{"action":"research_read","connection":"papers","operation":"resources/list"}`, nil
				}
				return `{"action":"say","text":"Continuing without external evidence."}`, nil
			})
			id := f.start([]string{"codex"})
			pending := f.pending(id, "resources/list")
			if cancel {
				settingsRequest(t, f.handler, "POST", "sessions/"+id+"/cancel", map[string]any{}, 202)
				f.settled(id)
				f.reviewRequest(id, "POST", f.api.minerCreds.reviewProof, map[string]string{"id": pending.ID, "action": "allow", "project_id": f.project}, 409)
			} else {
				op := labConnectorRequest{ID: "papers", ProjectID: f.project, Confirmed: true, Revision: 2}
				f.post("untrust", op, 200)
				f.post("trust", op, 200)
				f.decide(id, pending, "allow")
				room := f.settled(id)
				if room.Status != "ready" {
					t.Fatal(room.Status)
				}
			}
			if readFixtureFile(t, log) != "" {
				t.Fatal("cancel or invalidated trust reached local service")
			}
		})
	}
}

func TestModelResearchBackoffAndRetry(t *testing.T) {
	conn := setupConnector(t)
	op := conn.configure(research.LabConnector{ID: "papers", Transport: "https", Endpoint: "https://example.com", Enabled: true})
	op.Confirmed = true
	conn.post("trust", op, 200)
	var requests atomic.Int32
	var clock atomic.Int64
	clock.Store(1)
	conn.api.labConnect.modelAudit.clock = func() time.Time { return time.Unix(clock.Load(), 0) }
	conn.api.labConnect.modelAudit.http = &http.Client{Transport: labTestTransport(func(w http.ResponseWriter, r *http.Request) {
		var msg struct {
			Method string
			ID     int
		}
		_ = json.NewDecoder(r.Body).Decode(&msg)
		if requests.Add(1) == 1 {
			http.Error(w, "fixture", 503)
			return
		}
		switch msg.Method {
		case "initialize":
			fmt.Fprint(w, `{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18","capabilities":{"resources":{}}}}`)
		case "notifications/initialized":
			w.WriteHeader(202)
		case "resources/list":
			fmt.Fprint(w, `{"jsonrpc":"2.0","id":2,"result":{"resources":[{"uri":"arxiv:fixture","name":"Fixture article"}]}}`)
		default:
			t.Errorf("unexpected request %s", msg.Method)
		}
	})}
	var steps atomic.Int32
	f := startModelReadTest(t, conn, func(_ context.Context, _, _, prompt, _ string) (string, error) {
		switch steps.Add(1) {
		case 3:
			if !strings.Contains(prompt, "retry_count=2") {
				return "", errors.New("suppressed retry missing from feedback")
			}
			clock.Add(3)
		case 4:
			if !strings.Contains(prompt, "arxiv:fixture") {
				return "", errors.New("approved retry missing result")
			}
			return `{"action":"say","text":"Recovered the catalog."}`, nil
		}
		return `{"action":"research_read","connection":"papers","operation":"resources/list"}`, nil
	})
	id := f.start([]string{"codex"})
	first := f.pending(id, "resources/list")
	f.decide(id, first, "allow")
	next := f.pending(id, "resources/list")
	if requests.Load() != 1 || first.ID == next.ID {
		t.Fatal("backoff made an external call", requests.Load())
	}
	f.decide(id, next, "allow")
	room := f.settled(id)
	if room.Status != "ready" || requests.Load() != 4 {
		t.Fatal(room.Status, requests.Load())
	}
	audit := map[string]string{}
	for _, ev := range room.Events {
		audit[ev.Type] = ev.Detail
	}
	if !strings.Contains(audit["mcp_read_error"], "HTTP 503") || !strings.Contains(audit["mcp_read_backoff"], "retry_count=2") || !strings.Contains(audit["mcp_read_backoff"], "next_retry=") || audit["mcp_read_success"] == "" {
		t.Fatal(audit)
	}
}
func TestModelResearchRejectsMalformedOrUnregisteredOperations(t *testing.T) {
	f, _ := modelRegisteredStdio(t)
	s := f.api.research.(*research.Service)
	dir, _ := s.ProjectDirectory(f.project)
	scope := meeting.ProjectScope{ID: f.project, Directory: dir}
	for _, req := range []meeting.ResearchRead{
		{Connection: "unknown", Operation: "tools/list"}, {Connection: "papers", Operation: "tools/write"}, {Connection: "papers", Operation: "tools/call", Resource: "write", Definition: strings.Repeat("a", 64), Arguments: json.RawMessage(`{}`)},
		{Connection: "papers", Operation: "tools/call", Resource: "lookup", Definition: strings.Repeat("a", 64), Arguments: json.RawMessage(`{"a":{"n":1,"n":2}}`)},
	} {
		if _, err := f.api.PrepareResearchRead(scope, req); err == nil {
			t.Fatal(req)
		}
	}
	for _, scope := range []meeting.ProjectScope{{Global: true}, {ID: f.other, Directory: dir}, {ID: f.project, Directory: "/other"}} {
		if len(f.api.ResearchConnections(scope)) != 0 {
			t.Fatal("scope leaked eligible connections", scope)
		}
	}
}

func TestModelResearchListedResourceRead(t *testing.T) {
	conn, log := modelRegisteredStdio(t)
	var steps atomic.Int32
	f := startModelReadTest(t, conn, func(_ context.Context, _, _, prompt, _ string) (string, error) {
		switch steps.Add(1) {
		case 1:
			return `{"action":"research_read","connection":"papers","operation":"resources/list"}`, nil
		case 2:
			if !strings.Contains(prompt, "fixture:paper") {
				return "", errors.New("missing approved resource catalogue")
			}
			return `{"action":"research_read","connection":"papers","operation":"resources/read","resource":"fixture:paper"}`, nil
		default:
			if !strings.Contains(prompt, "Verified fixture text") {
				return "", errors.New("approved source text missing")
			}
			return `{"action":"say","text":"Verified using the approved paper."}`, nil
		}
	})
	id := f.start([]string{"codex"})
	list := f.pending(id, "resources/list")
	f.decide(id, list, "allow")
	read := f.pending(id, "resources/read")
	if read.Resource != "fixture:paper" || strings.Contains(readFixtureFile(t, log), "resources/read") {
		t.Fatal("read executed before approval")
	}
	f.decide(id, read, "allow")
	if f.settled(id).Status != "ready" || strings.Count(readFixtureFile(t, log), "resources/read") != 1 {
		t.Fatal("exact approved source was not read once")
	}
}
func TestModelResearchCredentialRotationAndAuthFailure(t *testing.T) {
	f := setupConnector(t)
	op := f.configure(research.LabConnector{ID: "papers", Transport: "https", Endpoint: "https://example.com/mcp", Bearer: true, Enabled: true})
	op.Confirmed = true
	op.Token = "first-fixture"
	f.post("set-token", op, 200)
	op.Token = ""
	f.post("trust", op, 200)
	s := f.api.research.(*research.Service)
	dir, _ := s.ProjectDirectory(f.project)
	scope := meeting.ProjectScope{ID: f.project, Directory: dir}
	plan, err := f.api.PrepareResearchRead(scope, meeting.ResearchRead{Connection: "papers", Operation: "resources/list"})
	if err != nil {
		t.Fatal(err)
	}
	op.Token = "second-fixture"
	f.post("set-token", op, 200)
	var requests int
	f.api.labConnect.modelAudit.http = &http.Client{Transport: labTestTransport(func(w http.ResponseWriter, r *http.Request) {
		requests++
		http.Error(w, "fixture", http.StatusUnauthorized)
	})}
	if _, err := plan.Execute(context.Background()); err == nil || requests != 0 {
		t.Fatal("stale account dispatch", requests, err)
	}
	plan, err = f.api.PrepareResearchRead(scope, meeting.ResearchRead{Connection: "papers", Operation: "resources/list"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err = plan.Execute(context.Background()); err == nil || !strings.Contains(err.Error(), "401") || requests != 1 {
		t.Fatal(err)
	}
	if _, err = f.api.PrepareResearchRead(scope, meeting.ResearchRead{Connection: "papers", Operation: "resources/list"}); err != nil {
		t.Fatal("credential failures must not start transport backoff", err)
	}
}
