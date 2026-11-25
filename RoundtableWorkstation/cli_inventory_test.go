package main

import (
	"encoding/json"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"scistation.local/desktop/internal/cli"
)

func inventoryFixtureExecutable(t *testing.T, path string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte("#!/bin/sh\nexit 99\n"), 0700); err != nil {
		t.Fatal(err)
	}
}
func inventoryByID(list []installedClient, id string) installedClient {
	for _, c := range list {
		if c.ID == id {
			return c
		}
	}
	return installedClient{}
}
func inventoryNoDiscover(string, string) cli.Info { return cli.Info{} }

func TestInventoryDoesNotRunOrConfuseClients(t *testing.T) {
	root := t.TempDir()
	bin := filepath.Join(root, "bin")
	for _, name := range []string{"codex", "claude", "copilot", "opencode", "qwen", "aider", "kimi", "droid", "agent", "pi", "amp"} {
		inventoryFixtureExecutable(t, filepath.Join(bin, name))
	}
	marker := filepath.Join(root, "ran-client")
	if err := os.WriteFile(filepath.Join(bin, "claude"), []byte("#!/bin/sh\ntouch '"+marker+"'\n"), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(bin, "gemini"), 0700); err != nil {
		t.Fatal(err)
	}
	list := detectClients(root, []string{bin}, nil, inventoryNoDiscover)
	if len(list) != 12 {
		t.Fatalf("got %d clients", len(list))
	}
	for _, id := range []string{"codex", "claude", "copilot", "opencode", "qwen", "aider", "kimi", "droid"} {
		if !inventoryByID(list, id).Installed {
			t.Errorf("missing %s", id)
		}
	}
	if inventoryByID(list, "gemini").Installed {
		t.Fatal("directory counted as CLI")
	}
	for _, id := range []string{"cursor", "pi", "amp"} {
		c := inventoryByID(list, id)
		if c.Installed || c.State != "unverified" {
			t.Errorf("generic %s falsely confirmed: %+v", id, c)
		}
	}
	if _, err := os.Stat(marker); !os.IsNotExist(err) {
		t.Fatal("inventory executed a client")
	}
	if !inventoryByID(list, "codex").Seat || !inventoryByID(list, "cursor").Seat || inventoryByID(list, "claude").Seat {
		t.Fatal("seat capability changed")
	}
}

