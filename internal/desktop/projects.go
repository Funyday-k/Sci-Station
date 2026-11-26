package desktop

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"syscall"
	"unicode"
	"unicode/utf8"

	"scistation.local/desktop/internal/meeting"
	"scistation.local/desktop/internal/research"
	"scistation.local/desktop/internal/workspace"
)

const (
	maxProjectSelections  = 12
	maxProjectRules       = 24
	maxRuleBytes          = 32 << 10
	maxProjectContext     = 64 << 10
	maxRegisteredProjects = 256
)

type projectRuleRef = meeting.ProjectRuleVersion

type projectRule struct {
	projectRuleRef
	Source string `json:"source"`
	Text   string `json:"text"`
}

type projectRecord struct {
	disk           json.RawMessage
	DirectoryGrant *research.DirectoryGrant `json:"directoryGrant,omitempty"`
	Path           string                   `json:"path"`
	Rules          []projectRule            `json:"rules"`
}

type projectSummary struct {
	ID        string `json:"id,omitempty"`
	Path      string `json:"path"`
	Name      string `json:"name"`
	RuleCount int    `json:"rule_count"`
}

type projectRulePreview struct {
	projectRule
	Imported bool `json:"imported"`
}

type projectPreview struct {
	Path    string               `json:"path"`
	Name    string               `json:"name"`
	Rules   []projectRulePreview `json:"rules"`
	Omitted int                  `json:"omitted"`
}

type projectImportSelection struct {
	Path  string           `json:"path"`
	Rules []projectRuleRef `json:"rules"`
}

type projectImportRequest struct {
	Action     string                   `json:"action"`
	Paths      []string                 `json:"paths"`
	Selections []projectImportSelection `json:"selections"`
}

type projectRulesView struct {
	Project projectSummary `json:"project"`
	Rules   []projectRule  `json:"rules"`
}

var projectsMu sync.RWMutex
var errProjectRuleChanged = errors.New("规则文件已更新，请重新预览后再导入。")

func (a *apiServer) projectsFile() string {
	return filepath.Join(filepath.Dir(a.prefs.file), "projects.json")
}

func loadProjectRecords(file string) (map[string]projectRecord, error) {
	data, err := workspace.ManagedReadFile(file)
	if errors.Is(err, os.ErrNotExist) {
		return make(map[string]projectRecord), nil
	}
	if err != nil {
		return nil, fmt.Errorf("无法读取项目规则配置：%w", err)
	}
	var projects map[string]projectRecord
	if err := json.Unmarshal(data, &projects); err != nil {
		return nil, fmt.Errorf("无法读取项目规则配置：%w", err)
	}
	invalid := errors.New("无法读取项目规则配置：项目记录格式无效")
	if projects == nil || len(projects) > maxRegisteredProjects {
		return nil, invalid
	}
	for path, project := range projects {
		if !registeredProjectPath(path) || project.Path != path || project.Rules == nil || len(project.Rules) > maxProjectRules {
			return nil, invalid
		}
		seen := make(map[string]bool, len(project.Rules))
		for _, rule := range project.Rules {
			if seen[rule.Path] || rule.Source == "" || rule.Source != projectRuleSource(rule.Path) ||
				!validProjectRuleText(rule.Text) || rule.Digest != projectRuleDigest(rule.Text) {
				return nil, invalid
			}
			seen[rule.Path] = true
		}
		if len(projectContextText(project.Rules)) > maxProjectContext {
			return nil, invalid
		}
	}
	var raw map[string]json.RawMessage
	if err := json.Unmarshal(data, &raw); err != nil {
		return nil, err
	}
	for path, project := range projects {
		project.disk = raw[path]
		projects[path] = project
	}
	return projects, nil
}

func saveProjectRecords(file string, projects map[string]projectRecord) error {
	updated := make(map[string]json.RawMessage, len(projects))
	for path, record := range projects {
		data, err := marshalProjectRecord(record)
		if err != nil {
			return err
		}
		updated[path] = data
	}
	body, err := json.MarshalIndent(updated, "", "  ")
	if err != nil {
		return err
	}
	return atomicFile(file, body)
}

