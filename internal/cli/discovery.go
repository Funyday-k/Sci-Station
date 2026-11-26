// Package cli discovers installed command-line clients for the diagnostic panel.
package cli

import (
	"os"
	"path/filepath"
	"strings"
)

type Info struct {
	Available bool   `json:"available"`
	Path      string `json:"path"`
	Version   string `json:"version,omitempty"`
}

// Discover checks executable locations without starting a client or inspecting
// its account state. An explicit override never silently falls back elsewhere.
func Discover(seat, override string) Info {
	seat = strings.ToLower(strings.TrimSpace(seat))
	if seat != "codex" && seat != "cursor" {
		return Info{}
	}
	if override != "" {
		return executableInfo(override)
	}
	names := []string{"codex"}
	if seat == "cursor" {
		names = []string{"agent", "cursor-agent"}
	}
	for _, dir := range filepath.SplitList(clientPath()) {
		if dir == "" {
			continue
		}
		for _, name := range names {
			if info := executableInfo(filepath.Join(dir, name)); info.Available {
				return info
			}
		}
	}
	if seat == "codex" {
		for _, path := range []string{
			"/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
			"/Applications/Codex.app/Contents/Resources/codex",
		} {
			if info := executableInfo(path); info.Available {
				return info
			}
		}
	}
	return Info{}
}

func executableInfo(path string) Info {
	if strings.HasPrefix(path, "~/") {
		home, _ := os.UserHomeDir()
		path = filepath.Join(home, path[2:])
	}
	if !strings.ContainsRune(path, os.PathSeparator) {
		for _, dir := range filepath.SplitList(clientPath()) {
			if dir == "" {
				continue
			}
			candidate := filepath.Join(dir, path)
			if info := executableInfo(candidate); info.Available {
				return info
			}
		}
		return Info{Path: path}
	}
	absolute, err := filepath.Abs(path)
	if err != nil {
		return Info{Path: path}
	}
	stat, err := os.Stat(absolute)
	return Info{Available: err == nil && stat.Mode().IsRegular() && stat.Mode().Perm()&0111 != 0, Path: absolute}
}

func clientPath() string {
	home, _ := os.UserHomeDir()
	// Finder does not load a login shell's PATH. Keep the inherited PATH first,
	// then add standard official installers and Homebrew locations.
	return strings.Join([]string{os.Getenv("PATH"), filepath.Join(home, ".local", "bin"),
		"/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"}, string(os.PathListSeparator))
}
