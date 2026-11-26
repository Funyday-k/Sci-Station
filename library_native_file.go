package main

import (
	"errors"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
)

func (a *apiServer) openLibraryPDF(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		reject(w, http.StatusMethodNotAllowed, "请从文献库打开 PDF")
		return
	}
	if runtime.GOOS != "darwin" || !a.desktop || !strings.Contains(r.UserAgent(), desktopUserAgent) {
		reject(w, http.StatusNotImplemented, "此操作需要 macOS 桌面应用")
		return
	}
	library, ok := a.research.(interface{ PaperPDFPath(string) (string, error) })
	if !ok {
		reject(w, http.StatusServiceUnavailable, "文献库不可用")
		return
	}
	var input struct {
		Action string `json:"action"`
	}
	if !jsonBody(w, r, &input) {
		return
	}
	if input.Action != "open" && input.Action != "reveal" {
		reject(w, http.StatusBadRequest, "无法识别 PDF 操作")
		return
	}
	id := strings.TrimSuffix(strings.TrimPrefix(r.URL.Path, "/api/research/papers/"), "/native-file")
	path, err := library.PaperPDFPath(id)
	if err == nil {
		err = regularLibraryPDF(path)
	}
	if err != nil {
		fail(w, err)
		return
	}
	args := []string{path}
	if input.Action == "reveal" {
		args = []string{"-R", path}
	}
	// The command receives one resolved library resource and no caller-supplied
	// path, application, or option.
	if err = exec.CommandContext(r.Context(), "/usr/bin/open", args...).Run(); err != nil {
		if r.Context().Err() == nil {
			reject(w, http.StatusInternalServerError, "无法在系统中打开 PDF")
		}
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func regularLibraryPDF(path string) error {
	if !filepath.IsAbs(path) || filepath.Ext(path) != ".pdf" {
		return errors.New("无效的文献 PDF 路径")
	}
	resolved, err := filepath.EvalSymlinks(path)
	if err != nil {
		return err
	}
	if resolved != path {
		return errors.New("文献 PDF 路径不能包含符号链接")
	}
	info, err := os.Lstat(path)
	if err != nil {
		return err
	}
	if !info.Mode().IsRegular() {
		return errors.New("文献 PDF 不是普通文件")
	}
	return nil
}
