package desktop

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"syscall"
	"unicode"

	"scistation.local/desktop/internal/meeting"
	"scistation.local/desktop/internal/research"
	"scistation.local/desktop/internal/workspace"
)

const (
	maxProjectSelections = 12
	maxProjectRules      = research.MaxRoundtableRules
	maxRuleBytes         = research.MaxRoundtableRuleBytes

	maxRegisteredProjects = 256
)

type projectRuleRef = research.RoundtableRuleVersion
type projectRule = research.RoundtableRule

type projectRecord struct {
	selectedGrant research.DirectoryGrant
	projectID     string
	Path          string        `json:"path"`
	Rules         []projectRule `json:"rules"`
}

type projectSummary = research.RoundtableProjectSummary

type projectRulePreview struct {
	projectRule
	Imported bool `json:"imported"`
}

type projectPreview struct {
	ID      string               `json:"id,omitempty"`
	Path    string               `json:"path"`
	Name    string               `json:"name"`
	Rules   []projectRulePreview `json:"rules"`
	Omitted int                  `json:"omitted"`
}

type projectImportSelection struct {
	ID    string           `json:"id,omitempty"`
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
		if !research.ValidRoundtableRules(project.Rules) {
			return nil, invalid
		}
	}
	return projects, nil
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

func readProjectRule(root *os.Root, path string) (projectRule, error) {
	source := research.RoundtableRuleSource(path)
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
	if !research.ValidRoundtableRuleText(text) {
		return projectRule{}, errors.New("规则必须是非空 UTF-8 文本")
	}
	return projectRule{
		RoundtableRuleVersion: projectRuleRef{Path: path, Digest: research.RoundtableRuleDigest(text)},
		Source:                source,
		Text:                  text,
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
			} else if entry.Type().IsRegular() && research.RoundtableRuleSource(path) != "" {
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

func previewProjects(lab *research.Service, paths []string) ([]projectPreview, error) {
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
		err = lab.WithRuleImportDirectory(project, "", func(root *os.Root, id string, _ research.DirectoryGrant, rules []projectRule) error {
			preview := projectPreview{ID: id, Path: project, Name: filepath.Base(project), Rules: []projectRulePreview{}}
			imported := make(map[projectRuleRef]bool)
			for _, rule := range rules {
				imported[rule.RoundtableRuleVersion] = true
			}
			remaining := 256 << 10
			for _, path := range projectRulePaths(root) {
				if rule, err := readProjectRule(root, path); err == nil {
					if len(rule.Text) > remaining || len(preview.Rules) >= 64 {
						preview.Omitted++
						continue
					}
					remaining -= len(rule.Text)
					preview.Rules = append(preview.Rules, projectRulePreview{projectRule: rule, Imported: imported[rule.RoundtableRuleVersion]})
				}
			}
			previews = append(previews, preview)
			return nil
		})
		if err != nil {
			return nil, err
		}
	}
	return previews, nil
}

func collectProjectImports(lab *research.Service, selections []projectImportSelection) ([]projectRecord, error) {
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
		err = lab.WithRuleImportDirectory(path, selection.ID, func(root *os.Root, id string, grant research.DirectoryGrant, _ []projectRule) error {
			record.selectedGrant = grant
			record.projectID = id
			for _, ref := range selection.Rules {
				if research.RoundtableRuleSource(ref.Path) == "" {
					return errors.New("只能导入项目下支持的规则文件")
				}
				rule, err := readProjectRule(root, ref.Path)
				if err != nil || rule.Digest != ref.Digest {
					return errProjectRuleChanged
				}
				record.Rules = append(record.Rules, rule)
			}
			records = append(records, record)
			return nil
		})
		if err != nil {
			return nil, err
		}
	}
	return records, nil
}

func (a *apiServer) applyProjectSelections(selections []projectImportSelection) ([]projectSummary, error) {
	lab := a.research
	if lab == nil {
		return nil, fmt.Errorf("%w: 科研项目服务不可用", os.ErrPermission)
	}
	entries, err := collectProjectImports(lab, selections)
	if err != nil {
		return nil, err
	}
	for _, entry := range entries {
		if _, err := lab.RegisterDirectoryProject(entry.Path, entry.projectID, entry.selectedGrant, entry.Rules...); err != nil {
			return nil, err
		}
		a.selectedPaths.CompareAndDelete(entry.Path, entry.selectedGrant)
	}
	return a.activeProjectSummaries()
}

