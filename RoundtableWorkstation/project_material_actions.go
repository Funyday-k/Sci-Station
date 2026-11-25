package main

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"

	"scistation.local/desktop/internal/research"
	"scistation.local/desktop/internal/workspace"
)

const projectMaterialActionPath = "/api/research/tools/project-material"

type projectMaterialActions struct {
	confirm func(context.Context, string, string) bool
	pick    func() (string, error)
	launch  func(context.Context, materialLaunch) error

	dialogMu sync.Mutex
	envs     sync.Map // project ID -> materialEnvironment
}

type materialEnvironment struct {
	directory string
	grant     research.DirectoryGrant
}

type materialLaunch struct {
	action      string
	project     string
	file        string
	interpreter string
	material    workspace.MaterialFile
	grant       research.DirectoryGrant
	basePython  string
}

type projectMaterialInput struct {
	Project string `json:"project"`
	Action  string `json:"action"`
	Path    string `json:"path"`
	Runtime string `json:"runtime"`
}

type projectMaterialCapabilities struct {
	Native   bool `json:"native"`
	LocalEnv bool `json:"localEnv"`
	Chosen   bool `json:"chosen"`
}

func (a *apiServer) serveProjectMaterial(w http.ResponseWriter, r *http.Request) {
	lab, ok := a.research.(*research.Service)
	if !ok {
		reject(w, 503, "科研服务未启动")
		return
	}
	a.pickMu.RLock()
	actions := a.materialActions
	a.pickMu.RUnlock()
	native := actions != nil && strings.Contains(r.UserAgent(), desktopUserAgent)
	if r.Method == http.MethodGet || r.Method == http.MethodHead {
		project := r.URL.Query().Get("project")
		caps := projectMaterialCapabilities{Native: native}
		err := lab.WithProjectDirectory(project, func(dir string) error {
			_, err := environmentPython(filepath.Join(dir, ".venv"))
			caps.LocalEnv = err == nil
			if native {
				caps.Chosen = actions.chosenPython(project) != ""
			}
			return nil
		})
		if err != nil {
			rejectMaterialAction(w, err)
			return
		}
		reply(w, 200, caps)
		return
	}
	if r.Method != http.MethodPost {
		reject(w, 405, "不支持此请求")
		return
	}
	if !native {
		reject(w, 403, "请从 Sci-Station 桌面窗口使用此功能")
		return
	}
	var input projectMaterialInput
	if !jsonBody(w, r, &input) {
		return
	}
	if !actions.dialogMu.TryLock() {
		reject(w, 409, "请先处理已打开的材料操作窗口")
		return
	}
	defer actions.dialogMu.Unlock()
	performed, err := actions.perform(r.Context(), lab, input)
	if err != nil {
		rejectMaterialAction(w, err)
		return
	}
	reply(w, 200, map[string]bool{"performed": performed})
}

func rejectMaterialAction(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, os.ErrNotExist):
		reject(w, 404, "项目或材料已不存在")
	case errors.Is(err, os.ErrPermission):
		reject(w, 403, "项目目录没有有效授权")
	case errors.Is(err, workspace.ErrConflict):
		reject(w, 409, "项目或运行环境已变更，请刷新后重试")
	default:
		reject(w, 400, err.Error())
	}
}

func (a *projectMaterialActions) perform(ctx context.Context, lab *research.Service, input projectMaterialInput) (bool, error) {
	if err := ctx.Err(); err != nil {
		return false, err
	}
	if input.Action == "select-venv" {
		return a.selectVenv(ctx, lab, input.Project)
	}
	var target materialLaunch
	err := lab.WithProjectDirectory(input.Project, func(dir string) error {
		var err error
		target, err = a.resolve(dir, input)
		return err
	})
	if err != nil {
		return false, err
	}
	title, description := target.confirmation()
	if !a.confirm(ctx, title, description) {
		return false, nil
	}
	err = lab.WithProjectDirectory(input.Project, func(dir string) error {
		if err := ctx.Err(); err != nil {
			return err
		}
		fresh, err := a.resolve(dir, input)
		if err != nil {
			return err
		}
		if fresh != target {
			return workspace.ErrConflict
		}
		return a.launch(ctx, target)
	})
	return err == nil, err
}