// Keep unrecognized registry fields when updating approved rule snapshots.
func marshalProjectRecord(record projectRecord) (json.RawMessage, error) {
	if record.disk == nil {
		return json.Marshal(record)
	}
	var out map[string]json.RawMessage
	if err := json.Unmarshal(record.disk, &out); err != nil {
		return nil, err
	}
	var originals []json.RawMessage
	if err := json.Unmarshal(out["rules"], &originals); err != nil {
		return nil, err
	}
	byPath := map[string]json.RawMessage{}
	for _, raw := range originals {
		var old projectRule
		if err := json.Unmarshal(raw, &old); err != nil {
			return nil, err
		}
		byPath[old.Path] = raw
	}
	rules := make([]json.RawMessage, 0, len(record.Rules))
	for _, rule := range record.Rules {
		raw, err := overlayFields(byPath[rule.Path], rule)
		if err != nil {
			return nil, err
		}
		rules = append(rules, raw)
	}
	out["rules"], _ = json.Marshal(rules)
	if record.DirectoryGrant != nil {
		raw, err := overlayFields(out["directoryGrant"], record.DirectoryGrant)
		if err != nil {
			return nil, err
		}
		out["directoryGrant"] = raw
	}
	return json.Marshal(out)
}
func overlayFields(raw json.RawMessage, value any) (json.RawMessage, error) {
	known, err := json.Marshal(value)
	if err != nil || len(raw) == 0 {
		return known, err
	}
	var original, fields map[string]json.RawMessage
	if err = json.Unmarshal(raw, &original); err != nil {
		return nil, err
	}
	if original == nil {
		return known, nil
	}
	if err = json.Unmarshal(known, &fields); err != nil {
		return nil, err
	}
	for key, value := range fields {
		original[key] = value
	}
	return json.Marshal(original)
}

func (a *apiServer) projectRecords() (map[string]projectRecord, error) {
	projectsMu.RLock()
	defer projectsMu.RUnlock()
	return loadProjectRecords(a.projectsFile())
}

func projectSummaries(records map[string]projectRecord) []projectSummary {
	summaries := make([]projectSummary, 0, len(records))
	for _, project := range records {
		summaries = append(summaries, project.summary())
	}
	sort.Slice(summaries, func(i, j int) bool {
		return summaries[i].Path < summaries[j].Path
	})
	return summaries
}

func (p projectRecord) summary() projectSummary {
	return projectSummary{Path: p.Path, Name: filepath.Base(p.Path), RuleCount: len(p.Rules)}
}

func registeredProjectPath(path string) bool {
	return filepath.IsAbs(path) && path == filepath.Clean(path) && strings.IndexFunc(path, unicode.IsControl) < 0
}

func cleanProjectPath(path string) (string, error) {
	path = strings.TrimSpace(path)
	if strings.IndexFunc(path, unicode.IsControl) >= 0 {
		return "", errors.New("项目文件夹路径含有控制字符")
	}
	for _, part := range strings.Split(path, string(filepath.Separator)) {
		if part == ".." {
			return "", errors.New("请输入项目文件夹的完整路径")
		}
	}
	return workspace.Validate(path)
}

// Open each directory by name, holding its parent open and checking the identity
// across the open. Root also prevents a symlink replacement from escaping the parent.
func openProjectDirectory(path string) (*os.Root, error) {
	if !filepath.IsAbs(path) || path != filepath.Clean(path) {
		return nil, errors.New("只支持绝对目录路径")
	}
	base := filepath.VolumeName(path) + string(filepath.Separator)
	root, err := os.OpenRoot(base)
	if err != nil {
		return nil, err
	}
	rel := strings.TrimPrefix(path, base)
	if rel == "" {
		return root, nil
	}
	for _, part := range strings.Split(rel, string(filepath.Separator)) {
		next, err := openProjectSubdir(root, part)
		root.Close()
		if err != nil {
			return nil, err
		}
		root = next
	}
	return root, nil
}