func (a *apiServer) activeProjectSummaries() ([]projectSummary, error) {
	lab := a.research
	if lab == nil {
		return nil, os.ErrPermission
	}
	return lab.RoundtableProjects(), nil
}

func (a *apiServer) projectRuleSnapshot(scope meeting.ProjectScope) (meeting.ProjectRuleSnapshot, error) {
	snapshot := meeting.ProjectRuleSnapshot{Versions: []meeting.ProjectRuleVersion{}}
	lab := a.research
	if lab == nil || scope.ID == "" {
		return snapshot, os.ErrPermission
	}
	rules, err := lab.RoundtableRules(scope.ID, scope.Directory)
	if err != nil {
		return snapshot, err
	}
	for _, rule := range rules {
		snapshot.Versions = append(snapshot.Versions, meeting.ProjectRuleVersion(rule.RoundtableRuleVersion))
	}
	snapshot.Guidance = research.RoundtableRuleText(rules)
	return snapshot, nil
}

func (a *apiServer) projectRulesHandler(w http.ResponseWriter, r *http.Request) {
	lab := a.research
	if lab == nil {
		fail(w, os.ErrPermission)
		return
	}
	var input struct {
		ID   string         `json:"id"`
		Path string         `json:"path"`
		Rule projectRuleRef `json:"rule"`
	}
	if r.URL.Query().Get("legacy") == "1" && r.Method != http.MethodGet {
		w.Header().Set("Allow", "GET")
		reject(w, http.StatusMethodNotAllowed, "历史规则快照仅供查看")
		return
	}
	if r.Method == http.MethodGet {
		input.ID = r.URL.Query().Get("id")
		input.Path = r.URL.Query().Get("path")
		if r.URL.Query().Get("legacy") == "1" {
			if input.ID != "" || !registeredProjectPath(input.Path) {
				reject(w, http.StatusBadRequest, "请选择历史规则的来源路径")
				return
			}
			records, err := a.projectRecords()
			if err != nil {
				fail(w, err)
				return
			}
			record, found := records[input.Path]
			if !found {
				fail(w, os.ErrNotExist)
				return
			}
			reply(w, 200, projectRulesView{Project: record.summary(), Rules: record.Rules})
			return
		}
	} else if r.Method == http.MethodPost {
		if !jsonBody(w, r, &input) {
			return
		}
		digest, err := hex.DecodeString(input.Rule.Digest)
		if research.RoundtableRuleSource(input.Rule.Path) == "" || err != nil || len(digest) != sha256.Size {
			reject(w, 400, "请选择有效的项目规则版本")
			return
		}
	} else {
		w.Header().Set("Allow", "GET, POST")
		reject(w, 405, "不支持这个操作")
		return
	}
	var project research.Project
	if input.ID != "" {
		var found bool
		project, found = lab.ActiveProject(input.ID)
		if !found || (input.Path != "" && project.Path != input.Path) {
			fail(w, os.ErrNotExist)
			return
		}

	} else {
		if !registeredProjectPath(input.Path) {
			reject(w, 400, "请选择已添加的项目")
			return
		}
		var found bool
		project, found = lab.ProjectForDirectory(input.Path)
		if !found {
			fail(w, os.ErrNotExist)
			return
		}
	}
	var rules []projectRule
	var err error
	if r.Method == http.MethodPost {
		rules, err = lab.DisableRoundtableRule(project.ID, input.Path, input.Rule)
	} else {
		rules, err = lab.RoundtableRules(project.ID, input.Path)
	}
	if err != nil {
		fail(w, err)
		return
	}
	reply(w, 200, projectRulesView{Project: projectSummary{ID: project.ID, Name: project.Name, Path: project.Path, RuleCount: len(rules)}, Rules: rules})
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
		summaries, err = a.activeProjectSummaries()
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
		reply(w, http.StatusOK, map[string]any{"candidates": discoverProjects(records), "legacy": projectSummaries(records)})
		return
	}
	var request projectImportRequest
	if !jsonBody(w, r, &request) {
		return
	}
	switch request.Action {
	case "preview":
		lab := a.research
		if lab == nil {
			fail(w, os.ErrPermission)
			return
		}
		previews, err := previewProjects(lab, request.Paths)
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
