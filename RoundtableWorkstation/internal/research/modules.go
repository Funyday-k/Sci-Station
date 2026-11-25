package research

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"slices"
	"strings"
)

const moduleSettingsFile = "modules.json"

type moduleDefinition struct {
	ID           string   `json:"id"`
	Title        string   `json:"title"`
	ChineseTitle string   `json:"chineseTitle"`
	Dependencies []string `json:"dependencies"`
	Placeholder  bool     `json:"placeholder"`
	Directories  []string `json:"-"`
}

// IDs and dependencies correspond to the Swift workspace registry. Directory
// entries refer to currently used storage inside the Go research root.
var workspaceModules = []moduleDefinition{
	{"projects", "Projects", "项目", []string{}, false, []string{"records", "workspaces"}},
	{"paper-library", "Paper Library", "文献库", []string{}, false, []string{"library/records", "library/pdf"}},
	{"wiki", "Wiki", "Wiki", []string{"projects"}, false, nil},
	{"materials", "Materials", "材料", []string{"projects"}, false, []string{"blobs"}},
	{"tasks", "Tasks", "任务", []string{"projects"}, false, nil},
	{"calendar", "Calendar", "日历", []string{"tasks"}, false, nil},
	{"pdf-reader", "PDF Reader", "PDF 阅读器", []string{"paper-library"}, false, nil},
	{"ai-lab", "AI Lab", "AI 实验室", []string{"projects"}, false, nil},
	{"code", "Code Research", "代码研究", []string{"projects", "wiki", "ai-lab"}, true, nil},
	{"datasets", "Datasets", "数据集", []string{"projects", "materials"}, true, nil},
	{"experiments", "Experiments", "实验", []string{"projects", "code", "datasets", "ai-lab"}, true, nil},
	{"citation-graph", "Citation Graph", "引文图谱", []string{"paper-library", "wiki"}, false, nil},
	{"recommendation", "Recommendations", "论文推荐", []string{"paper-library"}, false, nil},
	{"writing", "Writing", "写作", []string{"projects", "wiki", "paper-library", "ai-lab"}, true, nil},
	{"theory-notes", "Theory Notes", "理论笔记", []string{"projects", "wiki", "paper-library"}, true, nil},
}

var modulesByID = func() map[string]moduleDefinition {
	modules := make(map[string]moduleDefinition, len(workspaceModules))
	for _, module := range workspaceModules {
		modules[module.ID] = module
	}
	return modules
}()

type moduleConfig struct {
	fields   map[string]json.RawMessage
	enabled  map[string]bool
	pins     []string
	projects map[string]map[string]bool
	revision string
}

// Keep unrecognized fields and module IDs through writes. A malformed or
// newer-version file remains in place and must be repaired before mutation.
func (s *Service) readModuleConfig(project string) (moduleConfig, error) {
	config := moduleConfig{
		fields:   map[string]json.RawMessage{"version": json.RawMessage("1")},
		enabled:  map[string]bool{},
		projects: map[string]map[string]bool{},
	}
	path := filepath.Join(s.dir, moduleSettingsFile)
	var data []byte
	info, err := os.Lstat(path)
	switch {
	case err == nil && info.Mode().IsRegular():
		data, err = os.ReadFile(path)
		if err != nil {
			return config, err
		}
		if err := json.Unmarshal(data, &config.fields); err != nil {
			return config, err
		}
		var version int
		if json.Unmarshal(config.fields["version"], &version) != nil || version != 1 {
			return config, errors.New("unsupported module settings version")
		}
		for key, target := range map[string]any{
			"enabled": &config.enabled, "pins": &config.pins, "projects": &config.projects,
		} {
			if value, ok := config.fields[key]; ok && json.Unmarshal(value, target) != nil {
				return config, fmt.Errorf("invalid module settings field %q", key)
			}
		}
		if config.enabled == nil || config.projects == nil {
			return config, errors.New("invalid module settings maps")
		}
	case errors.Is(err, os.ErrNotExist):
	case err != nil:
		return config, err
	default:
		return config, errors.New("module settings are not a regular file")
	}
	hash := sha256.New()
	fmt.Fprintf(hash, "%s\x00%s\x00", s.dir, project)
	hash.Write(data)
	config.revision = hex.EncodeToString(hash.Sum(nil))
	return config, nil
}

func (s *Service) saveModuleConfig(config moduleConfig) error {
	for key, value := range map[string]any{
		"enabled":  config.enabled,
		"pins":     config.pins,
		"projects": config.projects,
	} {
		encoded, err := json.Marshal(value)
		if err != nil {
			return err
		}
		config.fields[key] = encoded
	}
	data, err := json.MarshalIndent(config.fields, "", "  ")
	if err != nil {
		return err
	}
	return atomicWrite(filepath.Join(s.dir, moduleSettingsFile), append(data, '\n'))
}