func openProjectSubdir(root *os.Root, name string) (*os.Root, error) {
	info, err := root.Lstat(name)
	if err != nil {
		return nil, err
	}
	if !info.IsDir() {
		return nil, errors.New("项目规则目录必须为普通文件夹")
	}
	next, err := root.OpenRoot(name)
	if err != nil {
		return nil, err
	}
	actual, err := next.Stat(".")
	if err != nil || !os.SameFile(info, actual) {
		next.Close()
		return nil, errors.New("项目规则目录已改变，请重试")
	}
	return next, nil
}

func openRelativeProjectDir(root *os.Root, path string) (*os.Root, error) {
	next := root
	for _, part := range strings.Split(path, string(filepath.Separator)) {
		dir, err := openProjectSubdir(next, part)
		if next != root {
			next.Close()
		}
		if err != nil {
			return nil, err
		}
		next = dir
	}
	return next, nil
}

func readProjectRegular(root *os.Root, filename string, limit int) ([]byte, error) {
	info, err := root.Lstat(filename)
	if err != nil {
		return nil, err
	}
	if !info.Mode().IsRegular() || info.Size() > int64(limit) {
		return nil, errors.New("只能读取大小在限制内的普通文件")
	}
	file, err := root.OpenFile(filename, os.O_RDONLY|syscall.O_NONBLOCK|syscall.O_NOFOLLOW, 0)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	actual, err := file.Stat()
	if err != nil || !os.SameFile(info, actual) {
		return nil, errors.New("文件已改变，请重试")
	}
	data, err := io.ReadAll(io.LimitReader(file, int64(limit)+1))
	if err != nil {
		return nil, err
	}
	if len(data) > limit {
		return nil, errors.New("文件大小超出限制")
	}
	return data, nil
}

func projectRuleSource(path string) string {
	switch path {
	case "AGENTS.md":
		return "AGENTS.md"
	case "AGENTS.override.md":
		return "Codex"
	case "CLAUDE.md", ".claude/CLAUDE.md":
		return "Claude Code"
	case ".cursorrules":
		return "Cursor"
	}
	if len(path) > 1024 || !fs.ValidPath(path) || path == "." || strings.ContainsRune(path, '\\') || strings.IndexFunc(path, unicode.IsControl) >= 0 {
		return ""
	}
	parts := strings.Split(path, "/")
	if len(parts) < 3 || len(parts) > 7 {
		return ""
	}
	for _, part := range parts[2:] {
		if strings.HasPrefix(part, ".") {
			return ""
		}
	}
	switch {
	case strings.HasPrefix(path, ".claude/rules/") && filepath.Ext(path) == ".md":
		return "Claude Code"
	case strings.HasPrefix(path, ".cursor/rules/") && filepath.Ext(path) == ".mdc":
		return "Cursor"
	}
	return ""
}

func validProjectRuleText(text string) bool {
	return len(text) <= maxRuleBytes && utf8.ValidString(text) && !strings.ContainsRune(text, 0) && strings.TrimSpace(text) != ""
}

func projectRuleDigest(text string) string {
	digest := sha256.Sum256([]byte(text))
	return hex.EncodeToString(digest[:])
}

func readProjectRule(root *os.Root, path string) (projectRule, error) {
	source := projectRuleSource(path)
	if source == "" {
		return projectRule{}, errors.New("不支持这个规则文件")
	}
	relative := filepath.FromSlash(path)
	dir, name := filepath.Split(relative)
	if dir != "" {
		parent, err := openRelativeProjectDir(root, strings.TrimSuffix(dir, string(filepath.Separator)))
		if err != nil {
			return projectRule{}, err
		}
		root = parent
		defer parent.Close()
	}
	data, err := readProjectRegular(root, name, maxRuleBytes)
	if err != nil {
		return projectRule{}, err
	}
	text := string(data)
	if !validProjectRuleText(text) {
		return projectRule{}, errors.New("规则必须是非空 UTF-8 文本")
	}
	return projectRule{
		projectRuleRef: projectRuleRef{Path: path, Digest: projectRuleDigest(text)},
		Source:         source,
		Text:           text,
	}, nil
}

