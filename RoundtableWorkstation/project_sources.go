package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

type projectCandidate struct {
	Path    string   `json:"path"`
	Name    string   `json:"name"`
	Sources []string `json:"sources"`
}

func discoverProjects(registered map[string]projectRecord) []projectCandidate {
	home, err := os.UserHomeDir()
	if err != nil {
		return []projectCandidate{}
	}
	config, _ := os.UserConfigDir()
	codexDir := os.Getenv("CODEX_HOME")
	if codexDir == "" {
		codexDir = filepath.Join(home, ".codex")
	}
	claudeDir := os.Getenv("CLAUDE_CONFIG_DIR")
	if claudeDir == "" {
		claudeDir = filepath.Join(home, ".claude")
	}

	byPath := make(map[string]*projectCandidate)
	add := func(path, source string) {
		clean, err := cleanProjectPath(path)
		if err != nil {
			return
		}
		candidate := byPath[clean]
		if candidate == nil {
			candidate = &projectCandidate{Path: clean, Name: filepath.Base(clean), Sources: []string{}}
			byPath[clean] = candidate
		}
		for _, existing := range candidate.Sources {
			if existing == source {
				return
			}
		}
		candidate.Sources = append(candidate.Sources, source)
	}
	for path := range registered {
		add(path, "工作圆桌")
	}
	for _, path := range codexProjectPaths(codexDir) {
		add(path, "Codex")
	}
	for _, path := range indexedProjectPaths(home, filepath.Join(claudeDir, "projects"), true) {
		add(path, "Claude Code")
	}
	for _, path := range indexedProjectPaths(home, filepath.Join(home, ".cursor", "projects"), false) {
		add(path, "Cursor CLI")
	}
	if config != "" {
		for _, profile := range []string{"Cursor", "Cursor Nightly"} {
			storage := filepath.Join(config, profile, "User", "workspaceStorage")
			for _, path := range cursorWorkspacePaths(storage) {
				add(path, "Cursor 工作区")
			}
		}
	}
	candidates := make([]projectCandidate, 0, len(byPath))
	for _, candidate := range byPath {
		candidates = append(candidates, *candidate)
	}
	sort.Slice(candidates, func(i, j int) bool { return candidates[i].Path < candidates[j].Path })
	return candidates
}

var codexProjectHeader = regexp.MustCompile(`^\[\s*projects\s*\.\s*("(?:[^"\\]|\\.)*"|'[^']*')\s*\]\s*(?:#.*)?$`)

func codexProjectPaths(dir string) []string {
	var paths []string
	root, err := openProjectDirectory(filepath.Clean(dir))
	if err != nil {
		return paths
	}
	defer root.Close()
	// Parse only known-project table headers. Config values, trust levels, and
	// companion files are outside of this import.
	body, err := readProjectRegular(root, "config.toml", 512<<10)
	if err != nil {
		return paths
	}
	scanner := bufio.NewScanner(bytes.NewReader(body))
	scanner.Buffer(make([]byte, 8192), len(body)+1)
	for scanner.Scan() {
		match := codexProjectHeader.FindStringSubmatch(strings.TrimSpace(scanner.Text()))
		if len(match) == 0 {
			continue
		}
		path := match[1]
		if path[0] == '\'' {
			paths = append(paths, path[1:len(path)-1])
		} else if value, err := strconv.Unquote(path); err == nil {
			paths = append(paths, value)
		}
	}
	return paths
}

func projectIndexKey(path string) string {
	return strings.Map(func(r rune) rune {
		if r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' || r == '_' || r == '-' {
			return r
		}
		return '-'
	}, filepath.ToSlash(path))
}

func indexedProjectPaths(home, index string, leadingDash bool) []string {
	var paths []string
	prefix := projectIndexKey(filepath.Clean(home)) + "-"
	if !leadingDash {
		prefix = strings.TrimPrefix(prefix, "-")
	}
	root, err := openProjectDirectory(filepath.Clean(index))
	if err != nil {
		return paths
	}
	defer root.Close()
	file, err := root.Open(".")
	if err != nil {
		return paths
	}
	defer file.Close()
	entries, _ := file.ReadDir(1024)
	for _, entry := range entries {
		if entry.IsDir() && strings.HasPrefix(entry.Name(), prefix) {
			path := resolveIndexProject(home, strings.TrimPrefix(entry.Name(), prefix))
			if path != "" {
				paths = append(paths, path)
			}
		}
	}
	return paths
}