func (config moduleConfig) workspaceEnabled(module moduleDefinition) bool {
	if enabled, ok := config.enabled[module.ID]; ok {
		return enabled
	}
	return !module.Placeholder
}

func (config moduleConfig) requested(module moduleDefinition, project string) bool {
	if enabled, ok := config.projects[project][module.ID]; ok {
		return enabled
	}
	return config.workspaceEnabled(module)
}

func (config moduleConfig) effective(id, project string) bool {
	module, ok := modulesByID[id]
	if !ok || !config.requested(module, project) {
		return false
	}
	return len(config.missingDependencies(module, project)) == 0
}

func (config moduleConfig) missingDependencies(module moduleDefinition, project string) []string {
	var missing []string
	for _, dependency := range module.Dependencies {
		if !config.effective(dependency, project) {
			missing = append(missing, dependency)
		}
	}
	return missing
}

// ModuleEnabled resolves dependencies within the requested project snapshot.
// The global scope is represented by an empty project ID.
func (s *Service) ModuleEnabled(project, moduleID string) (bool, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	if project != "" && !s.activeModuleProject(project) {
		return false, os.ErrNotExist
	}
	config, err := s.readModuleConfig(project)
	if err != nil {
		return false, err
	}
	return config.effective(moduleID, project), nil
}

func (s *Service) activeModuleProject(project string) bool {
	data, exists := s.projects[project]
	return exists && !data.Archived
}

type moduleDirectory struct {
	Path       string `json:"path"`
	Exists     bool   `json:"exists"`
	Repairable bool   `json:"repairable"`
}

type moduleState struct {
	moduleDefinition
	Enabled          bool              `json:"enabled"`
	WorkspaceEnabled bool              `json:"workspaceEnabled"`
	Effective        bool              `json:"effective"`
	Missing          []string          `json:"missing,omitempty"`
	Pinned           bool              `json:"pinned"`
	Override         *bool             `json:"override,omitempty"`
	Paths            []moduleDirectory `json:"paths,omitempty"`
}

type moduleResponse struct {
	Modules     []moduleState `json:"modules"`
	PinnedOrder []string      `json:"pinnedOrder"`
	Revision    string        `json:"revision"`
}

func (s *Service) moduleSnapshot(config moduleConfig, project string) moduleResponse {
	out := moduleResponse{PinnedOrder: []string{}, Revision: config.revision}
	for _, id := range config.pins {
		if _, known := modulesByID[id]; known && !slices.Contains(out.PinnedOrder, id) {
			out.PinnedOrder = append(out.PinnedOrder, id)
		}
	}
	for _, definition := range workspaceModules {
		module := moduleState{
			moduleDefinition: definition,
			Enabled:          config.requested(definition, project),
			WorkspaceEnabled: config.workspaceEnabled(definition),
			Effective:        config.effective(definition.ID, project),
			Missing:          config.missingDependencies(definition, project),
			Pinned:           slices.Contains(out.PinnedOrder, definition.ID),
		}
		if enabled, ok := config.projects[project][definition.ID]; ok {
			module.Override = &enabled
		}
		for _, path := range definition.Directories {
			module.Paths = append(module.Paths, s.moduleDirectoryStatus(path))
		}
		out.Modules = append(out.Modules, module)
	}
	return out
}

// Check every path component so a repair can never recreate a directory
// through a symlink or overwrite an existing non-directory entry.
func (s *Service) moduleDirectoryStatus(path string) moduleDirectory {
	status := moduleDirectory{Path: path}
	current := s.dir
	for _, component := range strings.Split(path, "/") {
		current = filepath.Join(current, component)
		info, err := os.Lstat(current)
		if errors.Is(err, os.ErrNotExist) {
			status.Repairable = true
			return status
		}
		if err != nil || !info.IsDir() {
			return status
		}
	}
	status.Exists = true
	return status
}

type moduleChange struct {
	Revision string `json:"revision"`
	Action   string `json:"action"`
	ModuleID string `json:"id,omitempty"`
	Enabled  *bool  `json:"enabled,omitempty"`
	Position *int   `json:"position,omitempty"`
	Path     string `json:"path,omitempty"`
}

func (config *moduleConfig) setEnabled(id, project string, enabled bool) {
	if project == "" {
		config.enabled[id] = enabled
		return
	}
	if config.projects[project] == nil {
		config.projects[project] = map[string]bool{}
	}
	config.projects[project][id] = enabled
}

func (config *moduleConfig) enableChain(id, project string) {
	definition := modulesByID[id]
	for _, dependency := range definition.Dependencies {
		if !config.effective(dependency, project) {
			config.enableChain(dependency, project)
		}
	}
	if !config.requested(definition, project) {
		config.setEnabled(id, project, true)
	}
}