func projectRulePaths(root *os.Root) []string {
	paths := []string{"AGENTS.md", "AGENTS.override.md", "CLAUDE.md", ".claude/CLAUDE.md", ".cursorrules"}
	var walk func(dir *os.Root, prefix string, depth int, budget *int)
	walk = func(dir *os.Root, prefix string, depth int, budget *int) {
		if depth > 5 || *budget <= 0 {
			return
		}
		file, err := dir.Open(".")
		if err != nil {
			return
		}
		entries, _ := file.ReadDir(*budget)
		file.Close()
		*budget -= len(entries)
		sort.Slice(entries, func(i, j int) bool { return entries[i].Name() < entries[j].Name() })
		for _, entry := range entries {
			name := entry.Name()
			if strings.HasPrefix(name, ".") || entry.Type()&os.ModeSymlink != 0 {
				continue
			}
			path := prefix + "/" + name
			if entry.IsDir() {
				child, err := openProjectSubdir(dir, name)
				if err == nil {
					walk(child, path, depth+1, budget)
					child.Close()
				}
			} else if entry.Type().IsRegular() && projectRuleSource(path) != "" {
				paths = append(paths, path)
			}
		}
	}
	for _, prefix := range []string{".claude/rules", ".cursor/rules"} {
		dir, err := openRelativeProjectDir(root, filepath.FromSlash(prefix))
		if err != nil {
			continue
		}
		budget := 256
		walk(dir, prefix, 1, &budget)
		dir.Close()
	}
	return paths
}

func previewProjects(paths []string, records map[string]projectRecord) ([]projectPreview, error) {
	if len(paths) == 0 || len(paths) > maxProjectSelections {
		return nil, errors.New("每次可预览 1–12 个项目")
	}
	seen := make(map[string]bool)
	previews := make([]projectPreview, 0, len(paths))
	for _, path := range paths {
		project, err := cleanProjectPath(path)
		if err != nil {
			return nil, err
		}
		if seen[project] {
			continue
		}
		seen[project] = true
		root, err := openProjectDirectory(project)
		if err != nil {
			return nil, err
		}
		preview := projectPreview{Path: project, Name: filepath.Base(project), Rules: []projectRulePreview{}}
		imported := make(map[projectRuleRef]bool)
		for _, rule := range records[project].Rules {
			imported[rule.projectRuleRef] = true
		}
		remaining := 256 << 10
		for _, path := range projectRulePaths(root) {
			if rule, err := readProjectRule(root, path); err == nil {
				if len(rule.Text) > remaining || len(preview.Rules) >= 64 {
					preview.Omitted++
					continue
				}
				remaining -= len(rule.Text)
				preview.Rules = append(preview.Rules, projectRulePreview{projectRule: rule, Imported: imported[rule.projectRuleRef]})
			}
		}
		root.Close()
		previews = append(previews, preview)
	}
	return previews, nil
}

func collectProjectImports(selections []projectImportSelection) ([]projectRecord, error) {
	if len(selections) == 0 || len(selections) > maxProjectSelections {
		return nil, errors.New("每次可导入 1–12 个项目")
	}
	records := make([]projectRecord, 0, len(selections))
	for _, selection := range selections {
		path, err := cleanProjectPath(selection.Path)
		if err != nil {
			return nil, err
		}
		if len(selection.Rules) > maxProjectRules {
			return nil, errors.New("每个项目最多选择 24 个规则文件")
		}
		record := projectRecord{Path: path, Rules: []projectRule{}}
		root, err := openProjectDirectory(path)
		if err != nil {
			return nil, err
		}
		for _, ref := range selection.Rules {
			if projectRuleSource(ref.Path) == "" {
				root.Close()
				return nil, errors.New("只能导入项目下支持的规则文件")
			}
			rule, err := readProjectRule(root, ref.Path)
			if err != nil || rule.Digest != ref.Digest {
				root.Close()
				return nil, errProjectRuleChanged
			}
			record.Rules = append(record.Rules, rule)
		}
		root.Close()
		records = append(records, record)
	}
	return records, nil
}

func projectContextText(rules []projectRule) string {
	var context strings.Builder
	for _, rule := range rules {
		fmt.Fprintf(&context, "Source: %s (%s)\n%s\n\n", rule.Path, rule.Source, rule.Text)
	}
	return context.String()
}

