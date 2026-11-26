package desktop

import (
	"context"
	"errors"
	"io"
	"mime"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"scistation.local/desktop/internal/meeting"
)

const materialUploadPath = "/api/studio/materials"
const maxMaterialUploadRequest = meeting.MaxMaterialBytes + (64 << 10)
const desktopUserAgent = "SciStationDesktop/1.0"

func (a *apiServer) uploadMaterial(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", "POST")
		reject(w, http.StatusMethodNotAllowed, "请通过圆桌上传会议附件")
		return
	}
	if r.ContentLength > maxMaterialUploadRequest {
		reject(w, http.StatusRequestEntityTooLarge, "单份附件最多 12 MiB")
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, maxMaterialUploadRequest)
	if err := r.ParseMultipartForm(meeting.MaxMaterialBytes); err != nil {
		var limit *http.MaxBytesError
		if errors.As(err, &limit) {
			reject(w, http.StatusRequestEntityTooLarge, "单份附件最多 12 MiB")
		} else {
			reject(w, http.StatusBadRequest, "请提交一份有效的会议附件")
		}
		return
	}
	form := r.MultipartForm
	defer form.RemoveAll()
	files := form.File["file"]
	if len(files) != 1 || len(form.File) != 1 || len(form.Value) > 0 {
		reject(w, http.StatusBadRequest, "每次请通过 file 提交一份会议附件")
		return
	}
	if files[0].Size > meeting.MaxMaterialBytes {
		reject(w, http.StatusRequestEntityTooLarge, "单份附件最多 12 MiB")
		return
	}
	f, err := files[0].Open()
	if err != nil {
		reject(w, http.StatusInternalServerError, "无法读取上传的会议附件")
		return
	}
	defer f.Close()
	m, err := a.meetings.StoreMaterial(files[0].Filename, f)
	if err != nil {
		if errors.Is(err, meeting.ErrMaterialTooLarge) {
			reject(w, http.StatusRequestEntityTooLarge, "单份附件最多 12 MiB")
		} else {
			reject(w, http.StatusInternalServerError, "无法保存会议附件，请检查本地存储后重试")
		}
		return
	}
	reply(w, http.StatusCreated, m)
}

func (a *apiServer) downloadMaterial(w http.ResponseWriter, r *http.Request, id string) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		w.Header().Set("Allow", "GET, HEAD")
		reject(w, http.StatusMethodNotAllowed, "会议附件仅供读取")
		return
	}
	m, err := a.meetings.FindMaterial(id)
	if err != nil {
		rejectMaterialRead(w, err)
		return
	}
	f, err := a.meetings.OpenMaterial(m.ID)
	if err != nil {
		rejectMaterialRead(w, err)
		return
	}
	defer f.Close()

	contentType, disposition := "application/octet-stream", "attachment"
	if r.URL.Query().Get("preview") == "1" {
		var prefix [512]byte
		n, err := f.ReadAt(prefix[:], 0)
		if err != nil && !errors.Is(err, io.EOF) {
			rejectMaterialRead(w, err)
			return
		}
		switch detected := http.DetectContentType(prefix[:n]); detected {
		case "image/gif", "image/jpeg", "image/png", "image/webp":
			contentType, disposition = detected, "inline"
		}
	}
	w.Header().Set("Content-Type", contentType)
	w.Header().Set("Content-Disposition", mime.FormatMediaType(disposition, map[string]string{"filename": m.Name}))
	w.Header().Set("Content-Security-Policy", "default-src 'none'; sandbox")
	http.ServeContent(w, r, "", time.Time{}, f)
}

func (a *apiServer) saveMaterial(w http.ResponseWriter, r *http.Request, id string) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", "POST")
		reject(w, http.StatusMethodNotAllowed, "请通过圆桌保存会议附件")
		return
	}
	var request *struct{}
	if !jsonBody(w, r, &request) {
		return
	}
	if request == nil {
		reject(w, http.StatusBadRequest, "请提交空对象")
		return
	}
	m, err := a.meetings.FindMaterial(id)
	if err != nil {
		rejectMaterialRead(w, err)
		return
	}
	f, err := a.meetings.OpenMaterial(m.ID)
	if err != nil {
		rejectMaterialRead(w, err)
		return
	}
	defer f.Close()

	a.saveLocalDownload(w, r, m.Name, f)
}

func (a *apiServer) saveLocalDownload(w http.ResponseWriter, r *http.Request, name string, content io.Reader) {
	pick := a.savePicker()
	if pick == nil || !strings.Contains(r.UserAgent(), "SciStationDesktop/") {
		reply(w, http.StatusOK, map[string]bool{"browser_download": true})
		return
	}
	if !a.saveDialog.TryLock() {
		reject(w, http.StatusConflict, "请先处理已打开的保存窗口")
		return
	}
	defer a.saveDialog.Unlock()
	ctx := r.Context()
	if ctx.Err() != nil {
		return
	}
	path, err := pick(name, strings.TrimPrefix(filepath.Ext(name), "."))
	if ctx.Err() != nil {
		return
	}
	if errors.Is(err, context.Canceled) || (err == nil && path == "") {
		reply(w, http.StatusOK, map[string]bool{"saved": false})
		return
	}
	if err != nil {
		reject(w, http.StatusInternalServerError, "无法打开系统保存窗口")
		return
	}
	if err = writeNativeExport(ctx, path, content); err != nil {
		if ctx.Err() == nil {
			reject(w, http.StatusInternalServerError, "无法写入文件，请检查所选位置后重试")
		}
		return
	}
	reply(w, http.StatusOK, map[string]bool{"saved": true})
}

func rejectMaterialRead(w http.ResponseWriter, err error) {
	if errors.Is(err, os.ErrNotExist) {
		reject(w, http.StatusNotFound, "未找到会议附件")
		return
	}
	reject(w, http.StatusInternalServerError, "无法读取会议附件")
}
