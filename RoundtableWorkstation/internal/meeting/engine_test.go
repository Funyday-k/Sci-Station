package meeting

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"scistation.local/desktop/internal/deliberation"
	"scistation.local/desktop/internal/workspace"
)

func tempDir(t *testing.T) string {
	t.Helper()
	dir, err := os.MkdirTemp("/private/tmp", "studio-meeting-test-")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.RemoveAll(dir) })
	return dir
}
func testSettings() Settings {
	return Settings{Models: map[string]string{"codex": "codex/main", "cursor": "cursor/main"}, ChildModels: map[string]string{"codex": "codex/child", "cursor": "cursor/child"}, CLIPaths: map[string]string{"codex": "codex-bin", "cursor": "cursor-bin"}, Timeout: 3, MaxChildren: 1, MaxSteps: 8, AllowEdits: true}
}
func engine(t *testing.T, call func(context.Context, string, string, string, string) (string, error)) (*Engine, string) {
	t.Helper()
	project := tempDir(t)
	e, err := New(tempDir(t), call, testSettings)
	if err != nil {
		t.Fatal(err)
	}
	return e, project
}
func settled(t *testing.T, e *Engine, id string) *Session {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		s, err := e.Get(id)
		if err != nil {
			t.Fatal(err)
		}
		if s.Status != "running" {
			return s
		}
		time.Sleep(time.Millisecond)
	}
	t.Fatal("round did not finish")
	return nil
}
func say(text string) string {
	b, _ := json.Marshal(map[string]string{"action": "say", "text": text})
	return string(b)
}
func TestSequentialParentsReadAndKeepChildPrivate(t *testing.T) {
	var mu sync.Mutex
	counts := map[string]int{}
	order := []string{}
	var project string
	call := func(ctx context.Context, seat, model, prompt, executable string) (string, error) {
		mu.Lock()
		defer mu.Unlock()
		counts[model]++
		step := counts[model]
		order = append(order, model)
		if executable != seat+"-bin" {
			return "", errors.New("wrong executable")
		}
		if _, ok := ctx.Deadline(); !ok {
			return "", errors.New("no timeout context")
		}
		switch model {
		case "codex/main":
			switch step {
			case 1:
				return `{"action":"read","path":"note.md"}`, nil
			case 2:
				if !strings.Contains(prompt, `"version":"missing"`) {
					return "", errors.New("missing baseline absent")
				}
				return `{"action":"delegate","name":"Parent suggested name","task":"read and assess the draft"}`, nil
			case 3:
				if !strings.Contains(prompt, "PRIVATE CHILD RESULT") {
					return "", errors.New("child result not returned")
				}
				return `{"action":"write","path":"note.md","text":"actual edited draft"}`, nil
			case 4:
				if !strings.Contains(prompt, modelFileEditUnavailable) || strings.Contains(prompt, "actual edited draft") {
					return "", errors.New("blocked file write was not explained or its text leaked")
				}
				return say("Codex public position"), nil
			case 5:
				if !strings.Contains(prompt, "own_private_child_memory") || !strings.Contains(prompt, "PRIVATE CHILD RESULT") {
					return "", errors.New("own-seat child memory missing in later round")
				}
				return say("Codex followup public position"), nil
			}
		case "codex/child":
			if !strings.Contains(deliberation.InstructionsFrom(ctx), "PRIVATE read-only child") {
				return "", errors.New("missing child boundary")
			}
			if step == 1 {
				return `{"action":"read","path":"note.md","nickname":"Draft Reader"}`, nil
			}
			return say("PRIVATE CHILD RESULT"), nil
		case "cursor/main":
			if !strings.Contains(prompt, "Codex public position") || strings.Contains(prompt, "actual edited draft") {
				return "", errors.New("peer's public view includes an unapplied change or misses the statement")
			}
			if strings.Contains(prompt, "PRIVATE CHILD RESULT") {
				return "", errors.New("private child leaked to peer")
			}
			if _, err := os.Stat(filepath.Join(project, "note.md")); !os.IsNotExist(err) {
				return "", errors.New("meeting wrote a project file before the second seat")
			}
			return say("Cursor public response"), nil
		}
		return "", errors.New("unexpected call")
	}
	e, root := engine(t, call)
	project = root
	s, err := e.Create("Research discussion", project, nil)
	if err != nil {
		t.Fatal(err)
	}
	if len(order) != 0 || s.Status != "ready" || len(s.Rounds) != 0 {
		t.Fatal("create sent a request")
	}
	if _, err = e.Start(s.ID, "Inspect and revise", "", 0); err != nil {
		t.Fatal(err)
	}
	s = settled(t, e, s.ID)
	if s.Status != "ready" {
		t.Fatalf("session failed: %+v", s.Rounds[0].Turns)
	}
	if len(s.Rounds[0].Turns[0].Children) != 1 || len(s.Rounds[0].Turns[0].Changes) != 0 {
		t.Fatal("missing child or unexpected agent file change")
	}
	if s.Rounds[0].Turns[0].Children[0].Name != "Draft Reader" {
		t.Fatal("the child-reported nickname was not saved")
	}
	if s.Rounds[0].Turns[0].Text != "Codex public position" {
		t.Fatal("child replaced public speaker")
	}
	if len(s.Operations) != 0 {
		t.Fatal("blocked model edit entered the write journal")
	}
	markdown, err := e.Markdown(s.ID)
	if err != nil || strings.Contains(markdown, "PRIVATE CHILD RESULT") {
		t.Fatal("private child leaked into export")
	}
	if _, err = e.Start(s.ID, "stale", "", 0); !errors.Is(err, ErrConflict) {
		t.Fatalf("stale precondition accepted: %v", err)
	}
	if _, err = e.Start(s.ID, "Use your own prior private conclusion", "codex", 1); err != nil {
		t.Fatal(err)
	}
	if s = settled(t, e, s.ID); s.Status != "ready" {
		t.Fatal("own-seat followup failed:", s.Rounds[1].Turns[0].Error)
	}
	if _, err = e.Start(s.ID, "Peer followup must not receive private child conclusions", "cursor", 2); err != nil {
		t.Fatal(err)
	}
	if s = settled(t, e, s.ID); s.Status != "ready" {
		t.Fatal("peer privacy followup failed:", s.Rounds[2].Turns[0].Error)
	}
	mu.Lock()
	defer mu.Unlock()
	if order[len(order)-1] != "cursor/main" {
		t.Fatal("parents were not sequential")
	}
}

