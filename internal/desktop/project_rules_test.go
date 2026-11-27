package desktop

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"reflect"
	"strconv"
	"strings"
	"testing"
	"time"

	"scistation.local/desktop/internal/meeting"
	"scistation.local/desktop/internal/research"
)

func importTestProjectRule(t *testing.T, server *apiServer, project, text string) projectRuleRef {
	t.Helper()
	const path = "AGENTS.md"
	writeProjectTestFile(t, project, path, text)
	ref := projectRuleRef{Path: path, Digest: research.RoundtableRuleDigest(text)}
	if _, err := server.applyProjectSelections([]projectImportSelection{{Path: project, Rules: []projectRuleRef{ref}}}); err != nil {
		t.Fatal(err)
	}
	return ref
}

func TestProjectRulesViewAndDisableWithoutSource(t *testing.T) {
	project := projectTestDir(t)
	server := openNavigationFixture(t, projectTestDir(t))
	handler := server.serve(8765)
	old := importTestProjectRule(t, server, project, "previous instruction")
	current := importTestProjectRule(t, server, project, "current instruction")
	id := testMeetingProject(t, server, project).ID
	if err := os.Remove(filepath.Join(project, current.Path)); err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(project); err != nil {
		t.Fatal(err)
	}

	query := "/rules?id=" + id
	var view projectRulesView
	projectTestRequest(t, handler, http.MethodGet, query, nil, 200, &view)
	if view.Project.RuleCount != 1 || len(view.Rules) != 1 || view.Rules[0].RoundtableRuleVersion != current || view.Rules[0].Text != "current instruction" {
		t.Fatalf("expected the saved current version, got %+v", view)
	}
	projectTestRequest(t, handler, http.MethodPost, "/rules", map[string]any{"id": id, "rule": old}, 409, nil)
	request := map[string]any{"id": id, "rule": current}
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
	server := openNavigationFixture(t, projectTestDir(t))
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
	engine.SetProjectAccess(server.research.WithProjectDirectory)
	session, err := engine.CreateScopedWithMaterials("Check imported project rules", testMeetingProject(t, server, project), []string{"codex", "cursor"}, nil)
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
	if got := state.Rounds[0].ProjectRules; got == nil || !reflect.DeepEqual(*got, []meeting.ProjectRuleVersion{meeting.ProjectRuleVersion(ref)}) {
		t.Fatalf("first round lost its rule version: %v", got)
	}
	if got := state.Rounds[1].ProjectRules; got == nil || len(*got) != 0 {
		t.Fatalf("second round did not record its empty rule set: %v", got)
	}

	// An unreadable historical rule registry cannot take a current project or
	// its canonical rules out of service.
	if err := os.WriteFile(server.projectsFile(), []byte("{"), 0600); err != nil {
		t.Fatal(err)
	}
	projectTestRequest(t, server.serve(8765), http.MethodGet, "/rules?id="+session.ProjectID, nil, 200, nil)
	projectTestRequest(t, server.serve(8765), http.MethodGet, "/rules?legacy=1&path="+url.QueryEscape(project), nil, 400, nil)
	if _, err := engine.Start(session.ID, "third round", "", 2); err != nil {
		t.Fatal(err)
	}
	checkPrompt(false)
	checkPrompt(false)
	settleRound()
}

func TestRebindingProjectClearsPreviousFolderRules(t *testing.T) {
	root := t.TempDir()
	server := openNavigationFixture(t, root)
	lab := server.research
	lab.SetPathValidator(server.approvedResearchPath)
	// This fixture has no meeting archive; the directory transaction still
	// atomically updates the project and removes its folder-specific rules.
	lab.SetConversationReset(func(_ string, begin func() error) error { return begin() })
	old, next := projectTestDir(t), projectTestDir(t)
	legacyRule := research.RoundtableRule{RoundtableRuleVersion: research.RoundtableRuleVersion{Path: "AGENTS.md", Digest: research.RoundtableRuleDigest("old instruction")}, Source: "AGENTS.md", Text: "old instruction"}
	legacy, err := json.Marshal(map[string]any{old: map[string]any{"path": old, "rules": []research.RoundtableRule{legacyRule}, "future": "keep"}})
	if err != nil {
		t.Fatal(err)
	}
	if err = os.WriteFile(server.projectsFile(), legacy, 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := server.meetingScope("", old, ""); !errors.Is(err, os.ErrPermission) {
		t.Fatal("historical rule entry selected a project", err)
	}
	var archive projectRulesView
	projectTestRequest(t, server.serve(8765), "GET", "/rules?legacy=1&path="+url.QueryEscape(old), nil, 200, &archive)
	if len(archive.Rules) != 1 || archive.Rules[0].Text != "old instruction" {
		t.Fatal(archive)
	}
	importTestProjectRule(t, server, old, "current instructions")
	owner, err := server.meetingScope("", old, "")
	if err != nil || owner.ID == "" {
		t.Fatal(owner, err)
	}
	var initial research.Project
	base := "/api/research/projects/" + owner.ID
	rootFixtureRequest(t, server, "GET", base, nil, 200, &initial)
	rootFixtureRequest(t, server, "POST", base+"/directory", map[string]any{"revision": initial.Revision, "path": ""}, 200, &initial)
	if _, err = server.projectRuleSnapshot(owner); !errors.Is(err, os.ErrPermission) {
		t.Fatal("revoked project supplied meeting rules", err)
	}
	grant, err := research.IdentifyDirectory(next)
	if err != nil {
		t.Fatal(err)
	}
	server.selectedPaths.Store(next, grant)
	rootFixtureRequest(t, server, "POST", base+"/directory", map[string]any{"revision": initial.Revision, "path": next, "resetConversations": true}, 200, &initial)
	if initial.ID != owner.ID {
		t.Fatal(initial)
	}
	if _, err = server.projectRuleSnapshot(owner); !errors.Is(err, os.ErrPermission) {
		t.Fatal("old meeting resolved the rebound folder", err)
	}
	updated, err := server.meetingScope(owner.ID, "", "")
	if err != nil || updated.Directory != next {
		t.Fatal(updated, err)
	}
	snapshot, err := server.projectRuleSnapshot(updated)
	if err != nil || len(snapshot.Versions) != 0 {
		t.Fatal(snapshot, err)
	}
	replacement := testMeetingProject(t, server, old)
	if replacement.ID == owner.ID {
		t.Fatal("new project reused original ID")
	}
	snapshot, err = server.projectRuleSnapshot(replacement)
	if err != nil || len(snapshot.Versions) != 0 {
		t.Fatal("new project inherited historical rules", snapshot, err)
	}
	rootFixtureRequest(t, server, "DELETE", base+"?revision="+strconv.Itoa(initial.Revision), nil, 204, nil)
	if _, err = server.meetingScope(owner.ID, "", ""); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("archived project resolved", err)
	}
	if saved, err := os.ReadFile(server.projectsFile()); err != nil || !bytes.Equal(legacy, saved) {
		t.Fatal("historical archive changed", err)
	}
}
