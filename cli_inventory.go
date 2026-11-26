package main

import (
	"encoding/json"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"scistation.local/desktop/internal/cli"
)

type installedClient struct {
	ID         string `json:"id"`
	Name       string `json:"name"`
	Installed  bool   `json:"installed"`
	Path       string `json:"path,omitempty"`
	Command    string `json:"command"`
	Seat       bool   `json:"seat"`
	InstallURL string `json:"install_url,omitempty"`
	State      string `json:"state"`
}

type clientDefinition struct {
	id, name   string
	commands   []string
	installURL string
	packages   []string
}

// Installation references are first-party documentation. Inventory never runs
// these commands, package managers, shells, installers or account checks.
var mainstreamClients = []clientDefinition{
	{"codex", "Codex", []string{"codex"}, "https://developers.openai.com/codex/cli", []string{"@openai/codex"}},
	{"cursor", "Cursor Agent", []string{"agent", "cursor-agent"}, "https://cursor.com/docs/cli/overview", nil},
	{"claude", "Claude Code", []string{"claude"}, "https://code.claude.com/docs/en/setup", []string{"@anthropic-ai/claude-code"}},
	{"gemini", "Gemini CLI", []string{"gemini"}, "https://geminicli.com/docs/get-started/installation/", []string{"@google/gemini-cli"}},
	{"copilot", "GitHub Copilot CLI", []string{"copilot"}, "https://docs.github.com/en/copilot/how-tos/copilot-cli/set-up-copilot-cli/install-copilot-cli", []string{"@github/copilot"}},
	{"opencode", "OpenCode", []string{"opencode"}, "https://opencode.ai/docs/", []string{"@opencode/cli", "opencode-ai"}},
	{"qwen", "Qwen Code", []string{"qwen"}, "https://qwenlm.github.io/qwen-code-docs/en/users/quickstart/", []string{"@qwen-code/qwen-code"}},
	{"aider", "Aider", []string{"aider"}, "https://aider.chat/docs/install.html", nil},
	{"kimi", "Kimi CLI", []string{"kimi"}, "https://github.com/MoonshotAI/kimi-code", []string{"@moonshot-ai/kimi-code", "kimi-cli"}},
	{"pi", "Pi", []string{"pi"}, "https://github.com/earendil-works/pi/tree/main/packages/coding-agent", []string{"@earendil-works/pi-coding-agent", "@mariozechner/pi-coding-agent"}},
	{"amp", "Amp", []string{"amp"}, "https://ampcode.com/docs/cli", []string{"@sourcegraph/amp"}},
	{"droid", "Droid", []string{"droid"}, "https://docs.factory.com/droid-cli/quickstart", []string{"droid", "@factory-ai/cli"}},
}

func (a *apiServer) clients(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", "GET")
		reject(w, http.StatusMethodNotAllowed, "仅支持读取")
		return
	}
	home, dirs, overrides := a.clientInventorySources()
	reply(w, 200, map[string]any{"clients": detectClients(home, dirs, overrides, cli.Discover), "checked_at": time.Now().UTC().Format(time.RFC3339Nano)})
}

func (a *apiServer) clientInventorySources() (string, []string, map[string]string) {
	var overrides map[string]string
	if a.prefs != nil {
		overrides = a.prefs.get().CLIPaths
	}
	home, _ := os.UserHomeDir()
	return home, inventoryDirectories(home, os.Getenv("PATH"), os.Getenv), overrides
}

// Finder inherits a small PATH. Search only documented/common executable
// directories and bounded version-manager patterns, not the user's home tree.
// An interactive shell's aliases/functions cannot be inspected without running
// it; inherited PATH is honored, but no shell profile or account file is read.
func inventoryDirectories(home, inherited string, getenv func(string) string) []string {
	out := []string{}
	seen := map[string]bool{}
	add := func(path string) {
		if !filepath.IsAbs(path) {
			return
		}
		path = filepath.Clean(path)
		if !seen[path] {
			out = append(out, path)
			seen[path] = true
		}
	}
	for _, p := range filepath.SplitList(inherited) {
		add(p)
	}
	for _, p := range []string{".local/bin", ".npm-global/bin", ".npm/bin", ".yarn/bin", ".volta/bin", ".bun/bin", ".cargo/bin", ".local/share/pnpm", ".opencode/bin", ".amp/bin", ".factory/bin", ".kimi/bin", ".local/share/mise/shims"} {
		if home != "" {
			add(filepath.Join(home, p))
		}
	}
	for _, p := range []string{"/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin", "/usr/bin", "/bin"} {
		add(p)
	}
	for _, key := range []string{"NVM_BIN", "PNPM_HOME"} {
		add(getenv(key))
	}
	for _, key := range []string{"NPM_CONFIG_PREFIX", "npm_config_prefix", "VOLTA_HOME", "BUN_INSTALL"} {
		if p := getenv(key); p != "" {
			add(filepath.Join(p, "bin"))
		}
	}
	if home != "" {
		for _, pattern := range []string{".nvm/versions/node/*/bin", ".fnm/node-versions/*/installation/bin", "Library/Application Support/fnm/node-versions/*/installation/bin", ".local/share/fnm/node-versions/*/installation/bin", ".local/share/mise/installs/node/*/bin"} {
			paths, _ := filepath.Glob(filepath.Join(home, pattern))
			if len(paths) > 64 {
				paths = paths[len(paths)-64:]
			}
			for i := len(paths) - 1; i >= 0; i-- {
				add(paths[i])
			}
		}
		for _, pattern := range []string{"Library/Python/*/bin", ".local/pipx/venvs/aider-chat/bin", ".local/share/uv/tools/aider-chat/bin", ".local/share/uv/tools/kimi-cli/bin"} {
			paths, _ := filepath.Glob(filepath.Join(home, pattern))
			if len(paths) > 32 {
				paths = paths[:32]
			}
			for _, p := range paths {
				add(p)
			}
		}
	}
	return out
}

