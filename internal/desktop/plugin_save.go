package desktop

import (
	"context"
	"errors"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"unicode"

	"scistation.local/desktop/internal/plugins"
)

func (a *apiServer) setSavePicker(pick func(string, string) (string, error)) {
	a.pickMu.Lock()
	defer a.pickMu.Unlock()
	a.savePick = pick
}

func (a *apiServer) savePicker() func(string, string) (string, error) {
	a.pickMu.RLock()
	defer a.pickMu.RUnlock()
	return a.savePick
}

func (a *apiServer) savePluginOutput(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", "POST")
		reject(w, http.StatusMethodNotAllowed, "请通过插件工具保存输出")
		return
	}
	var req struct {
		Filename string `json:"filename"`
		Text     string `json:"text"`
		Format   string `json:"format"`
	}
	if !jsonBody(w, r, &req) {
		return
	}
	ext := map[string]string{"text": "txt", "markdown": "md"}[req.Format]
	nameOK := len(req.Filename) <= 250 && len(req.Filename) > len(ext)+1 &&
		filepath.Base(req.Filename) == req.Filename && !strings.ContainsAny(req.Filename, "\\:") &&
		strings.IndexFunc(req.Filename, unicode.IsControl) < 0 && strings.HasSuffix(req.Filename, "."+ext)
	if ext == "" || !nameOK || len(req.Text) > plugins.MaxOutputBytes {
		reject(w, http.StatusBadRequest, "插件输出的格式、名称或大小不符合要求")
		return
	}
	pick := a.savePicker()
	if pick == nil {
		reply(w, http.StatusOK, map[string]bool{"browser_download": true})
		return
	}
	if !a.saveDialog.TryLock() {
		reject(w, http.StatusConflict, "请先处理已打开的保存窗口")
		return
	}
	defer a.saveDialog.Unlock()
	path, err := pick(req.Filename, ext)
	if err != nil {
		fail(w, err)
		return
	}
	if path == "" {
		reply(w, http.StatusOK, map[string]bool{"saved": false})
		return
	}
	if err := r.Context().Err(); err != nil {
		return
	}
	if !strings.EqualFold(filepath.Ext(path), "."+ext) {
		reject(w, http.StatusBadRequest, "请选择匹配的文本文件扩展名")
		return
	}
	if err = writeNativeExport(r.Context(), path, strings.NewReader(req.Text)); err != nil {
		if r.Context().Err() != nil {
			return
		}
		fail(w, err)
		return
	}
	reply(w, http.StatusOK, map[string]bool{"saved": true})
}

// The destination comes exclusively from the native save panel. Stage the
// result beside it so a failed write cannot truncate a previous export.
func writeNativeExport(ctx context.Context, path string, source io.Reader) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	if existing, err := os.Lstat(path); err == nil && !existing.Mode().IsRegular() {
		return errors.New("请选择普通文件作为保存目标")
	} else if err != nil && !os.IsNotExist(err) {
		return err
	}
	staged, err := os.CreateTemp(filepath.Dir(path), ".roundtable-export-*")
	if err != nil {
		return err
	}
	defer os.Remove(staged.Name())
	defer staged.Close()
	if _, err = io.Copy(staged, exportReader{ctx: ctx, source: source}); err != nil {
		return err
	}
	if err = staged.Close(); err != nil {
		return err
	}
	if err = ctx.Err(); err != nil {
		return err
	}
	return os.Rename(staged.Name(), path)
}

type exportReader struct {
	ctx    context.Context
	source io.Reader
}

func (r exportReader) Read(p []byte) (int, error) {
	if err := r.ctx.Err(); err != nil {
		return 0, err
	}
	return r.source.Read(p)
}