// CLI project index names encode path separators as dashes. Reconstruct only
// existing, unambiguous paths below home. The index's contents are never read.
func resolveIndexProject(home, suffix string) string {
	if suffix == "" || len(suffix) > 512 || projectIndexKey(suffix) != suffix {
		return ""
	}
	var matches []string
	budget := 256
	var visit func(string, string, int)
	visit = func(parent, remainder string, depth int) {
		if depth > 16 || len(matches) > 1 {
			return
		}
		for end := 1; end <= len(remainder); end++ {
			if end < len(remainder) && remainder[end] != '-' {
				continue
			}
			name := remainder[:end]
			names := []string{name}
			if strings.HasPrefix(name, "-") && len(name) > 1 {
				names = append(names, "."+name[1:])
			}
			for _, name := range names {
				if budget == 0 || len(matches) > 1 {
					return
				}
				budget--
				path := filepath.Join(parent, name)
				entry, err := os.Lstat(path)
				if err != nil || !entry.IsDir() {
					continue
				}
				if end == len(remainder) {
					matches = append(matches, path)
				} else {
					visit(path, remainder[end+1:], depth+1)
				}
			}
		}
	}
	visit(home, suffix, 1)
	if len(matches) == 1 && budget > 0 {
		return matches[0]
	}
	return ""
}

func localWorkspaceURI(text string) string {
	parsed, err := url.Parse(text)
	if err != nil || parsed.Scheme != "file" || parsed.User != nil || parsed.Opaque != "" || parsed.RawQuery != "" || parsed.Fragment != "" {
		return ""
	}
	if parsed.Host != "" && !strings.EqualFold(parsed.Host, "localhost") {
		return ""
	}
	path := filepath.FromSlash(parsed.Path)
	if !filepath.IsAbs(path) {
		return ""
	}
	return path
}

func cursorWorkspacePaths(storage string) []string {
	var paths []string
	root, err := openProjectDirectory(filepath.Clean(storage))
	if err != nil {
		return paths
	}
	defer root.Close()
	file, err := root.Open(".")
	if err != nil {
		return paths
	}
	defer file.Close()
	dirs, _ := file.ReadDir(1024)
	for _, entry := range dirs {
		if !entry.IsDir() {
			continue
		}
		workspace, err := openProjectSubdir(root, entry.Name())
		if err != nil {
			continue
		}
		body, err := readProjectRegular(workspace, "workspace.json", 16<<10)
		workspace.Close()
		if err != nil {
			continue
		}
		var record struct {
			Folder    string `json:"folder"`
			Workspace string `json:"workspace"`
		}
		if json.Unmarshal(body, &record) != nil {
			continue
		}
		if path := localWorkspaceURI(record.Folder); path != "" {
			paths = append(paths, path)
		}
		if file := localWorkspaceURI(record.Workspace); filepath.Ext(file) == ".code-workspace" {
			paths = append(paths, cursorFileFolders(file)...)
		}
	}
	return paths
}

func cursorFileFolders(path string) []string {
	dir, filename := filepath.Split(path)
	root, err := openProjectDirectory(filepath.Clean(dir))
	if err != nil {
		return nil
	}
	defer root.Close()
	body, err := readProjectRegular(root, filename, 256<<10)
	if err != nil {
		return nil
	}
	var data struct {
		Folders []struct {
			Path string `json:"path"`
			URI  string `json:"uri"`
		} `json:"folders"`
	}
	if json.Unmarshal(workspaceJSON(body), &data) != nil {
		return nil
	}
	paths := make([]string, 0, len(data.Folders))
	for _, folder := range data.Folders {
		if folder.Path != "" && folder.URI == "" {
			path := folder.Path
			if !filepath.IsAbs(path) {
				path = filepath.Join(dir, path)
			}
			paths = append(paths, path)
		} else if path := localWorkspaceURI(folder.URI); folder.Path == "" && path != "" {
			paths = append(paths, path)
		}
	}
	return paths
}

// Workspace files permit JSON comments and trailing commas. Keep string
// literals intact while dropping comments and trailing separators.
func workspaceJSON(data []byte) []byte {
	clean := make([]byte, 0, len(data))
	inString := false
	for i := 0; i < len(data); i++ {
		char := data[i]
		switch {
		case char == '"' || inString:
			clean = append(clean, char)
			if char == '"' {
				inString = !inString
			} else if char == '\\' && i+1 < len(data) {
				i++
				clean = append(clean, data[i])
			}
		case char == '/' && i+1 < len(data) && data[i+1] == '/':
			clean = append(clean, ' ')
			for i+1 < len(data) && data[i+1] != '\n' && data[i+1] != '\r' {
				i++
			}
		case char == '/' && i+1 < len(data) && data[i+1] == '*':
			end := bytes.Index(data[i+2:], []byte("*/"))
			if end < 0 {
				return nil
			}
			clean = append(clean, ' ')
			i += end + 3
		default:
			clean = append(clean, char)
		}
	}
	normalized := clean[:0]
	for i := 0; i < len(clean); i++ {
		char := clean[i]
		switch {
		case char == '"' || inString:
			normalized = append(normalized, char)
			if char == '"' {
				inString = !inString
			} else if char == '\\' && i+1 < len(clean) {
				i++
				normalized = append(normalized, clean[i])
			}
		case char == ',':
			tail := bytes.TrimLeft(clean[i+1:], " \r\n\t")
			if len(tail) > 0 && tail[0] != ']' && tail[0] != '}' {
				normalized = append(normalized, char)
			}
		default:
			normalized = append(normalized, char)
		}
	}
	return normalized
}
