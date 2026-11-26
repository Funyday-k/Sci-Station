package desktop

import (
	"context"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"sync"
	"syscall"
	"time"

	"scistation.local/desktop/internal/cli"
)

type clientHealth struct {
	installedClient
	Version string `json:"version,omitempty"`
}

type clientVersionCheck struct {
	arg   string
	brand string
}

var clientVersionChecks = map[string]clientVersionCheck{
	"codex":    {"--version", "codex(?:-cli)?"},
	"cursor":   {"--version", "(?:cursor agent|cursor-agent|agent)"},
	"claude":   {"--version", "claude(?: code)?"},
	"gemini":   {"--version", "gemini(?: cli)?"},
	"copilot":  {"--version", "(?:github )?copilot(?: cli)?"},
	"opencode": {"--version", "opencode"},
	"qwen":     {"--version", "qwen(?: code)?"},
	"aider":    {"--version", "aider(?:-chat)?"},
	"kimi":     {"--version", "kimi(?: code(?: cli)?)?"},
	"pi":       {"--version", "pi(?: coding agent)?"},
	"amp":      {"version", "amp(?: cli)?"},
	"droid":    {"--version", "droid(?: cli)?"},
}

var versionWorkers = make(chan struct{}, 4)

func (a *apiServer) cliHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
		reject(w, http.StatusMethodNotAllowed, "仅支持读取")
		return
	}
	origin := r.Header.Get("Origin")
	if r.Header.Get("Sec-Fetch-Site") == "cross-site" || (origin != "" && origin != "http://"+r.Host) {
		reject(w, http.StatusForbidden, "请从本机圆桌检查")
		return
	}
	home, dirs, overrides := a.clientInventorySources()
	if home != "" {
		for _, dir := range []string{".kimi-code/bin", ".local/lib/qwen-code/bin", ".local/share/gh/copilot", ".local/share/pipx/venvs/aider-chat/bin"} {
			dirs = append(dirs, filepath.Join(home, dir))
		}
	}
	candidates := detectClientsBy(home, dirs, overrides, cli.Discover, installedCLIIdentity)
	ctx, cancel := context.WithTimeout(r.Context(), 18*time.Second)
	defer cancel()
	clients := checkInstalledClients(ctx, home, candidates)
	reply(w, http.StatusOK, map[string]any{"clients": clients, "checked_at": time.Now().UTC().Format(time.RFC3339Nano)})
}

// Unlike the compatibility inventory, a runnable candidate needs evidence
// from a recognized installation layout or a matching installed package.
func installedCLIIdentity(def clientDefinition, home, path, resolved string) bool {
	if !slices.Contains(def.commands, filepath.Base(path)) {
		return false
	}
	if hasInstalledNPMPackage(resolved, def.packages) {
		return true
	}
	if def.id == "codex" && (resolved == "/Applications/Codex.app/Contents/Resources/codex" ||
		resolved == "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex") {
		return true
	}

	brewName := map[string][]string{
		"codex": {"codex"}, "claude": {"claude-code"}, "gemini": {"gemini-cli"},
		"copilot": {"copilot-cli", "copilot-cli@prerelease"}, "opencode": {"opencode", "opencode-v2"},
		"qwen": {"qwen-code"}, "aider": {"aider"}, "pi": {"pi-coding-agent"},
		"amp": {"amp"}, "droid": {"droid"},
	}
	for _, name := range brewName[def.id] {
		for _, brew := range []string{"/opt/homebrew", "/usr/local"} {
			if matchesCLIPath(brew, "Cellar/"+name+"/*/bin/"+def.commands[0], resolved) ||
				matchesCLIPath(brew, "Cellar/"+name+"/*/libexec/bin/"+def.commands[0], resolved) ||
				matchesCLIPath(brew, "Caskroom/"+name+"/*/"+def.commands[0], resolved) {
				return true
			}
		}
	}

	if realHome, err := filepath.EvalSymlinks(home); err == nil {
		home = realHome
	}
	native := map[string][]string{
		"cursor":   {".local/share/cursor-agent/versions/*/agent", ".local/share/cursor-agent/versions/*/cursor-agent", ".cursor-agent/versions/*/cursor-agent"},
		"claude":   {".local/share/claude/versions/*"},
		"copilot":  {".local/share/gh/copilot/copilot"},
		"opencode": {".opencode/bin/opencode"},
		"qwen":     {".local/lib/qwen-code/bin/qwen"},
		"aider":    {".local/pipx/venvs/aider-chat/bin/aider", ".local/share/pipx/venvs/aider-chat/bin/aider", ".local/share/uv/tools/aider-chat/bin/aider"},
		"kimi":     {".local/share/kimi-code/versions/*/kimi", ".local/share/kimi-code/bin/kimi", ".kimi-code/bin/kimi", ".local/share/uv/tools/kimi-cli/bin/kimi"},
		"amp":      {".amp/bin/amp"},
		"droid":    {".factory/bin/droid", ".factory/versions/*/droid"},
	}
	for _, pattern := range native[def.id] {
		if home != "" && matchesCLIPath(home, pattern, resolved) {
			return true
		}
	}
	return false
}

func matchesCLIPath(root, pattern, executable string) bool {
	ok, _ := filepath.Match(filepath.Join(root, pattern), executable)
	return ok
}