func TestParentAndChildCannotWriteProjectFiles(t *testing.T) {
	count := 0
	e, project := engine(t, func(ctx context.Context, seat, model, prompt, executable string) (string, error) {
		if model == "codex/child" {
			return `{"action":"write","path":"blocked.md","text":"bad"}`, nil
		}
		count++
		switch count {
		case 1:
			return `{"action":"write","path":"blocked.md","text":"bad"}`, nil
		case 2:
			if !strings.Contains(prompt, modelFileEditUnavailable) {
				return "", errors.New("write was not rejected")
			}
			return `{"action":"delegate","name":"Parent placeholder","task":"attempt write"}`, nil
		case 3:
			if !strings.Contains(prompt, "禁止写入或继续委派") {
				return "", errors.New("child failure was hidden")
			}
			return say("No edit was made."), nil
		}
		return "", errors.New("unexpected request")
	})
	s, err := e.Create("readonly boundaries", project, []string{"codex"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err = e.Start(s.ID, "", "", 0); err != nil {
		t.Fatal(err)
	}
	s = settled(t, e, s.ID)
	if s.Rounds[0].Turns[0].Children[0].Name != "" {
		t.Fatal("a name supplied only by the parent was treated as the child's own name")
	}
	if s.Status != "ready" || s.Rounds[0].Turns[0].Children[0].Status != "error" {
		t.Fatalf("bad outcome: %+v", s)
	}
	if _, err = os.Stat(filepath.Join(project, "blocked.md")); !os.IsNotExist(err) {
		t.Fatal("unread/child write applied")
	}
}

func TestCancelAcrossEngineInstancesAndImmediateRestart(t *testing.T) {
	started := make(chan struct{})
	stopped := make(chan struct{})
	call := func(ctx context.Context, seat, model, prompt, executable string) (string, error) {
		close(started)
		<-ctx.Done()
		close(stopped)
		return say("late output must be discarded"), nil
	}
	e, project := engine(t, call)
	s, err := e.Create("cancel", project, nil)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = e.Start(s.ID, "", "", 0); err != nil {
		t.Fatal(err)
	}
	<-started
	other, err := New(e.dir, func(context.Context, string, string, string, string) (string, error) { return say("new round"), nil }, testSettings)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = other.Start(s.ID, "duplicate", "", 0); !errors.Is(err, ErrConflict) {
		t.Fatal("second scheduler launched")
	}
	if _, err = other.Cancel(s.ID); err != nil {
		t.Fatal(err)
	}
	select {
	case <-stopped:
	case <-time.After(time.Second):
		t.Fatal("CLI did not receive cancellation")
	}
	s = settled(t, e, s.ID)
	if s.Status != "partial" || s.Rounds[0].Turns[0].Text != "" || s.Rounds[0].Turns[1].Status != "error" {
		t.Fatal("cancelled work was published")
	}
	if _, err = other.Start(s.ID, "new round", "codex", 1); err != nil {
		t.Fatal(err)
	}
	if s = settled(t, other, s.ID); s.Status != "ready" {
		t.Fatal("new explicit round did not finish")
	}
}

func TestLegacyModelWriteCannotOverwriteUserEdit(t *testing.T) {
	project := tempDir(t)
	if err := os.WriteFile(filepath.Join(project, "note.md"), []byte("original"), 0600); err != nil {
		t.Fatal(err)
	}
	var e *Engine
	var id string
	count := 0
	call := func(ctx context.Context, seat, model, prompt, executable string) (string, error) {
		count++
		switch count {
		case 1:
			return `{"action":"read","path":"note.md"}`, nil
		case 2:
			f, err := workspace.Read(project, "note.md")
			if err != nil {
				return "", err
			}
			if _, err = e.UserWrite(id, "note.md", "human revision", f.Version); err != nil {
				return "", err
			}
			if _, err = e.UserWrite(id, "note.md", "stale manual revision", f.Version); !errors.Is(err, workspace.ErrConflict) {
				return "", errors.New("manual edit did not preserve the original version check")
			}
			return `{"action":"write","path":"note.md","text":"stale agent revision"}`, nil
		default:
			if !strings.Contains(prompt, modelFileEditUnavailable) {
				return "", errors.New("CLI approval boundary missing from parent feedback")
			}
			return say("I preserved the human change."), nil
		}
	}
	var err error
	e, err = New(tempDir(t), call, testSettings)
	if err != nil {
		t.Fatal(err)
	}
	s, err := e.Create("human edit", project, []string{"codex"})
	if err != nil {
		t.Fatal(err)
	}
	id = s.ID
	if _, err = e.Start(id, "", "", 0); err != nil {
		t.Fatal(err)
	}
	s = settled(t, e, id)
	f, err := workspace.Read(project, "note.md")
	if err != nil || f.Text != "human revision" {
		t.Fatal("human edit overwritten")
	}
	if len(s.UserChanges) != 1 || len(s.Rounds[0].Turns[0].Changes) != 0 || len(s.Operations) != 2 ||
		s.Operations[0].Seat != "user" || s.Operations[0].Status != "applied" ||
		s.Operations[1].Seat != "user" || s.Operations[1].Status != "error" {
		t.Fatal("change timeline inconsistent")
	}
}

func TestRecoveryNoReplayAndUnknownWrite(t *testing.T) {
	calls := 0
	e, project := engine(t, func(context.Context, string, string, string, string) (string, error) {
		calls++
		return say("unexpected"), nil
	})
	s, err := e.Create("recovery", project, nil)
	if err != nil {
		t.Fatal(err)
	}
	err = e.locked(func() error {
		s.Status = "running"
		s.Rounds = append(s.Rounds, Round{
			Number: 1, Settings: Settings{AllowEdits: true},
			Turns: []Turn{{Seat: "codex", Status: "running", Children: []Child{{ID: "child", Status: "running"}}, Reads: map[string]workspace.File{}, Changes: []workspace.Change{}}},
		})
		s.Operations = append(s.Operations, Operation{ID: "pending", Path: "note.md", Status: "pending", Text: "possibly written"})
		return e.save(s)
	})
	if err != nil {
		t.Fatal(err)
	}
	other, err := New(e.dir, e.call, testSettings)
	if err != nil {
		t.Fatal(err)
	}
	s, err = other.Get(s.ID)
	if err != nil {
		t.Fatal(err)
	}
	if calls != 0 || s.Status != "partial" || s.Rounds[0].Turns[0].Status != "error" || s.Rounds[0].Turns[0].Children[0].Status != "error" ||
		!s.Rounds[0].Settings.AllowEdits || s.Operations[0].Status != "unknown" || s.Operations[0].Text != "possibly written" {
		t.Fatalf("incorrect recovery: %+v", s)
	}
	if _, err = other.Start(s.ID, "Inspect the previous result", "codex", 1); err != nil {
		t.Fatal(err)
	}
	s = settled(t, other, s.ID)
	if s.Status != "ready" || !s.Rounds[0].Settings.AllowEdits || s.Rounds[1].Settings.AllowEdits || len(s.Operations) != 1 {
		t.Fatal("opening an old writable meeting changed history or restored its edit permission")
	}
	if _, err = os.Stat(filepath.Join(project, "note.md")); !os.IsNotExist(err) {
		t.Fatal("the recovered file edit was replayed")
	}
	if _, err = other.Get("../../bad"); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("invalid ID not rejected")
	}
}

func TestNestedJSONAndStepLimit(t *testing.T) {
	for _, raw := range []string{say("plain"), "```json\n" + say("fenced") + "\n```", marshal(say("nested")), marshal(map[string]string{"result": say("wrapped")})} {
		a, err := decodeAction(raw)
		if err != nil || a.Action != "say" {
			t.Fatalf("decode %s: %v", raw, err)
		}
	}
	count := 0
	e, project := engine(t, func(context.Context, string, string, string, string) (string, error) {
		count++
		return `{"action":"read","path":"missing.md"}`, nil
	})
	s, err := e.Create("bounded loop", project, []string{"codex"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err = e.Start(s.ID, "", "", 0); err != nil {
		t.Fatal(err)
	}
	s = settled(t, e, s.ID)
	if s.Status != "partial" || count != testSettings().MaxSteps || !strings.Contains(s.Rounds[0].Turns[0].Error, "步骤上限") {
		t.Fatal("unbounded read loop")
	}
}

func TestShutdownWaitsForEveryChildAndPersistsTerminalState(t *testing.T) {
	started := make(chan struct{}, 2)
	stopped := make(chan struct{}, 2)
	e, project := engine(t, func(ctx context.Context, seat, model, prompt, executable string) (string, error) {
		if model == "codex/main" {
			return `{"action":"delegate","task":"private bounded review"}`, nil
		}
		started <- struct{}{}
		<-ctx.Done()
		// Model transport must wait for process-group cleanup before returning.
		time.Sleep(15 * time.Millisecond)
		stopped <- struct{}{}
		return "", ctx.Err()
	})
	ids := []string{}
	for range 2 {
		s, err := e.Create("shutdown", project, []string{"codex"})
		if err != nil {
			t.Fatal(err)
		}
		ids = append(ids, s.ID)
		if _, err = e.Start(s.ID, "", "", 0); err != nil {
			t.Fatal(err)
		}
	}
	for range 2 {
		select {
		case <-started:
		case <-time.After(time.Second):
			t.Fatal("child did not start")
		}
	}
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	if err := e.Shutdown(ctx); err != nil {
		t.Fatal(err)
	}
	if len(stopped) != 2 {
		t.Fatal("Shutdown returned before child transport cleanup")
	}
	for _, id := range ids {
		s, err := e.Get(id)
		if err != nil {
			t.Fatal(err)
		}
		turn := s.Rounds[0].Turns[0]
		if s.Status != "partial" || turn.Status != "error" || turn.Children[0].Status != "error" {
			t.Fatalf("unfinished state after Shutdown: %+v", s)
		}
		if turn.Text != "" {
			t.Fatal("cancelled child became a public statement")
		}
		if _, err = e.Start(id, "", "", 1); !errors.Is(err, ErrConflict) {
			t.Fatalf("closed engine accepted a new round: %v", err)
		}
	}
	if err := e.Shutdown(ctx); err != nil {
		t.Fatal("Shutdown is not idempotent:", err)
	}
}

func TestShutdownHonorsDeadlineWhileCleanupContinues(t *testing.T) {
	started := make(chan struct{})
	release := make(chan struct{})
	e, project := engine(t, func(ctx context.Context, seat, model, prompt, executable string) (string, error) {
		close(started)
		<-release
		return "", ctx.Err()
	})
	s, err := e.Create("slow transport cleanup", project, []string{"codex"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err = e.Start(s.ID, "", "", 0); err != nil {
		t.Fatal(err)
	}
	<-started
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Millisecond)
	defer cancel()
	if err = e.Shutdown(ctx); !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("Shutdown did not respect deadline: %v", err)
	}
	close(release)
	finalCtx, finalCancel := context.WithTimeout(context.Background(), time.Second)
	defer finalCancel()
	if err = e.Shutdown(finalCtx); err != nil {
		t.Fatal(err)
	}
	if state, err := e.Get(s.ID); err != nil || state.Status != "partial" {
		t.Fatal("cancelled work did not reach a durable terminal state")
	}
}

func TestActionExtractionRejectsAmbiguityAndNestedInstructions(t *testing.T) {
	good := []string{
		"我先检查这个文件。\n```json\n{\"action\":\"read\",\"path\":\"note.md\"}\n```\n以上是本次动作。",
		"说明文字\n" + say("公开发言") + "\n结束说明",
		`{"action":"write","path":"note.md","text":"braces { } and escaped \"quotes\""}`,
		say("same") + "\n" + say("same"),
	}
	for _, raw := range good {
		if _, err := decodeAction(raw); err != nil {
			t.Fatalf("valid single action rejected: %s: %v", raw, err)
		}
	}
	bad := []string{
		`{"example":{"action":"write","path":"note.md","text":"bad"}}`,
		`{"text":"{\"action\":\"write\",\"path\":\"note.md\",\"text\":\"bad\"}"}`,
		`[{"action":"write","path":"note.md","text":"bad"}]`,
		`"example {\"action\":\"write\",\"path\":\"note.md\",\"text\":\"bad\"}"`,
		`{"action":"read","path":"note.md"} {"action":"write","path":"note.md","text":"bad"}`,
		say("first") + "\n" + say("second"),
		`{"action":"write","action":"say","path":"note.md","text":"ambiguous"}`,
		`{"action":"write","path":"note.md"}`,
		`文件已经写好了，没有返回动作。`,
	}
	for _, raw := range bad {
		if _, err := decodeAction(raw); err == nil {
			t.Fatalf("ambiguous/nested text accepted: %s", raw)
		}
	}
}

func TestProtocolCorrectionPreservesSuccessfulOperationsAndPrivateChild(t *testing.T) {
	counts := map[string]int{}
	e, project := engine(t, func(ctx context.Context, seat, model, prompt, executable string) (string, error) {
		counts[model]++
		if model == "codex/child" {
			switch counts[model] {
			case 1:
				return "子任务暂未返回动作。", nil
			case 2:
				if !strings.Contains(prompt, "上一回复不符合动作协议") {
					return "", errors.New("child correction missing")
				}
				return "私下结论如下：\n```json\n" + say("私有子任务结论") + "\n```", nil
			}
		}
		switch counts[model] {
		case 1:
			return `{"action":"read","path":"note.md"}`, nil
		case 2:
			return `模型说明很多，但没有动作。` + strings.Repeat("诊断", 500), nil
		case 3:
			if !strings.Contains(prompt, "已成功的读取和委派不要重复执行") || !strings.Contains(prompt, `"ok":true`) || !strings.Contains(prompt, "existing draft") {
				return "", errors.New("history lost during correction")
			}
			return `{"action":"delegate","task":"检查现有文本"}`, nil
		default:
			if !strings.Contains(prompt, "私有子任务结论") {
				return "", errors.New("child result missing after correction")
			}
			return "完成。\n" + say("只有父席公开发言。"), nil
		}
	})
	if err := os.WriteFile(filepath.Join(project, "note.md"), []byte("existing draft"), 0600); err != nil {
		t.Fatal(err)
	}
	s, err := e.Create("protocol repair", project, []string{"codex"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err = e.Start(s.ID, "", "", 0); err != nil {
		t.Fatal(err)
	}
	s = settled(t, e, s.ID)
	turn := s.Rounds[0].Turns[0]
	if s.Status != "ready" || len(turn.Changes) != 0 || len(s.Operations) != 0 || turn.Text != "只有父席公开发言。" {
		t.Fatalf("unexpected repaired state: %+v", turn)
	}
	parentErrors, childErrors := 0, 0
	for _, event := range s.Events {
		if event.Type == "protocol_error" {
			if event.RawExcerpt == "" || len([]rune(event.RawExcerpt)) > 401 || event.Step == 0 {
				t.Fatal("missing/bloated local diagnostic")
			}
			if event.ChildID == "" {
				parentErrors++
			} else {
				childErrors++
			}
		}
	}
	if parentErrors != 1 || childErrors != 1 {
		t.Fatalf("protocol errors parent=%d child=%d", parentErrors, childErrors)
	}
	f, err := workspace.Read(project, "note.md")
	if err != nil || f.Text != "existing draft" {
		t.Fatal("protocol recovery changed the project draft")
	}
}

func TestInvalidProtocolHasTwoCorrectionsAndCannotClaimEdits(t *testing.T) {
	for _, maxSteps := range []int{1, 8} {
		t.Run(string(rune('0'+maxSteps)), func(t *testing.T) {
			calls := 0
			settings := testSettings()
			settings.MaxSteps = maxSteps
			e, err := New(tempDir(t), func(context.Context, string, string, string, string) (string, error) {
				calls++
				return "已完成写入（但没有动作 JSON）。", nil
			}, func() Settings { return settings })
			if err != nil {
				t.Fatal(err)
			}
			s, err := e.Create("no fake success", tempDir(t), []string{"codex"})
			if err != nil {
				t.Fatal(err)
			}
			if _, err = e.Start(s.ID, "", "", 0); err != nil {
				t.Fatal(err)
			}
			s = settled(t, e, s.ID)
			want := min(maxSteps, 3)
			if calls != want || s.Status != "partial" || s.Rounds[0].Turns[0].Text != "" || len(s.Rounds[0].Turns[0].Changes) != 0 || len(s.Operations) != 0 {
				t.Fatalf("invalid protocol ran or claimed edits: calls=%d state=%+v", calls, s)
			}
		})
	}
}

func TestCodexRouteUsesImmutableRoundSnapshotForParentAndChild(t *testing.T) {
	if mode, port := CodexRoute(context.Background()); mode != "" || port != 0 {
		t.Fatal("missing route did not preserve the native CLI default")
	}
	settings := testSettings()
	settings.CodexTransport, settings.MagpiePort = "magpie", 43119
	var settingsMu sync.Mutex
	entered, release := make(chan struct{}), make(chan struct{})
	type observed struct {
		model, mode string
		port        int
	}
	var observations []observed
	var callsMu sync.Mutex
	parentCalls := 0
	call := func(ctx context.Context, seat, model, prompt, executable string) (string, error) {
		mode, port := CodexRoute(ctx)
		callsMu.Lock()
		observations = append(observations, observed{model, mode, port})
		if model == "codex/main" {
			parentCalls++
		}
		step := parentCalls
		callsMu.Unlock()
		if model == "codex/child" {
			return say("private result using the captured route"), nil
		}
		switch step {
		case 1:
			close(entered)
			<-release
			return `{"action":"read","path":"note.md"}`, nil
		case 2:
			return `{"action":"delegate","task":"bounded read-only review"}`, nil
		default:
			return say("public conclusion"), nil
		}
	}
	e, err := New(tempDir(t), call, func() Settings { settingsMu.Lock(); defer settingsMu.Unlock(); return settings })
	if err != nil {
		t.Fatal(err)
	}
	s, err := e.Create("transport snapshot", tempDir(t), []string{"codex"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err = e.Start(s.ID, "", "", 0); err != nil {
		t.Fatal(err)
	}
	<-entered
	settingsMu.Lock()
	settings.CodexTransport, settings.MagpiePort = "cli", 43120
	settingsMu.Unlock()
	close(release)
	s = settled(t, e, s.ID)
	if s.Status != "ready" {
		t.Fatal(s.Rounds[0].Turns[0].Error)
	}
	if s.Rounds[0].Settings.CodexTransport != "magpie" || s.Rounds[0].Settings.MagpiePort != 43119 {
		t.Fatal("round settings were not durably captured")
	}
	if _, err = e.Start(s.ID, "next round", "", 1); err != nil {
		t.Fatal(err)
	}
	s = settled(t, e, s.ID)
	if s.Status != "ready" || s.Rounds[1].Settings.CodexTransport != "cli" {
		t.Fatal("new round did not pick up new settings")
	}
	callsMu.Lock()
	defer callsMu.Unlock()
	if len(observations) != 5 {
		t.Fatalf("unexpected calls: %+v", observations)
	}
	for _, observation := range observations[:4] {
		if observation.mode != "magpie" || observation.port != 43119 {
			t.Fatalf("active round or child used changed settings: %+v", observation)
		}
	}
	if observations[4].mode != "cli" || observations[4].port != 43120 {
		t.Fatalf("next round did not use changed route: %+v", observations[4])
	}
}
