package desktop

import (
	"context"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"

	"scistation.local/desktop/internal/meeting"
)

func importTestProjectRule(t *testing.T, server *apiServer, project, text string) projectRuleRef {
	t.Helper()
	const path = "AGENTS.md"
	writeProjectTestFile(t, project, path, text)
	ref := projectRuleRef{Path: path, Digest: projectRuleDigest(text)}
	if _, err := server.applyProjectSelections([]projectImportSelection{{Path: project, Rules: []projectRuleRef{ref}}}); err != nil {
		t.Fatal(err)
	}
	return ref
}

func TestProjectRulesViewAndDisableWithoutSource(t *testing.T) {
	project := projectTestDir(t)
	server := &apiServer{prefs: &settingsStore{file: filepath.Join(projectTestDir(t), "settings.json")}}
	handler := server.serve(8765)
	old := importTestProjectRule(t, server, project, "previous instruction")
	current := importTestProjectRule(t, server, project, "current instruction")
	if err := os.Remove(filepath.Join(project, current.Path)); err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(project); err != nil {
		t.Fatal(err)
	}

	query := "/rules?path=" + url.QueryEscape(project)
	var view projectRulesView
	projectTestRequest(t, handler, http.MethodGet, query, nil, 200, &view)
	if view.Project.RuleCount != 1 || len(view.Rules) != 1 || view.Rules[0].projectRuleRef != current || view.Rules[0].Text != "current instruction" {
		t.Fatalf("expected the saved current version, got %+v", view)
	}
	projectTestRequest(t, handler, http.MethodPost, "/rules", map[string]any{"path": project, "rule": old}, 409, nil)
	request := map[string]any{"path": project, "rule": current}
	for range 2 {
		projectTestRequest(t, handler, http.MethodPost, "/rules", request, 200, &view)
		if view.Project.RuleCount != 0 || view.Rules == nil || len(view.Rules) != 0 {
			t.Fatalf("expected no active rules, got %+v", view)
		}
	}
	projectTestRequest(t, handler, http.MethodGet, query, nil, 200, &view)
	if view.Project.Path != project || len(view.Rules) != 0 {
		t.Fatalf("expected project registration without rules, got %+v", view)
	}
	projectTestRequest(t, handler, http.MethodGet, "/rules?path="+url.QueryEscape(projectTestDir(t)), nil, 404, nil)
}

func TestRoundCapturesProjectRuleVersionsAndRejectsBrokenRegistry(t *testing.T) {
	const ruleText = "round-rule-guidance-snapshot"
	project := projectTestDir(t)
	server := &apiServer{prefs: &settingsStore{file: filepath.Join(projectTestDir(t), "settings.json")}}
	ref := importTestProjectRule(t, server, project, ruleText)
	prompts := make(chan string, 4)
	continueFirstSeat := make(chan struct{})
	engine, err := meeting.New(projectTestDir(t), func(ctx context.Context, seat, model, prompt, program string) (string, error) {
		prompts <- prompt
		if seat == "codex" {
			select {
			case <-continueFirstSeat:
			case <-ctx.Done():
				return "", ctx.Err()
			}
		}
		return `{"action":"say","text":"Verified round context."}`, nil
	}, func() meeting.Settings {
		return meeting.Settings{Models: map[string]string{"codex": "test-codex", "cursor": "test-cursor"}, Timeout: 5, MaxSteps: 3}
	})
	if err != nil {
		t.Fatal(err)
	}
	engine.SetProjectRuleSnapshot(server.projectRuleSnapshot)
	t.Cleanup(func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := engine.Shutdown(ctx); err != nil {
			t.Error(err)
		}
	})
	session, err := engine.Create("Check imported project rules", project, []string{"codex", "cursor"})
	if err != nil {
		t.Fatal(err)
	}
	checkPrompt := func(wantRule bool) {
		t.Helper()
		select {
		case prompt := <-prompts:
			if strings.Contains(prompt, ruleText) != wantRule {
				t.Fatalf("want rule context %t, got %s", wantRule, prompt)
			}
		case <-time.After(5 * time.Second):
			t.Fatal("participant did not receive a prompt")
		}
	}
	settleRound := func() *meeting.Session {
		t.Helper()
		deadline := time.Now().Add(5 * time.Second)
		for time.Now().Before(deadline) {
			state, err := engine.Get(session.ID)
			if err != nil {
				t.Fatal(err)
			}
			if state.Status != "running" {
				if state.Status != "ready" {
					t.Fatalf("round ended with status %s", state.Status)
				}
				return state
			}
			time.Sleep(time.Millisecond)
		}
		t.Fatal("round did not finish")
		return nil
	}

	if _, err := engine.Start(session.ID, "first round", "", 0); err != nil {
		t.Fatal(err)
	}
	checkPrompt(true)
	projectTestRequest(t, server.serve(8765), http.MethodPost, "/rules", map[string]any{"path": project, "rule": ref}, 200, nil)
	close(continueFirstSeat)
	checkPrompt(true)
	settleRound()
	if _, err := engine.Start(session.ID, "second round", "", 1); err != nil {
		t.Fatal(err)
	}
	checkPrompt(false)
	checkPrompt(false)
	state := settleRound()
	if got := state.Rounds[0].ProjectRules; got == nil || !reflect.DeepEqual(*got, []meeting.ProjectRuleVersion{ref}) {
		t.Fatalf("first round lost its rule version: %v", got)
	}
	if got := state.Rounds[1].ProjectRules; got == nil || len(*got) != 0 {
		t.Fatalf("second round did not record its empty rule set: %v", got)
	}

	for _, broken := range []string{"{", `{"` + project + `":{}}`} {
		if err := os.WriteFile(server.projectsFile(), []byte(broken), 0600); err != nil {
			t.Fatal(err)
		}
		if _, err := engine.Start(session.ID, "third round", "", 2); err == nil || !strings.Contains(err.Error(), "无法读取项目规则配置") {
			t.Fatalf("expected an actionable configuration error, got %v", err)
		}
		projectTestRequest(t, server.serve(8765), http.MethodGet, "/rules?path="+url.QueryEscape(project), nil, 400, nil)
		if state := settleRound(); len(state.Rounds) != 2 {
			t.Fatal("failed start appended a round")
		}
	}
}