func hasInstalledNPMPackage(executable string, names []string) bool {
	var candidates []string
	for _, name := range names {
		// Avoid accepting an unrelated unscoped npm package called droid.
		if name != "droid" && name != "kimi-cli" &&
			strings.Contains(filepath.ToSlash(executable), "/node_modules/"+name+"/") {
			candidates = append(candidates, name)
		}
	}
	return len(candidates) > 0 && inventoryPackageMatches(executable, candidates)
}

func checkInstalledClients(ctx context.Context, home string, candidates []installedClient) []clientHealth {
	definitions := make(map[string]clientDefinition, len(mainstreamClients))
	for _, def := range mainstreamClients {
		definitions[def.id] = def
	}
	results := make([]clientHealth, 0, len(candidates))
	for _, candidate := range candidates {
		if candidate.Installed && candidate.State == "installed" {
			results = append(results, clientHealth{installedClient: candidate})
		}
	}
	var checks sync.WaitGroup
	for i := range results {
		checks.Add(1)
		go func(result *clientHealth) {
			defer checks.Done()
			def := definitions[result.ID]
			versionCheck, known := clientVersionChecks[result.ID]
			path, err := filepath.EvalSymlinks(result.Path)
			if err != nil || !filepath.IsAbs(path) || !inventoryExecutable(path) ||
				!known || !installedCLIIdentity(def, home, result.Path, path) {
				result.State = "unverified"
				return
			}
			// The last archived Python Kimi CLI release redirects entry points
			// into an installer. Leave that version unchecked.
			if result.ID == "kimi" && strings.Contains(filepath.ToSlash(path), "/tools/kimi-cli/") {
				result.State = "unverified"
				return
			}
			result.State = "check_failed"
			select {
			case versionWorkers <- struct{}{}:
				defer func() { <-versionWorkers }()
			case <-ctx.Done():
				return
			}
			output, err := runClientVersion(ctx, path, versionCheck.arg)
			if err == nil {
				result.Version = versionCheck.parse(output)
				if result.Version != "" {
					result.State = "ready"
				}
			}
		}(&results[i])
	}
	checks.Wait()
	return results
}

func (check clientVersionCheck) parse(raw string) string {
	// Only lift a tightly shaped version from a line on its own. Raw stdout
	// and stderr can contain account details, paths and arbitrary warnings.
	pattern := regexp.MustCompile(`(?im)^(?:(?:` + check.brand + `)(?: version)?[ :]+)?v?([0-9]{1,4}\.[0-9]{1,5}(?:\.[0-9]{1,8})?(?:[-+][a-z0-9.-]{1,32})?)(?:[ \t]+\((?:` + check.brand + `)\))?[ \t\r]*$`)
	match := pattern.FindStringSubmatch(strings.TrimSpace(raw))
	if len(match) == 2 {
		return match[1]
	}
	return ""
}

func versionRuntimePath(home, executable string) string {
	dirs := []string{"/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin", "/usr/bin", "/bin"}
	prefix, _, insideNode := strings.Cut(executable, string(filepath.Separator)+"lib"+string(filepath.Separator)+"node_modules"+string(filepath.Separator))
	if realHome, err := filepath.EvalSymlinks(home); err == nil {
		home = realHome
	}
	if insideNode && home != "" {
		for _, pattern := range []string{".nvm/versions/node/*", ".fnm/node-versions/*/installation", "Library/Application Support/fnm/node-versions/*/installation", ".local/share/fnm/node-versions/*/installation", ".local/share/mise/installs/node/*"} {
			if matchesCLIPath(home, pattern, prefix) {
				dirs = append([]string{filepath.Join(prefix, "bin")}, dirs...)
				break
			}
		}
	}
	return strings.Join(dirs, string(os.PathListSeparator))
}

func runClientVersion(parent context.Context, executable, arg string) (string, error) {
	ctx, cancel := context.WithTimeout(parent, 5*time.Second)
	defer cancel()
	dir, err := os.MkdirTemp("", "roundtable-cli-check-")
	if err != nil {
		return "", err
	}
	defer os.RemoveAll(dir)

	cmd := exec.CommandContext(ctx, executable, arg)
	cmd.Dir = dir
	home, _ := os.UserHomeDir()
	cmd.Env = []string{
		"PATH=" + versionRuntimePath(home, executable),
		"NO_COLOR=1", "NO_OPEN_BROWSER=1", "DO_NOT_TRACK=1", "DISABLE_AUTOUPDATER=1",
		"COPILOT_AUTO_UPDATE=false", "DISABLE_TELEMETRY=1", "PI_OFFLINE=1",
		"OPENCODE_DISABLE_AUTOUPDATE=true", "AIDER_CHECK_UPDATE=false",
		"XDG_CONFIG_HOME=" + dir, "XDG_CACHE_HOME=" + dir, "XDG_STATE_HOME=" + dir, "XDG_DATA_HOME=" + dir,
	}
	if home != "" {
		cmd.Env = append(cmd.Env, "HOME="+home)
	}
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error {
		return syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
	}
	cmd.WaitDelay = time.Second
	var out diagnosticBuffer
	cmd.Stdout, cmd.Stderr = &out, &out
	if err := cmd.Run(); err != nil {
		return "", err
	}
	if out.overflow {
		return "", nil
	}
	return out.String(), nil
}