func (config *moduleConfig) change(in moduleChange, project string) error {
	definition, known := modulesByID[in.ModuleID]
	if !known && in.Action != "reset" {
		return errors.New("未找到工作区模块")
	}
	switch in.Action {
	case "set":
		if in.Enabled == nil {
			if project == "" {
				return errors.New("请提供工作区模块的启用状态")
			}
			delete(config.projects[project], in.ModuleID)
			if len(config.projects[project]) == 0 {
				delete(config.projects, project)
			}
			return nil
		}
		if *in.Enabled && project == "" && len(config.missingDependencies(definition, project)) != 0 {
			return errors.New("请先启用依赖模块")
		}
		config.setEnabled(in.ModuleID, project, *in.Enabled)
	case "enable-dependencies":
		config.enableChain(in.ModuleID, project)
	case "pin":
		if project != "" || in.Enabled == nil {
			return errors.New("请在工作区范围内设置固定状态")
		}
		pinned := slices.Contains(config.pins, in.ModuleID)
		if *in.Enabled && !pinned {
			config.pins = append(config.pins, in.ModuleID)
		} else if !*in.Enabled && pinned {
			config.pins = slices.DeleteFunc(config.pins, func(id string) bool { return id == in.ModuleID })
		}
	case "move":
		if project != "" || in.Position == nil || !slices.Contains(config.pins, in.ModuleID) {
			return errors.New("请提供已固定模块的新位置")
		}
		config.pins = slices.DeleteFunc(config.pins, func(id string) bool { return id == in.ModuleID })
		position := max(0, *in.Position)
		index := len(config.pins)
		for i, id := range config.pins {
			if _, known := modulesByID[id]; !known {
				continue
			}
			if position == 0 {
				index = i
				break
			}
			position--
		}
		config.pins = slices.Insert(config.pins, index, in.ModuleID)
	case "reset":
		if project != "" {
			return errors.New("请在工作区范围内重置模块")
		}
		for id := range modulesByID {
			delete(config.enabled, id)
		}
		config.pins = slices.DeleteFunc(config.pins, func(id string) bool {
			_, known := modulesByID[id]
			return known
		})
	default:
		return errors.New("未知的模块设置操作")
	}
	return nil
}

func (s *Service) repairModuleDirectory(in moduleChange) error {
	definition, known := modulesByID[in.ModuleID]
	if !known || !slices.Contains(definition.Directories, in.Path) {
		return errors.New("所选目录不属于这个模块")
	}
	status := s.moduleDirectoryStatus(in.Path)
	if status.Exists {
		return nil
	}
	if !status.Repairable {
		return errors.New("目录不可修复")
	}
	root, err := os.OpenRoot(s.dir)
	if err != nil {
		return err
	}
	defer root.Close()
	return root.MkdirAll(in.Path, 0700)
}

func (s *Service) registerModules() {
	s.mux.HandleFunc("GET "+prefix+"/modules", s.getModules)
	s.mux.HandleFunc("PATCH "+prefix+"/modules", s.changeModules)
}

func (s *Service) getModules(w http.ResponseWriter, r *http.Request) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	project := r.URL.Query().Get("project")
	if project != "" && !found(w, s.activeModuleProject(project)) {
		return
	}
	config, err := s.readModuleConfig(project)
	if err != nil {
		jsonFail(w, 500, "无法读取工作区模块设置")
		return
	}
	jsonReply(w, 200, s.moduleSnapshot(config, project))
}

func (s *Service) changeModules(w http.ResponseWriter, r *http.Request) {
	var in moduleChange
	if !payload(w, r, &in) {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	project := r.URL.Query().Get("project")
	if project != "" && !found(w, s.activeModuleProject(project)) {
		return
	}
	config, err := s.readModuleConfig(project)
	if err != nil {
		jsonFail(w, 500, "无法读取工作区模块设置")
		return
	}
	if in.Revision == "" {
		jsonFail(w, 428, "请携带已读取的模块设置版本")
		return
	}
	if in.Revision != config.revision {
		jsonFail(w, 409, "模块设置已改变，请重新加载")
		return
	}
	if in.Action == "repair" {
		if project != "" {
			jsonFail(w, 400, "请在工作区范围内修复模块目录")
			return
		}
		if err := s.repairModuleDirectory(in); err != nil {
			jsonFail(w, 400, "无法修复所选模块目录")
			return
		}
	} else {
		if err := config.change(in, project); err != nil {
			jsonFail(w, 400, err.Error())
			return
		}
		if err := s.saveModuleConfig(config); err != nil {
			jsonFail(w, 500, "无法保存工作区模块设置")
			return
		}
		config, err = s.readModuleConfig(project)
		if err != nil {
			jsonFail(w, 500, "无法读取工作区模块设置")
			return
		}
	}
	jsonReply(w, 200, s.moduleSnapshot(config, project))
}
