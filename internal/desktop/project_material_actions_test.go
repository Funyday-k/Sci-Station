package desktop

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"scistation.local/desktop/internal/research"
)

func materialTestRequest(t *testing.T, handler http.Handler, method, path, body string, native bool, status int) *httptest.ResponseRecorder {
	t.Helper()
	r := httptest.NewRequest(method, "http://127.0.0.1:18765"+path, strings.NewReader(body))
	r.Header.Set("Content-Type", "application/json")
	r.Header.Set("X-Roundtable", "1")
	if native {
		r.Header.Set("User-Agent", desktopUserAgent)
	}
	w := httptest.NewRecorder()
	handler.ServeHTTP(w, r)
	if w.Code != status {
		t.Fatalf("%s %s: got %d want %d: %s", method, path, w.Code, status, w.Body.String())
	}
	return w
}

func materialProject(t *testing.T, handler http.Handler, name string) research.Project {
	t.Helper()
	r := materialTestRequest(t, handler, "POST", "/api/research/projects", `{"name":"`+name+`"}`, false, 201)
	var project research.Project
	if err := json.Unmarshal(r.Body.Bytes(), &project); err != nil {
		t.Fatal(err)
	}
	return project
}

func materialTestWrite(t *testing.T, dir, path, text string, mode os.FileMode) {
	t.Helper()
	filename := filepath.Join(dir, path)
	if err := os.MkdirAll(filepath.Dir(filename), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filename, []byte(text), mode); err != nil {
		t.Fatal(err)
	}
}

