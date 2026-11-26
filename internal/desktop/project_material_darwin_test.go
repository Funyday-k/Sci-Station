//go:build darwin && !nogui

package desktop

import (
	"encoding/json"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestStagedTerminalLauncherFollowsSelectedFileAndWorkingDirectory(t *testing.T) {
	project, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	working := "code/author's analysis"
	name := "plot file.py"
	materialTestWrite(t, project, filepath.Join(working, name), "printf 'fixture: %s / %s\n' \"$PWD\" \"$0\"\n", 0600)
	file := filepath.Join(project, working, name)
	commandFile, err := stageMaterialCommand(materialLaunch{
		action: "run-terminal", project: project, file: file, interpreter: "/bin/sh",
	})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Remove(commandFile) })
	cmd := exec.CommandContext(t.Context(), "/bin/zsh", commandFile)
	cmd.Stdin = strings.NewReader("\n")
	output, err := cmd.CombinedOutput()
	if err != nil || !strings.Contains(string(output), "fixture: "+filepath.Dir(file)+" / "+file) {
		t.Fatalf("launcher changed the working directory or arguments: %s, %v", output, err)
	}
	if _, err := os.Stat(commandFile); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("completed terminal launcher was not removed: %v", err)
	}
}

func TestStagedEditorWorkspaceUsesInterpreterWithoutReplacingExistingTasks(t *testing.T) {
	project := t.TempDir()
	existing := ".vscode/tasks.json"
	const saved = `{"version":"2.0.0","tasks":[{"label":"User task"}]}`
	materialTestWrite(t, project, existing, saved, 0600)
	m := materialLaunch{project: project, file: filepath.Join(project, "code", "run.py"), interpreter: filepath.Join(project, ".venv", "bin", "python")}
	config, err := stageMaterialVSCodeWorkspace(m)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(filepath.Dir(config)) })
	body, err := os.ReadFile(config)
	if err != nil {
		t.Fatal(err)
	}
	var settings struct {
		Folders []struct{ Path string }
		Tasks   struct {
			Tasks []struct {
				Type, Command string
				Args          []string
				Options       struct{ CWD string }
			}
		}
	}
	if err := json.Unmarshal(body, &settings); err != nil {
		t.Fatal(err)
	}
	if len(settings.Folders) != 1 || settings.Folders[0].Path != m.project || len(settings.Tasks.Tasks) != 1 {
		t.Fatalf("incorrect generated workspace: %s", body)
	}
	task := settings.Tasks.Tasks[0]
	if task.Type != "process" || task.Command != m.interpreter || len(task.Args) != 1 || task.Args[0] != m.file || task.Options.CWD != m.project {
		t.Fatalf("incorrect generated task: %+v", task)
	}
	userFile, err := os.ReadFile(filepath.Join(project, existing))
	if err != nil || string(userFile) != saved {
		t.Fatalf("existing editor tasks were altered: %s, %v", userFile, err)
	}
}