func (a *apiServer) applyProjectSelections(selections []projectImportSelection) ([]projectSummary, error) {
	lab, _ := a.research.(*research.Service)
	if lab != nil {
		for _, item := range selections {
			if err := lab.ValidateExternalDirectory(item.Path); err != nil {
				return nil, err
			}
		}
	}
	list, err := a.recordProjectSelections(selections)
	if err != nil || lab == nil {
		return list, err
	}
	// Never call into research with the registry lock held. Its grant validator
	// takes the registry read lock while writing the research record.
	for _, item := range selections {
		if _, err := lab.EnsureDirectoryProject(item.Path); err != nil {
			return nil, err
		}
	}
	return a.identifySummaries(list), nil
}
func (a *apiServer) identifySummaries(list []projectSummary) []projectSummary {
	lab, ok := a.research.(*research.Service)
	if !ok {
		return list
	}
	out := make([]projectSummary, 0, len(list))
	for _, item := range list {
		if p, ok := lab.ProjectForDirectory(item.Path); ok {
			item.ID = p.ID
			item.Name = p.Name
			out = append(out, item)
		}
	}
	return out
}
func (a *apiServer) recordProjectSelections(selections []projectImportSelection) ([]projectSummary, error) {
	projectsMu.Lock()
	defer projectsMu.Unlock()
	entries, err := collectProjectImports(selections)
	if err != nil {
		return nil, err
	}
	file := a.projectsFile()
	records, err := loadProjectRecords(file)
	if err != nil {
		return nil, err
	}
	changed := false
	for _, entry := range entries {
		current, exists := records[entry.Path]
		if !exists {
			current = projectRecord{Path: entry.Path, Rules: []projectRule{}}
			changed = true
		}
		grant, err := research.IdentifyDirectory(entry.Path)
		if err != nil {
			return nil, err
		}
		if current.DirectoryGrant == nil || *current.DirectoryGrant != grant {
			current.DirectoryGrant = &grant
			changed = true
		}
		index := make(map[string]int, len(current.Rules))
		for n, rule := range current.Rules {
			index[rule.Path] = n
		}
		for _, rule := range entry.Rules {
			if n, found := index[rule.Path]; found {
				if current.Rules[n].Digest != rule.Digest {
					current.Rules[n] = rule
					changed = true
				}
			} else {
				index[rule.Path] = len(current.Rules)
				current.Rules = append(current.Rules, rule)
				changed = true
			}
		}
		if len(current.Rules) > maxProjectRules || len(projectContextText(current.Rules)) > maxProjectContext {
			return nil, errors.New("项目规则超出 24 个文件或 64 KiB 的限制，请缩小选择范围")
		}
		sort.Slice(current.Rules, func(i, j int) bool { return current.Rules[i].Path < current.Rules[j].Path })
		records[entry.Path] = current
	}
	if len(records) > maxRegisteredProjects {
		return nil, errors.New("项目数量超出限制")
	}
	if changed {
		if err := saveProjectRecords(file, records); err != nil {
			return nil, err
		}
	}
	return projectSummaries(records), nil
}

func (a *apiServer) projectRuleSnapshot(projectPath string) (meeting.ProjectRuleSnapshot, error) {
	snapshot := meeting.ProjectRuleSnapshot{Versions: []meeting.ProjectRuleVersion{}}
	if projectPath == "" || a.prefs == nil {
		return snapshot, nil
	}
	records, err := a.projectRecords()
	if err != nil {
		return snapshot, err
	}
	rules := records[filepath.Clean(projectPath)].Rules
	for _, rule := range rules {
		snapshot.Versions = append(snapshot.Versions, rule.projectRuleRef)
	}
	snapshot.Guidance = projectContextText(rules)
	return snapshot, nil
}

func (a *apiServer) disableProjectRule(path string, ref projectRuleRef) (projectRecord, error) {
	projectsMu.Lock()
	defer projectsMu.Unlock()
	file := a.projectsFile()
	records, err := loadProjectRecords(file)
	if err != nil {
		return projectRecord{}, err
	}
	project, exists := records[path]
	if !exists {
		return projectRecord{}, os.ErrNotExist
	}
	for i, rule := range project.Rules {
		if rule.Path != ref.Path {
			continue
		}
		if rule.Digest != ref.Digest {
			return projectRecord{}, fmt.Errorf("%w: 这条规则已有新版本，请重新查看", meeting.ErrConflict)
		}
		project.Rules = append(project.Rules[:i], project.Rules[i+1:]...)
		records[path] = project
		if err := saveProjectRecords(file, records); err != nil {
			return projectRecord{}, err
		}
		break
	}
	return project, nil
}

