package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"scistation.local/desktop/internal/meeting"
	"scistation.local/desktop/internal/research"
)

func TestLabRunRecoveryUsesCurrentSettingsAndFreshPermissions(t *testing.T) {
	root := t.TempDir()
	prefs, err := openSettings(root)
	if err != nil {
		t.Fatal(err)
	}
	lab, err := research.New(filepath.Join(root, "research"))
	if err != nil {
		t.Fatal(err)
	}
	const name = "measurement.md"
	const contents = "EXPERIMENTAL_VALUE fixture\n"
	const followup = "Check the recorded measurement and its units."
	const privatePrompt = "Workspace fixture guidance"
	var settings atomic.Pointer[meeting.Settings]
	configure := func(version int) {
		config := prefs.meetingSettings()
		config.MaxSteps = 3 + version
		config.ToolBudget = &meeting.ToolBudget{MaxCalls: 2 + version, ContextChars: 80000, TotalResults: 5000, PerResult: 1000}
		config.PromptOverrides = map[meeting.PromptSurface]*meeting.PromptOverride{meeting.PromptPaperSummary: {
			ID: "fixture-guidance", Version: version, Surface: meeting.PromptPaperSummary, Digest: "fixture-digest", Body: privatePrompt,
		}}
		settings.Store(&config)
	}
	configure(1)
	var calls atomic.Int32
	type requestContext struct{ session, prompt string }
	observed := make(chan requestContext, 8)
	model := func(ctx context.Context, _, _, prompt, _ string) (string, error) {
		_, session := meeting.ModelRequest(ctx)
		observed <- requestContext{session, prompt}
		switch calls.Add(1) {
		case 1:
			return `{"action":"fail_fixture"}`, nil
		case 2:
			return `{"action":"read","path":"measurement.md"}`, nil
		case 3:
			return "", errors.New("fixture provider failure")
		case 4:
			return `{"action":"read","path":"measurement.md"}`, nil
		case 5:
			return `{"action":"write","path":"measurement.md","text":"unexpected write"}`, nil
		case 6:
			<-ctx.Done()
			return "", ctx.Err()
		default:
			return `{"action":"say","text":"Recovered fixture."}`, nil
		}
	}
	var handler http.Handler
	var project research.Project
	open := func() *meeting.Engine {
		t.Helper()
		engine, err := meeting.New(filepath.Join(root, "sessions"), model, func() meeting.Settings { return *settings.Load() })
		if err != nil {
			t.Fatal(err)
		}
		engine.SetProjectAccess(func(id string, work func(string) error) error {
			if id != project.ID {
				return os.ErrPermission
			}
			return work(project.Path)
		})
		t.Cleanup(func() { _ = engine.Shutdown(context.Background()) })
		handler = (&apiServer{prefs: prefs, research: lab, meetings: engine}).serve(8765)
		return engine
	}
	call := func(method, path string, payload any, want int) []byte {
		t.Helper()
		body, err := json.Marshal(payload)
		if err != nil {
			t.Fatal(err)
		}
		r := httptest.NewRequest(method, "http://127.0.0.1:8765"+path, bytes.NewReader(body))
		r.Header.Set("X-Roundtable", "1")
		r.Header.Set("Content-Type", "application/json")
		w := httptest.NewRecorder()
		handler.ServeHTTP(w, r)
		if w.Code != want {
			t.Fatalf("%s %s: got %d want %d: %s", method, path, w.Code, want, w.Body.Bytes())
		}
		return w.Body.Bytes()
	}
	engine := open()
	project = scienceWorkflowDecode[research.Project](t, call("POST", "/api/research/projects", map[string]string{"name": "Run audit"}, 201))
	other := scienceWorkflowDecode[research.Project](t, call("POST", "/api/research/projects", map[string]string{"name": "Other run scope"}, 201))
	path := filepath.Join(project.Path, name)
	if err := os.WriteFile(path, []byte(contents), 0600); err != nil {
		t.Fatal(err)
	}
	source := scienceWorkflowDecode[research.Note](t, call("POST", "/api/research/projects/"+project.ID+"/notes", map[string]string{
		"title": "Calibration", "body": "Original calibration passage.",
	}, 201))
	location := research.SourceLocation{Kind: "note", ID: source.ID}
	input := labSourcesRequest{ProjectID: project.ID, Location: location}
	evidence := scienceWorkflowDecode[research.WorkflowSource](t, call("POST", "/api/research/lab/sources/preview", input, 200))
	input.Citations = []labCitation{{SourceLocation: location, Hash: evidence.Hash, Quote: "Original calibration passage."}}
	material := scienceWorkflowDecode[[]meeting.Material](t, call("POST", "/api/research/lab/sources/prepare", input, 200))[0]
	room, err := engine.CreateScopedConfiguredWithMaterials("科研工作流 · 论文精读\n工作流 ID：paper-reading\n\nReview the calibration.", meeting.ProjectScope{ID: project.ID, Directory: project.Path},
		[]meeting.Member{{Model: "fixture/run-recovery", Effort: "auto"}}, "review", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	studio := "/api/studio/sessions/" + room.ID
	runs := "/api/research/lab/runs/" + room.ID
	scoped := runs + "?project=" + project.ID
	await := func(check func() bool) {
		t.Helper()
		for until := time.Now().Add(5 * time.Second); time.Now().Before(until); time.Sleep(5 * time.Millisecond) {
			if check() {
				return
			}
		}
		t.Fatal("run did not reach the expected state")
	}
	settled := func(want string) {
		t.Helper()
		await(func() bool {
			s, err := engine.Get(room.ID)
			return err == nil && s.Status == want
		})
	}
	approval := func() *meeting.ReadReview {
		t.Helper()
		var pending *meeting.ReadReview
		await(func() bool { pending = engine.PendingReadReview(room.ID); return pending != nil })
		return pending
	}
	get := func(number string) labRunInspection {
		t.Helper()
		return scienceWorkflowDecode[labRunInspection](t, call("GET", scoped+"&round="+number, nil, 200))
	}
	retry := func(expected, want int) []byte {
		t.Helper()
		return call("POST", scoped, map[string]int{"expected_round": expected}, want)
	}
	call("POST", studio+"/run", map[string]any{"expected_round": 0, "note": followup, "material_ids": []string{material.ID}}, 202)
	firstReview := approval()
	if err := engine.DecideReadReview(room.ID, firstReview.ID, false); err != nil {
		t.Fatal(err)
	}
	settled("partial")
	first := get("1")
	if first.Status != "error" || first.Note != followup || first.Record.PromptDigest == "" || first.Configuration.Prompt.Version != 1 || first.Configuration.Budget.MaxCalls != 3 ||
		len(first.Sources) != 1 || first.Sources[0].Evidence.SourceHash != evidence.Hash || first.Sources[0].Evidence.Source.ID != source.ID {
		t.Fatalf("incorrect recorded input: %+v", first)
	}
	call("GET", runs+"?project="+other.ID+"&round=1", nil, 404)
	call("POST", runs+"?project="+other.ID, map[string]int{"expected_round": 1}, 404)
	call("POST", scoped, map[string]any{"expected_round": 1, "approval": firstReview.ID}, 400)
	if err := engine.Shutdown(context.Background()); err != nil {
		t.Fatal(err)
	}
	configure(2)
	engine = open()
	if reopened := get("1"); reopened.Configuration.Prompt.Version != 1 || reopened.Configuration.Budget.MaxCalls != 3 {
		t.Fatal("reopen substituted current settings for the recorded run")
	}
	next := scienceWorkflowDecode[meeting.Session](t, retry(1, 202))
	if second := next.Rounds[1]; second.LabRun.RetryOfRound != 1 || second.Note != followup || !slices.Equal(second.MaterialIDs, []string{material.ID}) || second.Settings.AllowEdits {
		t.Fatalf("retry changed original input or permissions: %+v", second)
	}
	retry(1, 409)
	secondReview := approval()
	if secondReview.ID == firstReview.ID || engine.DecideReadReview(room.ID, firstReview.ID, true) == nil {
		t.Fatal("retry reused an old decision")
	}
	if err := engine.DecideReadReview(room.ID, secondReview.ID, true); err != nil {
		t.Fatal(err)
	}
	await(func() bool { return calls.Load() == 6 })
	call("POST", studio+"/cancel", map[string]any{}, 202)
	settled("partial")
	second := get("2")
	kinds := make([]string, 0, len(second.Timeline))
	for _, event := range second.Timeline {
		kinds = append(kinds, event.Kind)
	}
	if second.Status != "cancelled" || second.Record.RetryOfRound != 1 || second.Configuration.Prompt.Version != 2 || second.Configuration.Budget.MaxCalls != 4 ||
		!slices.Contains(kinds, "cancel_requested") || !slices.Contains(kinds, "action_error") || !slices.Contains(kinds, "read_approval_allowed") || len(second.Files) != 1 || second.Files[0].Version == "" {
		t.Fatalf("incorrect retry timeline: %+v", second)
	}
	if data, err := os.ReadFile(path); err != nil || string(data) != contents {
		t.Fatal("retry changed a research file", err)
	}
	if inspected := call("GET", scoped+"&round=2", nil, 200); bytes.Contains(inspected, []byte(privatePrompt)) || bytes.Contains(inspected, []byte(contents)) {
		t.Fatal("local audit exposed configured prompt or raw file bytes")
	}
	retry(2, 202)
	settled("ready")
	if third := get("3"); third.Status != "done" || third.Record.RetryOfRound != 2 {
		t.Fatalf("missing completed retry association: %+v", third)
	}
	retry(3, 409)
	firstCall := <-observed
	<-observed
	denied := <-observed
	secondCall := <-observed
	allowed := <-observed
	blocked := <-observed
	thirdCall := <-observed
	if firstCall.session == secondCall.session || secondCall.session == thirdCall.session || strings.Contains(denied.prompt, "EXPERIMENTAL_VALUE") ||
		!strings.Contains(allowed.prompt, "EXPERIMENTAL_VALUE") || !strings.Contains(blocked.prompt, "require the host to start a CLI edit") {
		t.Fatal("retry reused provider state or bypassed the tool boundary")
	}
}

func TestLabRunRecoversHistoricalInProgressSessionWithoutInventingSnapshots(t *testing.T) {
	root := t.TempDir()
	prefs, err := openSettings(root)
	if err != nil {
		t.Fatal(err)
	}
	var calls atomic.Int32
	engine, err := meeting.New(root, func(context.Context, string, string, string, string) (string, error) {
		calls.Add(1)
		return `{"action":"say","text":"Completed on retry."}`, nil
	}, prefs.meetingSettings)
	if err != nil {
		t.Fatal(err)
	}
	defer engine.Shutdown(context.Background())
	room, err := engine.CreateScopedWithMaterials("Historical question", meeting.ProjectScope{Global: true}, []string{"codex"}, nil)
	if err != nil {
		t.Fatal(err)
	}
	room.Status = "running"
	room.Rounds = []meeting.Round{{Number: 1, Preset: "work", Phase: "work", Note: "Historical instruction",
		Turns: []meeting.Turn{{Seat: "codex", Model: "historical-model", Status: "running"}}}}
	room.Events = append(room.Events, meeting.Event{ID: 2, Type: "round_started", Round: 1, At: room.CreatedAt})
	data, err := json.Marshal(room)
	if err != nil {
		t.Fatal(err)
	}
	if err = os.WriteFile(filepath.Join(root, room.ID+".json"), data, 0600); err != nil {
		t.Fatal(err)
	}
	scope := meeting.LabScope{Global: true}
	if _, err := engine.LabRunSession(meeting.LabScope{ProjectID: "wrong"}, room.ID); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("read did not validate its scope", err)
	}
	recovered, err := engine.LabRunSession(scope, room.ID)
	if err != nil || recovered.Status != "partial" || calls.Load() != 0 {
		t.Fatal("history read retried the run", err)
	}
	old := inspectLabRun(recovered, recovered.Rounds[0])
	if old.Record != nil || old.Configuration.Prompt != nil || old.Configuration.Budget != nil || old.Configuration.Model != "historical-model" ||
		old.Status != "interrupted" || len(old.Timeline) != 3 || old.Timeline[2].Kind != "recovered" {
		t.Fatalf("incorrect historical audit %+v", old)
	}
	rev := 0
	if _, err := engine.ChangeLabThread(scope, room.ID, meeting.LabThreadChange{Action: "archive", Revision: &rev}); err != nil {
		t.Fatal(err)
	}
	if _, err := engine.RetryLabRun(scope, room.ID, 1); !errors.Is(err, meeting.ErrConflict) || calls.Load() != 0 {
		t.Fatal("an archived historical run was retried", err)
	}
	rev = 1
	if _, err := engine.ChangeLabThread(scope, room.ID, meeting.LabThreadChange{Action: "restore", Revision: &rev}); err != nil {
		t.Fatal(err)
	}
	next, err := engine.RetryLabRun(scope, room.ID, 1)
	if err != nil || len(next.Rounds) != 2 || next.Rounds[0].LabRun != nil || next.Rounds[1].LabRun.RetryOfRound != 1 || next.Rounds[1].Note != "Historical instruction" {
		t.Fatal("retry did not preserve the historical attempt", err)
	}
}
