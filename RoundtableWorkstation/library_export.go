package main

import (
	"context"
	"errors"
	"net/http"
	"net/url"
	"path/filepath"
	"strings"
)

func (a *apiServer) saveLibraryBibtex(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		reject(w, http.StatusMethodNotAllowed, "请从文献库保存 BibTeX")
		return
	}
	var input *struct{}
	if !jsonBody(w, r, &input) {
		return
	}
	if input == nil {
		reject(w, http.StatusBadRequest, "请提交空对象")
		return
	}
	library, ok := a.research.(interface {
		LibraryBibtex(url.Values) (string, error)
	})
	if !ok {
		reject(w, http.StatusServiceUnavailable, "文献库不可用")
		return
	}
	contents, err := library.LibraryBibtex(r.URL.Query())
	if err != nil {
		fail(w, err)
		return
	}
	if contents == "" {
		reject(w, http.StatusNotFound, "没有符合筛选条件的文献")
		return
	}
	pick := a.savePicker()
	if pick == nil || !strings.Contains(r.UserAgent(), desktopUserAgent) {
		reply(w, http.StatusOK, map[string]bool{"browser_download": true})
		return
	}
	if !a.saveDialog.TryLock() {
		reject(w, http.StatusConflict, "请先处理已打开的保存窗口")
		return
	}
	defer a.saveDialog.Unlock()
	if r.Context().Err() != nil {
		return
	}
	path, err := pick("references.bib", "bib")
	if r.Context().Err() != nil {
		return
	}
	if errors.Is(err, context.Canceled) || (err == nil && path == "") {
		reply(w, http.StatusOK, map[string]bool{"saved": false})
		return
	}
	if err != nil {
		fail(w, err)
		return
	}
	if !strings.EqualFold(filepath.Ext(path), ".bib") {
		reject(w, http.StatusBadRequest, "请选择 .bib 文件")
		return
	}
	if err = writeNativeExport(r.Context(), path, strings.NewReader(contents)); err != nil {
		if r.Context().Err() == nil {
			fail(w, err)
		}
		return
	}
	reply(w, http.StatusOK, map[string]bool{"saved": true})
}
