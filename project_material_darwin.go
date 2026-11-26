//go:build darwin && !nogui

package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"

	"github.com/wailsapp/wails/v3/pkg/application"
)

func configureMaterialDesktop(host *apiServer, app *application.App, window application.Window, pickerMu *sync.Mutex) {
	actions := &projectMaterialActions{
		confirm: func(ctx context.Context, title, detail string) bool {
			result := make(chan bool, 1)
			dialog := app.Dialog.Question().AttachToWindow(window).SetTitle(title).SetMessage(detail)
			dialog.AddButton("取消").SetAsCancel().OnClick(func() { result <- false })
			dialog.AddButton("继续").OnClick(func() { result <- true })
			dialog.Show()
			select {
			case confirmed := <-result:
				return confirmed
			case <-ctx.Done():
				return false
			}
		},
		pick: func() (string, error) {
			pickerMu.Lock()
			defer pickerMu.Unlock()
			return app.Dialog.OpenFile().AttachToWindow(window).
				CanChooseDirectories(true).CanChooseFiles(false).CanCreateDirectories(false).
				SetTitle("选择 Python 虚拟环境").SetMessage("请选择包含可执行 bin/python 的环境文件夹。").
				SetButtonText("选择环境").PromptForSingleSelection()
		},
		launch: launchProjectMaterial,
	}
	host.pickMu.Lock()
	host.materialActions = actions
	host.pickMu.Unlock()
}

func launchProjectMaterial(ctx context.Context, m materialLaunch) error {
	path := m.project
	if m.file != "" {
		path = m.file
	}
	switch m.action {
	case "reveal":
		if m.file != "" {
			return openMaterialApplication(ctx, "-R", path)
		}
		return openMaterialApplication(ctx, "-b", "com.apple.finder", path)
	case "open":
		return openMaterialApplication(ctx, path)
	case "editor":
		return openMaterialVSCode(ctx, path)
	case "run-terminal", "create-venv":
		name, err := stageMaterialCommand(m)
		if err != nil {
			return err
		}
		if err := openMaterialApplication(ctx, "-b", "com.apple.Terminal", name); err != nil {
			_ = os.Remove(name)
			return err
		}
		return nil
	case "run-editor":
		name, err := stageMaterialVSCodeWorkspace(m)
		if err != nil {
			return err
		}
		if err := openMaterialVSCode(ctx, name, m.file); err != nil {
			_ = os.RemoveAll(filepath.Dir(name))
			return err
		}
		return nil
	default:
		return errors.New("未知的材料操作")
	}
}

func openMaterialApplication(ctx context.Context, args ...string) error {
	output, err := exec.CommandContext(ctx, "/usr/bin/open", args...).CombinedOutput()
	if err != nil {
		return fmt.Errorf("无法打开所选应用：%s", strings.TrimSpace(string(output)))
	}
	return nil
}

func openMaterialVSCode(ctx context.Context, paths ...string) error {
	for _, bundle := range []string{"com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.vscodium", "com.visualstudio.code.oss"} {
		args := append([]string{"-b", bundle}, paths...)
		if err := openMaterialApplication(ctx, args...); err == nil {
			return nil
		}
	}
	return errors.New("未找到可打开项目的 VS Code 或 VSCodium")
}

func materialShellQuote(path string) string {
	return "'" + strings.ReplaceAll(path, "'", "'\\''") + "'"
}

func stageMaterialCommand(m materialLaunch) (string, error) {
	command := "cd -- " + materialShellQuote(filepath.Dir(m.file)) + " && " +
		materialShellQuote(m.interpreter) + " " + materialShellQuote(m.file)
	if m.action == "create-venv" {
		command = "cd -- " + materialShellQuote(m.project) +
			" && /bin/mkdir -- .venv && " + materialShellQuote(m.interpreter) + " -m venv .venv"
	}
	script := "#!/bin/zsh\n/bin/rm -f -- \"$0\"\n" + command +
		"\nexit_code=$?\nprintf '\\nPython exited with status %s. Press Return to close.\\n' \"$exit_code\"\nread -r _\nexit \"$exit_code\"\n"
	file, err := os.CreateTemp("", "scistation-python-*.command")
	if err != nil {
		return "", err
	}
	name := file.Name()
	if _, err = file.WriteString(script); err == nil {
		err = file.Chmod(0700)
	}
	closeErr := file.Close()
	if err != nil || closeErr != nil {
		_ = os.Remove(name)
		return "", errors.Join(err, closeErr)
	}
	return name, nil
}

func stageMaterialVSCodeWorkspace(m materialLaunch) (string, error) {
	// Store the task in an app-generated workspace file so a project that
	// already has .vscode/tasks.json keeps all of its existing task definitions.
	workspace := map[string]any{
		"folders": []map[string]string{{"path": m.project}},
		"tasks": map[string]any{
			"version": "2.0.0",
			"tasks": []map[string]any{{
				"label":          "Sci-Station: Run Python Material",
				"type":           "process",
				"command":        m.interpreter,
				"args":           []string{m.file},
				"options":        map[string]string{"cwd": m.project},
				"group":          map[string]any{"kind": "build", "isDefault": true},
				"presentation":   map[string]any{"reveal": "always", "panel": "dedicated", "clear": true},
				"problemMatcher": []string{},
			}},
		},
	}
	data, err := json.MarshalIndent(workspace, "", "  ")
	if err != nil {
		return "", err
	}
	dir, err := os.MkdirTemp("", "scistation-vscode-")
	if err != nil {
		return "", err
	}
	name := filepath.Join(dir, "Sci-Station Python.code-workspace")
	if err := os.WriteFile(name, data, 0600); err != nil {
		_ = os.RemoveAll(dir)
		return "", err
	}
	return name, nil
}
