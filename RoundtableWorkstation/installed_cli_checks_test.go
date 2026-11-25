package main

import (
	"context"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestCLIHealthNeverRunsUnknownName(t *testing.T) {
	home := t.TempDir()
	untrustedBin := filepath.Join(home, "project", "bin")
	trustedBin := filepath.Join(home, ".local", "bin")
	marker := filepath.Join(home, "unexpected-execution")
	untrusted := filepath.Join(untrustedBin, "claude")
	inventoryFixtureExecutable(t, untrusted)
	if err := os.WriteFile(untrusted, []byte("#!/bin/sh\ntouch '"+marker+"'\n"), 0700); err != nil {
		t.Fatal(err)
	}
	// Even finding package metadata outside an installed package is insufficient.
	if err := os.WriteFile(filepath.Join(home, "project", "package.json"), []byte(`{"name":"@anthropic-ai/claude-code"}`), 0600); err != nil {
		t.Fatal(err)
	}
	target := filepath.Join(home, ".local/share/claude/versions/2.5.6")
	inventoryFixtureExecutable(t, target)
	script := "#!/bin/sh\n[ \"$#\" -eq 1 ] && [ \"$1\" = --version ] || exit 91\nprintf '%s\\n' '2.5.6 (Claude Code)' 'unexpected plaintext'\n"
	if err := os.WriteFile(target, []byte(script), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(trustedBin, 0700); err != nil {
		t.Fatal(err)
	}
	trusted := filepath.Join(trustedBin, "claude")
	if err := os.Symlink(target, trusted); err != nil {
		t.Fatal(err)
	}

	candidates := detectClientsBy(home, []string{untrustedBin, trustedBin}, nil, inventoryNoDiscover, installedCLIIdentity)
	if client := inventoryByID(candidates, "claude"); client.Path != trusted {
		t.Fatalf("found %q, want %q", client.Path, trusted)
	}
	results := checkInstalledClients(context.Background(), home, candidates)
	if len(results) != 1 || results[0].State != "ready" || results[0].Version != "2.5.6" {
		t.Fatalf("unexpected check result: %+v", results)
	}
	if _, err := os.Stat(marker); !os.IsNotExist(err) {
		t.Fatal("unverified same-name executable ran")
	}
}

func TestCLIHealthFailureAndCancellation(t *testing.T) {
	home := t.TempDir()
	dir := filepath.Join(home, ".amp/bin")
	path := filepath.Join(dir, "amp")
	inventoryFixtureExecutable(t, path)
	candidates := detectClientsBy(home, []string{dir}, nil, inventoryNoDiscover, installedCLIIdentity)
	results := checkInstalledClients(context.Background(), home, candidates)
	if len(results) != 1 || results[0].State != "check_failed" || !results[0].Installed {
		t.Fatalf("failed execution lost confirmed installation: %+v", results)
	}

	if err := os.WriteFile(path, []byte("#!/bin/sh\nsleep 30 &\nwait\n"), 0700); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 50*time.Millisecond)
	defer cancel()
	start := time.Now()
	results = checkInstalledClients(ctx, home, candidates)
	if time.Since(start) > 2*time.Second || results[0].State != "check_failed" {
		t.Fatalf("version subprocess outlived cancellation: %+v", results)
	}
}

func TestClientVersionParsesOnlyVersionLines(t *testing.T) {
	cases := []struct{ id, raw, want string }{
		{"codex", "codex-cli 0.40.10", "0.40.10"},
		{"cursor", "2026.11.22-e9042b2", "2026.11.22-e9042b2"},
		{"claude", "2.5.6 (Claude Code)", "2.5.6"},
		{"gemini", "0.27.3", "0.27.3"},
		{"copilot", "GitHub Copilot CLI v0.0.33.\nGitHub account redacted", ""},
		{"copilot", "GitHub Copilot CLI v0.0.33\nGitHub account redacted", "0.0.33"},
		{"opencode", "2.0.20", "2.0.20"},
		{"qwen", "0.25.2", "0.25.2"},
		{"aider", "aider 0.86.2", "0.86.2"},
		{"kimi", "Kimi Code CLI 2.5.6", "2.5.6"},
		{"pi", "0.81.3", "0.81.3"},
		{"amp", "amp 0.0.12345678-abc123\nadditional output", "0.0.12345678-abc123"},
		{"droid", "Droid CLI version 0.32.0", "0.32.0"},
		{"droid", "error: private-name@example.test v0.32.0", ""},
	}
	for _, tc := range cases {
		if got := clientVersionChecks[tc.id].parse(tc.raw); got != tc.want {
			t.Errorf("%s got %q, want %q", tc.id, got, tc.want)
		}
	}
	for _, def := range mainstreamClients {
		if check := clientVersionChecks[def.id]; check.arg == "" || check.brand == "" {
			t.Errorf("missing version check for %s", def.id)
		}
	}
	if clientVersionChecks["amp"].arg != "version" {
		t.Fatal("Amp version check should use its documented command")
	}
}

func TestCLIHealthRejectsWritesAndCrossSite(t *testing.T) {
	a := &apiServer{}
	for _, tc := range []struct {
		method, site string
		status       int
	}{{"POST", "", 405}, {"GET", "cross-site", 403}} {
		request := httptest.NewRequest(tc.method, "http://127.0.0.1:8765/api/studio/cli-health", nil)
		request.Header.Set("Sec-Fetch-Site", tc.site)
		response := httptest.NewRecorder()
		a.cliHealth(response, request)
		if response.Code != tc.status || response.Header().Get("Cache-Control") != "no-store" ||
			!strings.Contains(response.Body.String(), "\"error\"") {
			t.Fatalf("unexpected HTTP result: %d %s", response.Code, response.Body.String())
		}
	}
}
