//go:build connector_browser_smoke

package main

import (
	"context"
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

	"scistation.local/desktop/internal/meeting"
)

func TestLabConnectorBrowser(t *testing.T) {
	f := setupConnector(t)
	engine, err := meeting.New(filepath.Join(t.TempDir(), "meetings"), func(context.Context, string, string, string, string) (string, error) {
		return "", errors.New("offline fixture")
	}, func() meeting.Settings { return f.api.prefs.get().Settings })
	if err != nil {
		t.Fatal(err)
	}
	defer engine.Shutdown(context.Background())
	f.api.meetings = engine
	server := httptest.NewUnstartedServer(nil)
	port := server.Listener.Addr().(*net.TCPAddr).Port
	routes := f.api.serve(port)
	server.Config.Handler = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/api/studio/models" {
			reply(w, 200, map[string]any{"models": []any{}})
			return
		}
		routes.ServeHTTP(w, r)
	})
	server.Start()
	defer server.Close()
	py, err := exec.LookPath("python3")
	if err != nil {
		t.Fatal(err)
	}
	script, log := filepath.Join(t.TempDir(), "server.py"), filepath.Join(t.TempDir(), "calls")
	if err := os.WriteFile(script, []byte(connectorScript), 0600); err != nil {
		t.Fatal(err)
	}
	origin := "http://127.0.0.1:" + strconv.Itoa(port)
	cmd := exec.Command("node", "tests/lab-connectors-browser-smoke.cjs", origin, f.project, f.other, py, script, log)
	cmd.Stdin = strings.NewReader(f.api.desktopCredentialSessionScript(origin))
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("%v: %s", err, out)
	}
	t.Logf("%s", out)
}