func TestProjectMaterialsUseActiveGrantedProjectAndNativeConfirmation(t *testing.T) {
	lab, err := research.New(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	a := &apiServer{research: lab}
	handler := a.serve(18765)
	alpha := materialProject(t, handler, "Alpha")
	beta := materialProject(t, handler, "Beta")
	materialTestWrite(t, alpha.Path, "code/analysis.py", "print('alpha')\n", 0600)
	materialTestWrite(t, beta.Path, "code/analysis.py", "print('beta')\n", 0600)
	materialTestWrite(t, alpha.Path, ".venv/pyvenv.cfg", "home = /usr/bin", 0600)
	materialTestWrite(t, alpha.Path, ".venv/bin/python", "#!/bin/sh\n", 0700)

	base := "/api/research/projects/" + alpha.ID + "/files"
	preview := materialTestRequest(t, handler, "GET", base+"?view=preview&path=code/analysis.py", "", false, 200)
	if preview.Body.String() != "print('alpha')\n" || preview.Header().Get("Content-Type") != "text/plain; charset=utf-8" ||
		!strings.Contains(preview.Header().Get("Content-Security-Policy"), "sandbox") {
		t.Fatalf("invalid inline preview: %v, %q", preview.Header(), preview.Body.String())
	}
	catalog := materialTestRequest(t, handler, "GET", base+"?view=materials", "", false, 200)
	if !strings.Contains(catalog.Body.String(), `"path":"code/analysis.py"`) || strings.Contains(catalog.Body.String(), ".venv") {
		t.Fatalf("incorrect material catalog: %s", catalog.Body)
	}

	actions := &projectMaterialActions{}
	a.materialActions = actions
	input := `{"project":"` + alpha.ID + `","action":"run-terminal","path":"code/analysis.py","runtime":"local"}`
	materialTestRequest(t, handler, "POST", projectMaterialActionPath, input, false, 403)
	var confirmed bool
	var launched []materialLaunch
	actions.confirm = func(_ context.Context, _, text string) bool {
		if !strings.Contains(text, filepath.Join(alpha.Path, "code", "analysis.py")) ||
			!strings.Contains(text, filepath.Join(alpha.Path, ".venv", "bin", "python")) {
			t.Fatalf("confirmation did not include the actual file and interpreter: %s", text)
		}
		return confirmed
	}
	actions.launch = func(_ context.Context, item materialLaunch) error {
		launched = append(launched, item)
		return nil
	}
	cancel := materialTestRequest(t, handler, "POST", projectMaterialActionPath, input, true, 200)
	if !strings.Contains(cancel.Body.String(), `"performed":false`) || len(launched) != 0 {
		t.Fatalf("canceled action was launched: %s", cancel.Body)
	}
	confirmed = true
	materialTestRequest(t, handler, "POST", projectMaterialActionPath, input, true, 200)
	if len(launched) != 1 || launched[0].file != filepath.Join(alpha.Path, "code", "analysis.py") ||
		launched[0].interpreter != filepath.Join(alpha.Path, ".venv", "bin", "python") {
		t.Fatalf("launch resolved a different project or environment: %+v", launched)
	}
	actions.confirm = func(_ context.Context, _, _ string) bool {
		materialTestRequest(t, handler, "DELETE", "/api/research/projects/"+alpha.ID+"?revision=1", "", false, 204)
		return true
	}
	materialTestRequest(t, handler, "POST", projectMaterialActionPath, input, true, 404)
	materialTestRequest(t, handler, "GET", base+"?view=preview&path=code/analysis.py", "", false, 404)
	if len(launched) != 1 {
		t.Fatal("project changed after confirmation but the previously resolved action was launched")
	}
}

func TestSelectedPythonEnvironmentIsProjectSpecific(t *testing.T) {
	lab, err := research.New(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	a := &apiServer{research: lab}
	handler := a.serve(18765)
	alpha := materialProject(t, handler, "Alpha")
	beta := materialProject(t, handler, "Beta")
	env, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	materialTestWrite(t, env, "bin/python", "#!/bin/sh\n", 0700)
	a.materialActions = &projectMaterialActions{pick: func() (string, error) { return env, nil }}
	input := `{"project":"` + alpha.ID + `","action":"select-venv"}`
	materialTestRequest(t, handler, "POST", projectMaterialActionPath, input, true, 200)
	if got := a.materialActions.chosenPython(alpha.ID); got != filepath.Join(env, "bin", "python") {
		t.Fatalf("wrong selected Python: %s", got)
	}
	if got := a.materialActions.chosenPython(beta.ID); got != "" {
		t.Fatalf("environment leaked to another project: %s", got)
	}
	if err := os.Remove(filepath.Join(env, "bin", "python")); err != nil {
		t.Fatal(err)
	}
	if got := a.materialActions.chosenPython(alpha.ID); got != "" {
		t.Fatalf("deleted environment remained available: %s", got)
	}
}

func TestRevokedDirectoryBlocksPreviewEditingAndDesktopHandoff(t *testing.T) {
	lab, err := research.New(filepath.Join(t.TempDir(), "research"))
	if err != nil {
		t.Fatal(err)
	}
	directory, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	lab.SetPathValidator(func(path string) bool { return path == directory })
	a := &apiServer{research: lab, materialActions: &projectMaterialActions{}}
	handler := a.serve(18765)
	body, err := json.Marshal(map[string]string{"name": "External", "path": directory})
	if err != nil {
		t.Fatal(err)
	}
	r := materialTestRequest(t, handler, "POST", "/api/research/projects", string(body), false, 201)
	var project research.Project
	if err := json.Unmarshal(r.Body.Bytes(), &project); err != nil {
		t.Fatal(err)
	}
	materialTestWrite(t, directory, "code/model.py", "print('original')\n", 0600)
	materialTestRequest(t, handler, "GET", "/api/research/projects/"+project.ID+"/files?view=materials", "", false, 200)
	materialTestRequest(t, handler, "POST", "/api/research/projects/"+project.ID+"/directory", `{"revision":1,"path":""}`, false, 200)
	projectFiles := "/api/research/projects/" + project.ID + "/files"
	materialTestRequest(t, handler, "GET", projectFiles+"?view=preview&path=code/model.py", "", false, 403)
	materialTestRequest(t, handler, "GET", projectFiles, "", false, 403)
	materialTestRequest(t, handler, "PATCH", projectFiles, `{"path":"code/model.py","version":"missing","text":"changed"}`, false, 403)
	materialTestRequest(t, handler, "POST", projectMaterialActionPath, `{"project":"`+project.ID+`","action":"reveal"}`, true, 403)
	source, err := os.ReadFile(filepath.Join(directory, "code", "model.py"))
	if err != nil || string(source) != "print('original')\n" {
		t.Fatalf("revoked project bytes changed: %q, %v", source, err)
	}
}
