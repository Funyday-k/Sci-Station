package research

import (
	"bufio"
	"errors"
	"io"
	"maps"
	"mime"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

const maxMaterialSize = 256 << 20

func (s *Service) registerMaterials() {
	base := prefix + "/projects/{project}/materials"
	for _, method := range []string{"GET", "POST"} {
		s.mux.HandleFunc(method+" "+base, s.materials)
	}
	for _, method := range []string{"GET", "PATCH", "DELETE"} {
		s.mux.HandleFunc(method+" "+base+"/{material}", s.materials)
	}
	s.mux.HandleFunc("GET "+base+"/{material}/content", s.materialContent)
}

func fileLabel(name string) bool {
	return label(name, 240) && name == filepath.Base(name) && !strings.ContainsAny(name, `/\`) && name != "." && name != ".."
}
func (s *Service) blobPath(id string) string { return filepath.Join(s.dir, "blobs", id) }

func (s *Service) materials(w http.ResponseWriter, r *http.Request) {
	pid, id := r.PathValue("project"), r.PathValue("material")
	if r.Method == "POST" {
		s.uploadMaterial(w, r, pid)
		return
	}
	if r.Method == "GET" || r.Method == "HEAD" {
		s.mu.RLock()
		defer s.mu.RUnlock()
		d, ok := s.loadProject(w, pid)
		if !ok {
			return
		}
		if id == "" {
			jsonReply(w, 200, valuesBy(d.Materials, func(a, b Material) bool {
				if a.Name == b.Name {
					return a.ID < b.ID
				}
				return a.Name < b.Name
			}))
			return
		}
		m, ok := d.Materials[id]
		if found(w, ok) {
			jsonReply(w, 200, m)
		}
		return
	}
	var in struct {
		Name     string `json:"name"`
		Revision int    `json:"revision"`
	}
	if r.Method == "PATCH" && !payload(w, r, &in) {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	d, ok := s.loadProject(w, pid)
	if !ok {
		return
	}
	m, ok := d.Materials[id]
	if !found(w, ok) {
		return
	}
	d.Materials = maps.Clone(d.Materials)
	if r.Method == "DELETE" {
		if !revisionOK(w, m.Revision, queryRevision(r.URL.Query())) {
			return
		}
		delete(d.Materials, id)
		if s.save(w, d) {
			_ = os.Remove(s.blobPath(id))
			w.WriteHeader(204)
		}
		return
	}
	if !revisionOK(w, m.Revision, in.Revision) {
		return
	}
	if !fileLabel(in.Name) {
		jsonFail(w, 400, "文件名无效")
		return
	}
	m.Name = in.Name
	m.bump()
	d.Materials[id] = m
	if s.save(w, d) {
		jsonReply(w, 200, m)
	}
}
func (s *Service) uploadMaterial(w http.ResponseWriter, r *http.Request, pid string) {
	if !s.hasProject(pid) {
		jsonFail(w, 404, "未找到项目")
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, maxMaterialSize+(1<<20))
	multipart, err := r.MultipartReader()
	if err != nil {
		jsonFail(w, 400, "需要 multipart 文件")
		return
	}
	part, err := multipart.NextPart()
	if err != nil || part.FormName() != "file" || !fileLabel(part.FileName()) {
		jsonFail(w, 400, "请选择一个文件")
		return
	}
	m := Material{Entity: fresh(), ProjectID: pid, Name: part.FileName()}
	source := bufio.NewReader(part)
	sample, err := source.Peek(512)
	if err != nil && err != io.EOF {
		jsonFail(w, 400, "无法读取文件")
		return
	}
	m.MediaType = http.DetectContentType(sample)
	// Material bytes remain private until the durable metadata record is published.
	tmp, err := os.CreateTemp(filepath.Join(s.dir, "blobs"), ".upload-")
	if err != nil {
		jsonFail(w, 500, "无法保存附件")
		return
	}
	defer os.Remove(tmp.Name())
	m.Size, err = io.Copy(tmp, io.LimitReader(source, maxMaterialSize+1))
	if err == nil && m.Size <= maxMaterialSize {
		err = tmp.Sync()
	}
	cerr := tmp.Close()
	if m.Size > maxMaterialSize {
		jsonFail(w, 413, "单份材料上限为 256 MiB")
		return
	}
	if err != nil {
		var maxErr *http.MaxBytesError
		if errors.As(err, &maxErr) {
			jsonFail(w, 413, "上传内容过大")
		} else {
			jsonFail(w, 400, "文件上传中断")
		}
		return
	}
	if cerr != nil {
		jsonFail(w, 500, "无法保存附件")
		return
	}
	if _, err = multipart.NextPart(); err != io.EOF {
		jsonFail(w, 400, "每次请提交一个文件")
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	d, ok := s.loadProject(w, pid)
	if !ok {
		return
	}
	path := s.blobPath(m.ID)
	if err = os.Rename(tmp.Name(), path); err != nil {
		jsonFail(w, 500, "无法提交附件")
		return
	}
	d.Materials = maps.Clone(d.Materials)
	d.Materials[m.ID] = m
	if !s.save(w, d) {
		_ = os.Remove(path)
		return
	}
	jsonReply(w, 201, m)
}
func (s *Service) materialContent(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("material")
	s.mu.RLock()
	d, ok := s.loadProject(w, r.PathValue("project"))
	if !ok {
		s.mu.RUnlock()
		return
	}
	m, ok := d.Materials[id]
	if !found(w, ok) {
		s.mu.RUnlock()
		return
	}
	if !validID(id) {
		s.mu.RUnlock()
		jsonFail(w, 400, "无效的材料编号")
		return
	}
	path := s.blobPath(id)
	f, err := os.OpenFile(path, os.O_RDONLY|syscall.O_NOFOLLOW, 0)
	s.mu.RUnlock()
	if err != nil {
		jsonFail(w, 404, "材料文件不可用")
		return
	}
	defer f.Close()
	stat, err := f.Stat()
	if err != nil || !stat.Mode().IsRegular() {
		jsonFail(w, 404, "材料文件不可用")
		return
	}
	disp := "attachment"
	if r.URL.Query().Get("download") != "1" {
		switch strings.Split(m.MediaType, ";")[0] {
		case "application/pdf", "text/plain", "image/png", "image/jpeg", "image/gif", "image/webp":
			disp = "inline"
		}
	}
	w.Header().Set("Content-Type", m.MediaType)
	w.Header().Set("Content-Security-Policy", "default-src 'none'; sandbox; frame-ancestors 'self'")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("Content-Disposition", mime.FormatMediaType(disp, map[string]string{"filename": m.Name}))
	stamp, _ := time.Parse(time.RFC3339Nano, m.UpdatedAt)
	http.ServeContent(w, r, m.Name, stamp, f)
}