func TestInventoryOfficialIdentityAndFinderLocations(t *testing.T) {
	home := t.TempDir()
	nvm := filepath.Join(home, ".nvm/versions/node/v22.0.0/bin")
	inventoryFixtureExecutable(t, filepath.Join(nvm, "gemini"))
	native := filepath.Join(home, ".local/share/cursor-agent/versions/2026.11/agent")
	inventoryFixtureExecutable(t, native)
	bin := filepath.Join(home, ".local/bin")
	if err := os.MkdirAll(bin, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(native, filepath.Join(bin, "agent")); err != nil {
		t.Fatal(err)
	}
	npmRoot := filepath.Join(home, ".nvm/versions/node/v22.0.0/lib/node_modules/@earendil-works/pi-coding-agent")
	pi := filepath.Join(npmRoot, "dist/cli.js")
	inventoryFixtureExecutable(t, pi)
	if err := os.WriteFile(filepath.Join(npmRoot, "package.json"), []byte(`{"name":"@earendil-works/pi-coding-agent"}`), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(pi, filepath.Join(nvm, "pi")); err != nil {
		t.Fatal(err)
	}
	inventoryFixtureExecutable(t, filepath.Join(home, ".amp/bin/amp"))
	dirs := inventoryDirectories(home, "", func(string) string { return "" })
	// Avoid machine-wide installations in this isolated fixture.
	fixtureDirs := []string{}
	for _, dir := range dirs {
		if strings.HasPrefix(dir, home+string(os.PathSeparator)) {
			fixtureDirs = append(fixtureDirs, dir)
		}
	}
	list := detectClients(home, fixtureDirs, nil, inventoryNoDiscover)
	for _, id := range []string{"cursor", "pi", "gemini", "amp"} {
		if c := inventoryByID(list, id); !c.Installed || c.State != "installed" {
			t.Errorf("not recognized %s: %+v", id, c)
		}
	}
}

func TestInventoryRejectsGUIAndGhAndNonExecutable(t *testing.T) {
	root := t.TempDir()
	gui := filepath.Join(root, "Antigravity.app/Contents/MacOS")
	inventoryFixtureExecutable(t, filepath.Join(gui, "gemini"))
	inventoryFixtureExecutable(t, filepath.Join(gui, "agent"))
	inventoryFixtureExecutable(t, filepath.Join(gui, "antigravity"))
	bin := filepath.Join(root, "bin")
	inventoryFixtureExecutable(t, filepath.Join(bin, "gh"))
	if err := os.WriteFile(filepath.Join(bin, "aider"), []byte("not executable"), 0600); err != nil {
		t.Fatal(err)
	}
	list := detectClients(root, []string{gui, bin}, nil, inventoryNoDiscover)
	for _, id := range []string{"gemini", "cursor", "copilot", "aider"} {
		if inventoryByID(list, id).Installed {
			t.Errorf("false CLI match %s", id)
		}
	}
}

func TestInventoryExplicitPathAndDiscoveryReuse(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, "codex")
	inventoryFixtureExecutable(t, path)
	calls := []string{}
	discover := func(seat, override string) cli.Info {
		calls = append(calls, seat+":"+override)
		if seat == "codex" {
			return cli.Info{Available: true, Path: path}
		}
		return cli.Info{}
	}
	list := detectClients(root, nil, map[string]string{"codex": path}, discover)
	if !inventoryByID(list, "codex").Installed || len(calls) != 2 || calls[0] != "codex:"+path {
		t.Fatalf("did not reuse cli.Discover: %v", calls)
	}
	missing := filepath.Join(root, "missing")
	list = detectClients(root, []string{root}, map[string]string{"codex": missing}, inventoryNoDiscover)
	if inventoryByID(list, "codex").Installed {
		t.Fatal("explicit override silently fell back")
	}
}

func TestInventorySearchIsBoundedAndIgnoresRelativePATH(t *testing.T) {
	home := t.TempDir()
	nested := filepath.Join(home, "Documents/unrelated-project/bin")
	inventoryFixtureExecutable(t, filepath.Join(nested, "qwen"))
	path := filepath.Join(home, "inherited/bin")
	dirs := inventoryDirectories(home, ".:relative:"+path, func(key string) string {
		if key == "NVM_BIN" {
			return filepath.Join(home, "custom-node/bin")
		}
		return ""
	})
	seen := map[string]bool{}
	for _, dir := range dirs {
		if !filepath.IsAbs(dir) || seen[dir] {
			t.Fatalf("invalid or duplicate search directory %q", dir)
		}
		seen[dir] = true
		if dir == nested {
			t.Fatal("recursive home discovery")
		}
	}
	if !seen[path] || !seen[filepath.Join(home, "custom-node/bin")] {
		t.Fatal("inherited/version-manager PATH missing")
	}
}

func TestInventoryOfficialLinksAndHTTP(t *testing.T) {
	official := map[string]bool{"developers.openai.com": true, "cursor.com": true, "code.claude.com": true, "geminicli.com": true, "docs.github.com": true, "opencode.ai": true, "qwenlm.github.io": true, "aider.chat": true, "github.com": true, "ampcode.com": true, "docs.factory.com": true}
	for _, def := range mainstreamClients {
		u, err := url.Parse(def.installURL)
		if err != nil || u.Scheme != "https" || !official[u.Host] {
			t.Fatalf("nonofficial URL %q", def.installURL)
		}
	}
	a := &apiServer{}
	bad := httptest.NewRecorder()
	a.clients(bad, httptest.NewRequest("POST", "/api/studio/clients", nil))
	if bad.Code != 405 {
		t.Fatal("write method accepted")
	}
	w := httptest.NewRecorder()
	a.clients(w, httptest.NewRequest("GET", "/api/studio/clients", nil))
	if w.Code != 200 {
		t.Fatal(w.Code)
	}
	var data struct {
		Clients []installedClient `json:"clients"`
		Checked string            `json:"checked_at"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &data); err != nil {
		t.Fatal(err)
	}
	if len(data.Clients) != 12 || data.Checked == "" {
		t.Fatal("inventory response incomplete")
	}
	for _, c := range data.Clients {
		if c.Installed != (c.State == "installed") {
			t.Fatalf("inconsistent state: %+v", c)
		}
	}
	if os.Getenv("ROUNDTABLE_INVENTORY_REPORT") == "1" {
		t.Log(w.Body.String())
	}
}
