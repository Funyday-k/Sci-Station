package research

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"
)

// All page endpoints operate on a library-resolved paper and its immutable PDF.
func readerPages(w http.ResponseWriter, r *http.Request, lib *PaperLibrary, id string, tail []string) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		w.Header().Set("Allow", "GET, HEAD")
		http.Error(w, "只支持读取页面", http.StatusMethodNotAllowed)
		return
	}
	path, err := lib.PDFPath(id)
	if err != nil {
		http.Error(w, "没有可读的本地 PDF", http.StatusNotFound)
		return
	}
	op, page, query := "info", 0, ""
	if len(tail) == 1 && tail[0] == "search" {
		op, query = "search", strings.TrimSpace(r.URL.Query().Get("q"))
		if query == "" || len([]rune(query)) > 240 {
			http.Error(w, "请输入 1 至 240 个字符", http.StatusBadRequest)
			return
		}
	} else if len(tail) > 0 {
		page, err = strconv.Atoi(tail[0])
		if err != nil || page < 1 || len(tail) > 2 || (len(tail) == 2 && tail[1] != "image" && tail[1] != "ocr") {
			http.NotFound(w, r)
			return
		}
		op = "page"
		if len(tail) == 2 {
			op = tail[1]
		}
	}
	select {
	case pageWorkers <- struct{}{}:
		defer func() { <-pageWorkers }()
	case <-r.Context().Done():
		return
	}
	data, err := nativePDFPage(path, op, page, query)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnprocessableEntity)
		return
	}
	mime := "application/json; charset=utf-8"
	if op == "image" {
		mime = "image/png"
	}
	w.Header().Set("Content-Type", mime)
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("Cache-Control", "private, max-age=3600")
	w.Header().Set("Content-Length", strconv.Itoa(len(data)))
	if r.Method != http.MethodHead {
		_, _ = w.Write(data)
	}
}

var pageWorkers = make(chan struct{}, 3)

func pageError(data []byte) error {
	var result struct {
		Error string `json:"error"`
	}
	if json.Unmarshal(data, &result) == nil && result.Error != "" {
		return errors.New(result.Error)
	}
	return errors.New("无法解析 PDF 页面")
}
