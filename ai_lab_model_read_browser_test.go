//go:build connector_browser_smoke

package main

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	"scistation.local/desktop/internal/meeting"
	"scistation.local/desktop/internal/research"
)

func TestModelResearchReadReviewBrowser(t *testing.T) {
	f := setupConnector(t)
	program, err := exec.LookPath("python3")
	if err != nil {
		t.Fatal(err)
	}
	serverScript := strings.Replace(connectorScript,
		`elif method == "tools/call": out={"content":[{"type":"text","text":params["arguments"]["query"]}]}`,
		`elif method == "tools/call":
        assert params["arguments"]["sample_id"] == 9007199254740993
        out={"content":[{"type":"text","text":"measured signal " + params["arguments"]["query"]}]}`, 1)
	dir := t.TempDir()
	script, log := filepath.Join(dir, "server.py"), filepath.Join(dir, "calls")
	if err := os.WriteFile(script, []byte(serverScript), 0600); err != nil {
		t.Fatal(err)
	}
	in := f.configure(research.LabConnector{ID: "fixture", Transport: "stdio", Enabled: true,
		Program: program, Arguments: []string{script, log}, Tools: []string{"lookup"}})
	in.Confirmed = true
	f.post("trust", in, 200)
	in.Action = "tools/list"
	list := scienceWorkflowDecode[struct{ Data []labToolView }](t, f.post("execute", f.prepare(in), 200))
	if len(list.Data) != 1 || list.Data[0].Name != "lookup" {
		t.Fatal("fixture did not expose its read-only tool", list)
	}
	if err := os.Remove(log); err != nil {
		t.Fatal(err)
	}
	action := fmt.Sprintf(`{"action":"research_read","connection":"fixture","operation":"tools/call","resource":"lookup","definition":%q,"arguments":{"query":"gamma","sample_id":9007199254740993}}`, list.Data[0].Definition)
	engine, err := meeting.New(filepath.Join(dir, "meetings"), func(_ context.Context, _, _, prompt, _ string) (string, error) {
		switch {
		case strings.Contains(prompt, "measured signal gamma"):
			return `{"action":"say","text":"The model received the approved gamma result."}`, nil
		case strings.HasSuffix(prompt, "ACTION HISTORY:\n[]"):
			return action, nil
		default:
			return `{"action":"say","text":"The model received no connector result."}`, nil
		}
	}, f.api.prefs.meetingSettings)
	if err != nil {
		t.Fatal(err)
	}
	defer engine.Shutdown(context.Background())
	f.api.workspaceDir = f.dir
	f.api.meetings = engine
	engine.SetResearchReads(f.api)

	server := httptest.NewUnstartedServer(nil)
	port := server.Listener.Addr().(*net.TCPAddr).Port
	routes := f.api.serve(port)
	server.Config.Handler = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/api/studio/models" {
			reply(w, 200, map[string]any{"models": []any{}, "default_model": ""})
			return
		}
		routes.ServeHTTP(w, r)
	})
	server.Start()
	defer server.Close()
	scope, err := f.api.meetingScope(f.project, "", "")
	if err != nil {
		t.Fatal(err)
	}
	ids := []string{}
	for _, topic := range []string{"Approve a fixture lookup", "Reject a fixture lookup", "Cancel a fixture lookup"} {
		room, err := engine.CreateScopedConfiguredWithMaterials(topic, scope,
			[]meeting.Member{{Model: "fixture/research", Effort: "auto"}}, "review", nil, nil)
		if err != nil {
			t.Fatal(err)
		}
		ids = append(ids, room.ID)
	}
	origin := "http://127.0.0.1:" + strconv.Itoa(port)
	args := append([]string{"tests/lab-model-read-browser-smoke.cjs", origin, f.project, f.other, log}, ids...)
	cmd := exec.Command("node", args...)
	cmd.Stdin = strings.NewReader(f.api.desktopCredentialSessionScript(origin))
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("%v: %s", err, out)
	}
	t.Logf("%s", out)
}