func detectClients(home string, dirs []string, overrides map[string]string, discover func(string, string) cli.Info) []installedClient {
	return detectClientsBy(home, dirs, overrides, discover, clientIdentity)
}

func detectClientsBy(home string, dirs []string, overrides map[string]string, discover func(string, string) cli.Info, identity func(clientDefinition, string, string, string) bool) []installedClient {
	out := make([]installedClient, 0, len(mainstreamClients))
	for _, def := range mainstreamClients {
		item := installedClient{ID: def.id, Name: def.name, Command: def.commands[0], Seat: def.id == "codex" || def.id == "cursor", InstallURL: def.installURL, State: "not_found"}
		candidates := []string{}
		explicit := overrides[def.id]
		if item.Seat && discover != nil {
			info := discover(def.id, explicit)
			if info.Available {
				candidates = append(candidates, info.Path)
			}
		}
		if explicit != "" {
			if filepath.IsAbs(explicit) {
				candidates = append(candidates, explicit)
			}
		} else {
			for _, dir := range dirs {
				for _, command := range def.commands {
					candidates = append(candidates, filepath.Join(dir, command))
				}
			}
		}
		seen := map[string]bool{}
		for _, candidate := range candidates {
			if !filepath.IsAbs(candidate) || seen[candidate] || !inventoryExecutable(candidate) {
				continue
			}
			seen[candidate] = true
			resolved, err := filepath.EvalSymlinks(candidate)
			if err != nil {
				continue
			}
			// A GUI executable is not evidence that its separate terminal agent exists.
			// Codex's bundled CLI is the explicit, already-supported exception.
			if def.id != "codex" && strings.Contains(filepath.ToSlash(resolved), ".app/Contents/") {
				continue
			}
			if !identity(def, home, candidate, resolved) {
				if item.State == "not_found" {
					item.State = "unverified"
					item.Path = candidate
				}
				continue
			}
			item.Installed = true
			item.State = "installed"
			item.Path = candidate
			break
		}
		out = append(out, item)
	}
	return out
}

func inventoryExecutable(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.Mode().IsRegular() && info.Mode().Perm()&0111 != 0
}

func clientIdentity(def clientDefinition, home, path, resolved string) bool {
	if canonicalHome, err := filepath.EvalSymlinks(home); err == nil {
		home = canonicalHome
	}
	base := filepath.Base(path)
	// agent, pi and amp are shared by unrelated software. A name alone is not
	// enough; use installation layout or nearby *package* metadata, never auth.
	strict := def.id == "pi" || def.id == "amp" || (def.id == "cursor" && base == "agent")
	if !strict {
		return true
	}
	if inventoryPackageMatches(resolved, def.packages) {
		return true
	}
	clean := filepath.ToSlash(resolved)
	if def.id == "cursor" {
		if home != "" {
			for _, location := range []string{".local/share/cursor-agent", ".cursor-agent"} {
				prefix := filepath.ToSlash(filepath.Join(home, location)) + "/"
				if strings.HasPrefix(clean, prefix) {
					return true
				}
			}
		}
		// Official user-local launcher may be a regular script, not a symlink.
		script := inventoryLauncher(path)
		return strings.Contains(script, "cursor-agent") && (strings.Contains(script, ".local/share/") || strings.Contains(script, "cursor.com"))
	}
	if home != "" && def.id == "amp" {
		canonical := filepath.Join(home, ".amp", "bin", "amp")
		return filepath.Clean(resolved) == canonical
	}
	return false
}

func inventoryPackageMatches(executable string, names []string) bool {
	// Resolve npm/pnpm symlinks, then inspect at most eight parent directories.
	// Read only the package name from a bounded package.json file.
	dir := filepath.Dir(executable)
	for depth := 0; depth < 8; depth++ {
		metadata := filepath.Join(dir, "package.json")
		stat, statErr := os.Stat(metadata)
		if statErr == nil && stat.Mode().IsRegular() && stat.Size() <= 65536 {
			f, err := os.Open(metadata)
			if err == nil {
				var p struct {
					Name string `json:"name"`
				}
				decodeErr := json.NewDecoder(io.LimitReader(f, 65536)).Decode(&p)
				f.Close()
				if decodeErr == nil {
					for _, name := range names {
						if p.Name == name {
							return true
						}
					}
				}
			}
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	return false
}
func inventoryLauncher(path string) string {
	f, err := os.Open(path)
	if err != nil {
		return ""
	}
	defer f.Close()
	b, err := io.ReadAll(io.LimitReader(f, 8192))
	if err != nil || !strings.HasPrefix(string(b), "#!") {
		return ""
	}
	return string(b)
}
