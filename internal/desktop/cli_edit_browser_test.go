//go:build cli_browser_smoke

package desktop

import (
	"context"
	"encoding/json"
	"errors"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	"scistation.local/desktop/internal/cliedit"
	"scistation.local/desktop/internal/meeting"
	"scistation.local/desktop/internal/research"
)

func TestCLIEditReviewBrowser(t *testing.T) {
	root := t.TempDir()
	dir, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	file := filepath.Join(dir, "measurement.txt")
	if err = os.WriteFile(file, []byte("initial fixture\n"), 0600); err != nil {
		t.Fatal(err)
	}
	fixtureSource, err := os.ReadFile("../../tests/fixtures/approval-cli.cjs")
	if err != nil {
		t.Fatal(err)
	}
	cli := filepath.Join(t.TempDir(), "mock-codex")
	if err = os.WriteFile(cli, fixtureSource, 0700); err != nil {
		t.Fatal(err)
	}

	var projectID, sessionID string

	for _, phase := range []string{"review", "reopen"} {
		prefs, err := openSettings(root)
		if err != nil {
			t.Fatal(err)
		}
		lab, err := research.New(filepath.Join(root, "research"))
		if err != nil {
			t.Fatal(err)
		}
		lab.SetPathValidator(func(path string) bool { return path == dir })
		engine, err := meeting.New(filepath.Join(root, "meetings"), func(context.Context, string, string, string, string) (string, error) {
			return "", errors.New("offline fixture: no model is connected")
		}, func() meeting.Settings { return prefs.get().Settings })
		if err != nil {
			t.Fatal(err)
		}
		engine.SetProjectAccess(lab.WithProjectDirectory)
		api := &apiServer{desktop: true, prefs: prefs, meetings: engine, research: lab, workspaceDir: root}
		api.cliEdits.lookup = func(_ context.Context, id string) cliEditProvider {
			if id == "codex" {
				return cliEditProvider{ID: id, Label: "Mock Codex CLI", Available: true, path: cli, run: cliedit.RunCodex}
			}
			return cliEditProvider{ID: id, Label: id, Reason: "Fixture has no per-file approval adapter"}
		}
		if phase == "review" {
			project, err := lab.EnsureDirectoryProject(dir)
			if err != nil {
				t.Fatal(err)
			}
			projectID = project.ID
			session, err := engine.CreateScopedWithMaterials("CLI file review fixture", meeting.ProjectScope{ID: projectID, Directory: dir}, []string{"codex"}, nil)
			if err != nil {
				t.Fatal(err)
			}
			sessionID = session.ID
		}
		server := httptest.NewUnstartedServer(nil)
		port := server.Listener.Addr().(*net.TCPAddr).Port
		routes := api.serve(port)
		server.Config.Handler = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			// The meeting UI can ask for its model catalogue on open. Supply an
			// offline list; the CLI editor still uses the production routes.
			if r.URL.Path == "/api/studio/models" {
				w.Header().Set("Content-Type", "application/json")
				_ = json.NewEncoder(w).Encode(map[string]any{"models": []string{}})
				return
			}
			routes.ServeHTTP(w, r)
		})
		server.Start()
		cmd := exec.Command("node", "../../tests/cli-edit-browser-smoke.cjs", "http://127.0.0.1:"+strconv.Itoa(port), projectID, sessionID, file, phase)
		cmd.Stdin = strings.NewReader(api.cliEditWindowScript("http://127.0.0.1:" + strconv.Itoa(port)))
		out, err := cmd.CombinedOutput()
		server.Close()
		api.cliEdits.jobs.Close(context.Background())
		_ = engine.Shutdown(context.Background())
		if err != nil {
			t.Fatalf("%s: %v\n%s", phase, err, out)
		}
		t.Logf("%s", out)
	}
}
