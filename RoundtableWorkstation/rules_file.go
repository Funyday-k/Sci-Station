package main

import (
	"bytes"
	"errors"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"

	"scistation.local/desktop/internal/deliberation"
)

const rulesFileName = "discussion-rules.md"

// openRulesText is deliberately a direct argument invocation, never a shell.
var openRulesText = func(path string) error {
	if runtime.GOOS != "darwin" {
		return errors.New("打开规则文件需要 macOS 桌面应用；可直接查看文件：" + path)
	}
	return exec.Command("/usr/bin/open", "-t", path).Run()
}

func rulesMarkdown(catalog []deliberation.PresetInfo) []byte {
	var b bytes.Buffer
	b.WriteString("# 圆桌讨论规则\n\n")
	b.WriteString("本文件由 Sci-Station 根据当前生效的讨论指令生成，仅供只读参考。应用运行时使用的规则以程序当前版本为准。\n")
	for _, preset := range catalog {
		fmt.Fprintf(&b, "\n## %s\n", preset.Label)
		for _, phase := range preset.Phases {
			fmt.Fprintf(&b, "\n### %s\n\n", phase.Label)
			b.WriteString(strings.TrimSpace(phase.Instructions))
			b.WriteByte('\n')
		}
	}
	return b.Bytes()
}

func writeRulesFile(path string, body []byte) error {
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return err
	}
	f, err := os.CreateTemp(filepath.Dir(path), ".discussion-rules-*")
	if err != nil {
		return err
	}
	tmp := f.Name()
	defer os.Remove(tmp)
	if _, err = f.Write(body); err == nil {
		err = f.Sync()
	}
	if err == nil {
		err = f.Chmod(0444)
	}
	closeErr := f.Close()
	if err != nil {
		return err
	}
	if closeErr != nil {
		return closeErr
	}
	return os.Rename(tmp, path)
}

func (a *apiServer) openRules(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		reject(w, http.StatusMethodNotAllowed, "请使用 POST 打开讨论规则文件")
		return
	}
	var payload struct{}
	if !jsonBody(w, r, &payload) {
		return
	}
	if a == nil || a.prefs == nil || a.prefs.file == "" {
		reject(w, http.StatusInternalServerError, "无法定位应用数据目录")
		return
	}
	path := filepath.Join(filepath.Dir(a.prefs.file), rulesFileName)
	if err := writeRulesFile(path, rulesMarkdown(deliberation.Catalog())); err != nil {
		reject(w, http.StatusInternalServerError, "无法刷新讨论规则文件："+err.Error())
		return
	}
	a.pickMu.RLock()
	desktop := a.pick != nil
	a.pickMu.RUnlock()
	if !desktop {
		reply(w, http.StatusConflict, map[string]string{"path": path, "error": "请从桌面应用的设置打开规则文件"})
		return
	}
	if err := openRulesText(path); err != nil {
		status := http.StatusConflict
		if runtime.GOOS != "darwin" {
			status = http.StatusNotImplemented
		}
		reply(w, status, map[string]string{"error": err.Error(), "path": path})
		return
	}
	reply(w, http.StatusOK, map[string]string{"path": path})
}
