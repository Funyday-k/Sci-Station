package desktop

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"reflect"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"scistation.local/desktop/internal/meeting"
	"scistation.local/desktop/internal/research"
)

func projectTestDir(t *testing.T) string {
	t.Helper()
	dir, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	return dir
}

func projectContextForTest(t *testing.T, server *apiServer, path string) string {
	t.Helper()
	project, ok := server.research.ProjectForDirectory(path)
	if !ok {
		return ""
	}
	snapshot, err := server.projectRuleSnapshot(meeting.ProjectScope{ID: project.ID, Directory: path})
	if err != nil {
		t.Fatal(err)
	}
	return snapshot.Guidance
}

func testMeetingProject(t *testing.T, api *apiServer, dir string) meeting.ProjectScope {
	t.Helper()
	lab := api.research
	grant, err := research.IdentifyDirectory(dir)
	if err != nil {
		t.Fatal(err)
	}
	p, err := lab.RegisterDirectoryProject(dir, "", grant)
	if err != nil {
		t.Fatal(err)
	}
	return meeting.ProjectScope{ID: p.ID, Directory: dir}
}
func writeProjectTestFile(t *testing.T, root, path, content string) string {
	t.Helper()
	absolute := filepath.Join(root, filepath.FromSlash(path))
	if err := os.MkdirAll(filepath.Dir(absolute), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(absolute, []byte(content), 0600); err != nil {
		t.Fatal(err)
	}
	return absolute
}

func projectTestRequest(t *testing.T, handler http.Handler, method, endpoint string, request any, status int, output any) {
	t.Helper()
	var body io.Reader
	if request != nil {
		data, err := json.Marshal(request)
		if err != nil {
			t.Fatal(err)
		}
		body = strings.NewReader(string(data))
	}
	r := httptest.NewRequest(method, "http://localhost:8765/api/studio/projects"+endpoint, body)
	if method == http.MethodPost {
		r.Header.Set("Content-Type", "application/json")
		r.Header.Set("X-Roundtable", "1")
	}
	w := httptest.NewRecorder()
	handler.ServeHTTP(w, r)
	if w.Code != status {
		t.Fatalf("%s %s returned %d, expected %d: %s", method, endpoint, w.Code, status, w.Body)
	}
	if output != nil {
		if err := json.Unmarshal(w.Body.Bytes(), output); err != nil {
			t.Fatal(err)
		}
	}
}

func TestProjectRegisterAndSelectiveImport(t *testing.T) {
	dir := projectTestDir(t)
	project := projectTestDir(t)
	other := projectTestDir(t)
	server := openNavigationFixture(t, dir)
	handler := server.serve(8765)

	writeProjectTestFile(t, project, "AGENTS.md", "test-only-agent-policy")
	writeProjectTestFile(t, project, "CLAUDE.md", "text deliberately unselected")
	writeProjectTestFile(t, project, ".claude/rules/sub/test.md", "Claude rule in a subdirectory")
	writeProjectTestFile(t, project, ".cursor/rules/test.mdc", "---\nglobs: '*.go'\n---\na cursor project rule")
	writeProjectTestFile(t, project, ".cursor/rules/ignored.md", "plain Markdown is not a Cursor project rule")
	writeProjectTestFile(t, project, ".cursor/mcp.json", "{\"token\":\"sentinel-credential\"}")
	writeProjectTestFile(t, project, ".env", "SECRET=sentinel-secret")
	writeProjectTestFile(t, project, ".cursor/rules/oversized.mdc", strings.Repeat("x", maxRuleBytes+1))
	outside := writeProjectTestFile(t, other, "secret.md", "outside project")
	if err := os.Symlink(outside, filepath.Join(project, ".claude", "rules", "unsafe.md")); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(filepath.Join(other), filepath.Join(project, ".cursor", "rules", "elsewhere")); err != nil {
		t.Fatal(err)
	}

	var list struct{ Projects []projectSummary }
	projectTestRequest(t, handler, http.MethodGet, "", nil, 200, &list)
	if len(list.Projects) != 0 {
		t.Fatalf("unexpected projects: %+v", list)
	}
	projectTestRequest(t, handler, http.MethodPost, "", map[string]string{"path": other + "/."}, 200, &list)
	projectTestRequest(t, handler, http.MethodPost, "", map[string]string{"path": other + "/"}, 200, &list)
	if len(list.Projects) != 1 || list.Projects[0].Path != other || list.Projects[0].RuleCount != 0 {
		t.Fatalf("empty registration mismatch: %+v", list)
	}

	var preview struct{ Projects []projectPreview }
	request := projectImportRequest{Action: "preview", Paths: []string{project, project + "/."}}
	projectTestRequest(t, handler, http.MethodPost, "/import", request, 200, &preview)
	if len(preview.Projects) != 1 || len(preview.Projects[0].Rules) != 4 {
		t.Fatalf("preview did not deduplicate or exposed unexpected files: %+v", preview)
	}
	if projectContextForTest(t, server, project) != "" {
		t.Fatal("preview must not import or register rules")
	}
	refs := []projectRuleRef{}
	for _, rule := range preview.Projects[0].Rules {
		if rule.Path == "AGENTS.md" || rule.Path == ".cursor/rules/test.mdc" {
			refs = append(refs, rule.RoundtableRuleVersion)
		}
	}
	selection := projectImportRequest{Action: "apply", Selections: []projectImportSelection{{Path: project, Rules: refs}}}
	projectTestRequest(t, handler, http.MethodPost, "/import", selection, 200, &list)
	projectTestRequest(t, handler, http.MethodPost, "/import", selection, 200, &list)
	if len(list.Projects) != 2 {
		t.Fatalf("registration not idempotent: %+v", list)
	}
	reopened := openNavigationFixture(t, dir)
	context := projectContextForTest(t, reopened, project)
	if !strings.Contains(context, "test-only-agent-policy") || !strings.Contains(context, "globs: '*.go'") ||
		strings.Contains(context, "unselected") || strings.Contains(context, "sentinel-") || projectContextForTest(t, reopened, other) != "" {
		t.Fatalf("unexpected project context: %s", context)
	}

	writeProjectTestFile(t, project, "AGENTS.md", "updated agent rule")
	projectTestRequest(t, handler, http.MethodPost, "/import", selection, 409, nil)
	if projectContextForTest(t, reopened, project) != context {
		t.Fatal("stale preview changed saved context")
	}
	projectTestRequest(t, handler, http.MethodPost, "/import", request, 200, &preview)
	updated := preview.Projects[0].Rules[0]
	if updated.Path != "AGENTS.md" || updated.Imported {
		t.Fatalf("expected an updated rule to reimport: %+v", updated)
	}
	selection.Selections[0].Rules = []projectRuleRef{updated.RoundtableRuleVersion}
	projectTestRequest(t, handler, http.MethodPost, "/import", selection, 200, nil)
	if got := projectContextForTest(t, openNavigationFixture(t, dir), project); !strings.Contains(got, "updated agent rule") || strings.Contains(got, "test-only-agent-policy") || !strings.Contains(got, "a cursor project rule") {
		t.Fatalf("unexpected context after update: %s", got)
	}
}

func TestProjectRejectsOutOfScopePaths(t *testing.T) {
	project := projectTestDir(t)
	outside := projectTestDir(t)
	if err := os.Symlink(outside, filepath.Join(project, "link")); err != nil {
		t.Fatal(err)
	}
	t.Setenv("HOME", projectTestDir(t))
	for _, input := range []string{"relative", "/", os.Getenv("HOME"), filepath.Join(project, "link"), project + "/link/../."} {
		if _, err := cleanProjectPath(input); err == nil {
			t.Errorf("accepted unsafe project path %q", input)
		}
	}
	server := openNavigationFixture(t, projectTestDir(t))
	if _, err := server.applyProjectSelections([]projectImportSelection{
		{Path: outside},
		{Path: project, Rules: []projectRuleRef{{Path: ".claude/rules/../../secret.md"}}},
	}); err == nil {
		t.Fatal("accepted unsupported rule path")
	}
	records, err := server.projectRecords()
	if err != nil || len(records) != 0 {
		t.Fatalf("malformed batch wrote to project registry: %+v %v", records, err)
	}
}

func TestProjectConcurrentRegistrationAndImport(t *testing.T) {
	project := projectTestDir(t)
	first := writeProjectTestFile(t, project, "AGENTS.md", "first rule")
	second := writeProjectTestFile(t, project, "CLAUDE.md", "second rule")
	preview, err := previewProjects(openNavigationFixture(t, projectTestDir(t)).research, []string{project})
	if err != nil || len(preview[0].Rules) != 2 {
		t.Fatalf("could not preview test project: %+v %v", preview, err)
	}
	api := openNavigationFixture(t, projectTestDir(t))
	requests := make([]projectImportSelection, 0, 5)
	for _, rule := range preview[0].Rules {
		requests = append(requests, projectImportSelection{Path: project, Rules: []projectRuleRef{rule.RoundtableRuleVersion}})
	}
	requests = append(requests, projectImportSelection{Path: project}, projectImportSelection{Path: projectTestDir(t)})
	var pending sync.WaitGroup
	for _, request := range requests {
		pending.Add(1)
		go func() {
			defer pending.Done()
			if _, err := api.applyProjectSelections([]projectImportSelection{request}); err != nil {
				t.Error(err)
			}
		}()
	}
	pending.Wait()
	got := projectContextForTest(t, api, project)
	if !strings.Contains(got, filepath.Base(first)) || !strings.Contains(got, filepath.Base(second)) {
		t.Fatalf("concurrent additions lost a rule: %s", got)
	}
	records, err := api.activeProjectSummaries()
	if err != nil || len(records) != 2 {
		t.Fatalf("incomplete project catalog: %+v %v", records, err)
	}
	for _, p := range records {
		if p.Path == project && p.RuleCount != 2 {
			t.Fatal(p)
		}
	}
}

func TestProjectDiscoveryMetadataOnly(t *testing.T) {
	home := projectTestDir(t)
	config := projectTestDir(t)
	t.Setenv("HOME", home)
	t.Setenv("CODEX_HOME", filepath.Join(home, ".alternate-codex"))
	t.Setenv("CLAUDE_CONFIG_DIR", filepath.Join(home, ".alternate-claude"))
	t.Setenv("XDG_CONFIG_HOME", config)
	project := filepath.Join(home, "My-Projects", "sun-local")
	claudeOnly := filepath.Join(home, "My-Projects", "paper")
	cursorOnly := filepath.Join(home, "My-Projects", "cli")
	workspaceOnly := filepath.Join(home, "My Projects", "cursor workspace")
	for _, dir := range []string{project, claudeOnly, cursorOnly, workspaceOnly} {
		if err := os.MkdirAll(dir, 0700); err != nil {
			t.Fatal(err)
		}
	}
	writeProjectTestFile(t, home, ".alternate-codex/config.toml",
		"model = \"private-model-value\"\n[projects."+strconv.Quote(project)+"] # path registry\ntrust_level = \"trusted\"\n"+
			"[plugins."+strconv.Quote(claudeOnly)+"]\nunrelated = true")
	writeProjectTestFile(t, home, ".alternate-claude/projects/"+projectIndexKey(claudeOnly)+"/ignored.jsonl", "claude-transcript-not-read")
	writeProjectTestFile(t, home, ".alternate-claude/projects/"+projectIndexKey(project)+"/ignored.jsonl", "claude-transcript-not-read")
	writeProjectTestFile(t, home, ".cursor/projects/"+strings.TrimPrefix(projectIndexKey(cursorOnly), "-")+"/mcp-auth.json", "cursor-token-not-read")
	writeProjectTestFile(t, home, ".cursor/projects/"+strings.TrimPrefix(projectIndexKey(project), "-")+"/agent-transcripts/ignored.jsonl", "cursor-transcript-not-read")
	got := discoverProjects(nil)
	want := []projectCandidate{
		{Path: cursorOnly, Name: "cli", Sources: []string{"Cursor CLI"}},
		{Path: claudeOnly, Name: "paper", Sources: []string{"Claude Code"}},
		{Path: project, Name: "sun-local", Sources: []string{"Codex", "Claude Code", "Cursor CLI"}},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("metadata discovery = %+v, expected %+v", got, want)
	}

	workspace := writeProjectTestFile(t, home, "My Projects/sample.code-workspace", `{
		/* Cursor workspace metadata */
		"folders": [{ "path": "cursor workspace", }, { "uri": "vscode-remote://host/root" }],
		"settings": { "privateUrl": "https://example.invalid", },
	}`)
	fileURI := func(path string) string { return (&url.URL{Scheme: "file", Path: path}).String() }
	writeProjectTestFile(t, config, "workspaceStorage/editor/workspace.json", `{"workspace":`+strconv.Quote(fileURI(workspace))+`}`)
	writeProjectTestFile(t, config, "workspaceStorage/folder/workspace.json", `{"folder":`+strconv.Quote(fileURI(claudeOnly))+`}`)
	writeProjectTestFile(t, config, "workspaceStorage/remote/workspace.json", `{"folder":"file://elsewhere/var/private"}`)
	gotPaths := cursorWorkspacePaths(filepath.Join(config, "workspaceStorage"))
	if len(gotPaths) != 2 || !strings.Contains(strings.Join(gotPaths, "\n"), workspaceOnly) || !strings.Contains(strings.Join(gotPaths, "\n"), claudeOnly) {
		t.Fatalf("workspace folders did not resolve: %v", gotPaths)
	}
}

func TestProjectImportedReferencesReachOnlyMatchingMeeting(t *testing.T) {
	project, other := projectTestDir(t), projectTestDir(t)
	api := openNavigationFixture(t, projectTestDir(t))
	writeProjectTestFile(t, project, "AGENTS.md", "agent-rule-reference-probe")
	preview, err := previewProjects(openNavigationFixture(t, projectTestDir(t)).research, []string{project})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := api.applyProjectSelections([]projectImportSelection{{Path: project, Rules: []projectRuleRef{preview[0].Rules[0].RoundtableRuleVersion}}}); err != nil {
		t.Fatal(err)
	}
	prompts := make(chan string, 2)
	engine, err := meeting.New(projectTestDir(t), func(ctx context.Context, seat, model, prompt, program string) (string, error) {
		prompts <- prompt
		return `{"action":"say","text":"checked project reference"}`, nil
	}, func() meeting.Settings {
		return meeting.Settings{Models: map[string]string{"codex": "test-model"}, Timeout: 5, MaxSteps: 3}
	})
	if err != nil {
		t.Fatal(err)
	}
	engine.SetProjectAccess(api.research.WithProjectDirectory)
	engine.SetProjectRuleSnapshot(api.projectRuleSnapshot)
	t.Cleanup(func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := engine.Shutdown(ctx); err != nil {
			t.Error(err)
		}
	})
	for _, dir := range []string{project, other} {
		scope := testMeetingProject(t, api, dir)
		session, err := engine.CreateScopedWithMaterials("Verify local rules", scope, []string{"codex"}, nil)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := engine.Start(session.ID, "project-local reference test", "", 0); err != nil {
			t.Fatal(err)
		}
		select {
		case prompt := <-prompts:
			got := strings.Contains(prompt, "agent-rule-reference-probe")
			if got != (dir == project) || (got && !strings.Contains(prompt, "AGENTS.md")) {
				t.Fatalf("wrong references for project %s: %s", dir, prompt)
			}
		case <-time.After(5 * time.Second):
			t.Fatal("round did not call its participant")
		}
	}
}