func (a *projectMaterialActions) selectVenv(ctx context.Context, lab *research.Service, project string) (bool, error) {
	var before research.DirectoryGrant
	err := lab.WithProjectDirectory(project, func(dir string) error {
		var err error
		before, err = research.IdentifyDirectory(dir)
		return err
	})
	if err != nil {
		return false, err
	}
	chosen, err := a.pick()
	if errors.Is(err, context.Canceled) || err == nil && chosen == "" {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	if err := ctx.Err(); err != nil {
		return false, err
	}
	err = lab.WithProjectDirectory(project, func(dir string) error {
		current, err := research.IdentifyDirectory(dir)
		if err != nil {
			return err
		}
		if current != before {
			return workspace.ErrConflict
		}
		grant, err := research.IdentifyDirectory(chosen)
		if err != nil {
			return err
		}
		if _, err := environmentPython(chosen); err != nil {
			return err
		}
		a.envs.Store(project, materialEnvironment{directory: chosen, grant: grant})
		return nil
	})
	return err == nil, err
}

func (a *projectMaterialActions) chosenPython(project string) string {
	value, found := a.envs.Load(project)
	if !found {
		return ""
	}
	env := value.(materialEnvironment)
	grant, err := research.IdentifyDirectory(env.directory)
	if err != nil || grant != env.grant {
		return ""
	}
	python, _ := environmentPython(env.directory)
	return python
}

func (a *projectMaterialActions) resolve(directory string, input projectMaterialInput) (materialLaunch, error) {
	target := materialLaunch{action: input.Action, project: directory}
	grant, err := research.IdentifyDirectory(directory)
	if err != nil {
		return target, err
	}
	target.grant = grant
	if input.Path != "" {
		path, item, err := workspace.MaterialLocation(directory, input.Path)
		if err != nil {
			return target, err
		}
		target.file, target.material = path, item
	}
	switch input.Action {
	case "reveal", "editor":
		return target, nil
	case "open":
		if target.file == "" {
			return target, errors.New("请选择要打开的项目文件")
		}
	case "create-venv":
		if target.file != "" {
			return target, errors.New("只能为项目文件夹创建环境")
		}
		_, err := os.Lstat(filepath.Join(directory, ".venv"))
		if !errors.Is(err, os.ErrNotExist) {
			return target, errors.New("项目中已有 .venv 路径")
		}
		target.interpreter = "/usr/bin/python3"
	case "run-terminal", "run-editor":
		if target.material.Kind != "python" {
			return target, errors.New("请选择一个项目 Python 文件")
		}
		switch input.Runtime {
		case "system":
			target.interpreter = "/usr/bin/python3"
		case "local":
			python, err := environmentPython(filepath.Join(directory, ".venv"))
			if err != nil {
				return target, err
			}
			target.interpreter = python
		case "chosen":
			target.interpreter = a.chosenPython(input.Project)
			if target.interpreter == "" {
				return target, errors.New("请重新选择有效的 Python 虚拟环境")
			}
		default:
			return target, errors.New("请选择 Python 运行环境")
		}
		target.basePython, err = filepath.EvalSymlinks(target.interpreter)
		if err != nil {
			return target, errors.New("所选 Python 解释器不可用")
		}
		if input.Action == "run-editor" && (strings.Contains(target.interpreter, "${") || strings.Contains(target.file, "${")) {
			return target, errors.New("路径包含 VS Code 任务变量语法")
		}
	default:
		return target, errors.New("未知的材料操作")
	}
	return target, nil
}

func environmentPython(directory string) (string, error) {
	invalid := errors.New("所选环境目录需要包含可执行的 bin/python")
	if _, err := workspace.Validate(filepath.Join(directory, "bin")); err != nil {
		return "", invalid
	}
	// A standard venv's bin/python is often a symlink to the base interpreter.
	exe := filepath.Join(directory, "bin", "python")
	info, err := os.Stat(exe)
	if err != nil || !info.Mode().IsRegular() || info.Mode().Perm()&0111 == 0 {
		return "", invalid
	}
	return exe, nil
}

func (m materialLaunch) confirmation() (string, string) {
	target := m.file
	if target == "" {
		target = m.project
	}
	switch m.action {
	case "reveal":
		return "在 Finder 中打开", target
	case "editor":
		return "在 VS Code 中打开", target
	case "open":
		return "在默认应用中打开", target
	case "create-venv":
		return "在终端创建 Python 虚拟环境", filepath.Join(m.project, ".venv")
	case "run-editor":
		return "准备 VS Code Python 任务", fmt.Sprintf("%s\n\nPython: %s\n工作目录: %s", target, m.interpreter, m.project)
	default:
		return "在终端运行 Python 文件", fmt.Sprintf("%s\n\nPython: %s\n工作目录: %s", target, m.interpreter, filepath.Dir(target))
	}
}