func (a *apiServer) projectRulesHandler(w http.ResponseWriter, r *http.Request) {
	var project projectRecord
	var err error
	switch r.Method {
	case http.MethodGet:
		path := r.URL.Query().Get("path")
		if !registeredProjectPath(path) {
			reject(w, http.StatusBadRequest, "请选择已添加的项目")
			return
		}
		var records map[string]projectRecord
		records, err = a.projectRecords()
		project = records[path]
	case http.MethodPost:
		var request struct {
			Path string         `json:"path"`
			Rule projectRuleRef `json:"rule"`
		}
		if !jsonBody(w, r, &request) {
			return
		}
		if !registeredProjectPath(request.Path) {
			reject(w, http.StatusBadRequest, "请选择已添加的项目")
			return
		}
		digest, decodeErr := hex.DecodeString(request.Rule.Digest)
		if projectRuleSource(request.Rule.Path) == "" || decodeErr != nil || len(digest) != sha256.Size {
			reject(w, http.StatusBadRequest, "请选择有效的项目规则版本")
			return
		}
		project, err = a.disableProjectRule(request.Path, request.Rule)
	default:
		w.Header().Set("Allow", "GET, POST")
		reject(w, http.StatusMethodNotAllowed, "不支持这个操作")
		return
	}
	if errors.Is(err, os.ErrNotExist) || (err == nil && project.Path == "") {
		reject(w, http.StatusNotFound, "这个项目尚未添加")
		return
	}
	if err != nil {
		fail(w, err)
		return
	}
	reply(w, http.StatusOK, projectRulesView{Project: project.summary(), Rules: project.Rules})
}

func (a *apiServer) projectsHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodPost {
		w.Header().Set("Allow", "GET, POST")
		reject(w, http.StatusMethodNotAllowed, "不支持这个操作")
		return
	}
	if strings.HasSuffix(r.URL.Path, "/import") {
		a.projectImportHandler(w, r)
		return
	}
	var summaries []projectSummary
	var err error
	if r.Method == http.MethodGet {
		var records map[string]projectRecord
		records, err = a.projectRecords()
		summaries = a.identifySummaries(projectSummaries(records))
	} else {
		var request struct {
			Path string `json:"path"`
		}
		if !jsonBody(w, r, &request) {
			return
		}
		summaries, err = a.applyProjectSelections([]projectImportSelection{{Path: request.Path}})
	}
	if err != nil {
		fail(w, err)
		return
	}
	reply(w, http.StatusOK, map[string]any{"projects": summaries})
}

func (a *apiServer) projectImportHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodGet {
		records, err := a.projectRecords()
		if err != nil {
			fail(w, err)
			return
		}
		reply(w, http.StatusOK, map[string]any{"candidates": discoverProjects(records)})
		return
	}
	var request projectImportRequest
	if !jsonBody(w, r, &request) {
		return
	}
	switch request.Action {
	case "preview":
		if lab, ok := a.research.(*research.Service); ok {
			for _, path := range request.Paths {
				if err := lab.ValidateExternalDirectory(path); err != nil {
					fail(w, err)
					return
				}
			}
		}
		records, err := a.projectRecords()
		if err != nil {
			fail(w, err)
			return
		}
		previews, err := previewProjects(request.Paths, records)
		if err != nil {
			fail(w, err)
			return
		}
		reply(w, http.StatusOK, map[string]any{"projects": previews})
	case "apply":
		summaries, err := a.applyProjectSelections(request.Selections)
		if errors.Is(err, errProjectRuleChanged) {
			reject(w, http.StatusConflict, err.Error())
			return
		}
		if err != nil {
			fail(w, err)
			return
		}
		reply(w, http.StatusOK, map[string]any{"projects": summaries})
	default:
		reject(w, http.StatusBadRequest, "未知项目导入操作")
	}
}
