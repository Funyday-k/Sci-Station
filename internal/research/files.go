package research

import (
	"errors"
	"mime"
	"net/http"
	"os"
	"path/filepath"

	"scistation.local/desktop/internal/workspace"
)

func (s *Service) files(w http.ResponseWriter, r *http.Request) {
	project := r.PathValue("project")
	path := r.URL.Query().Get("path")
	if r.Method == "GET" || r.Method == "HEAD" {
		switch r.URL.Query().Get("view") {
		case "materials":
			var materials []workspace.MaterialFile
			err := s.WithProjectDirectory(project, func(directory string) error {
				var err error
				materials, err = workspace.MaterialCatalog(directory)
				return err
			})
			if err != nil {
				fileError(w, err)
				return
			}
			jsonReply(w, 200, materials)
		case "preview":
			s.projectMaterialPreview(w, r, project, path)
		case "":
			s.projectTextFile(w, project, path)
		default:
			jsonFail(w, 400, "未知的项目文件视图")
		}
		return
	}
	var in struct {
		Path    string  `json:"path"`
		Text    *string `json:"text"`
		Version string  `json:"version"`
	}
	if !payload(w, r, &in) {
		return
	}
	if in.Text == nil || in.Path == "" || in.Version == "" {
		jsonFail(w, 400, "请提供文件路径、文本和读取时的版本")
		return
	}
	err := s.WithProjectDirectory(project, func(directory string) error {
		_, err := workspace.Write(directory, in.Path, *in.Text, in.Version)
		return err
	})
	if err != nil {
		fileError(w, err)
		return
	}
	jsonReply(w, 200, map[string]bool{"saved": true})
}

func (s *Service) projectTextFile(w http.ResponseWriter, project, path string) {
	var result any
	err := s.WithProjectDirectory(project, func(directory string) error {
		if path == "" {
			files, err := workspace.Catalog(directory)
			result = files
			return err
		}
		file, err := workspace.Read(directory, path)
		if err != nil {
			return err
		}
		if file.Version == workspace.MissingVersion {
			return os.ErrNotExist
		}
		result = file
		return nil
	})
	if err != nil {
		fileError(w, err)
		return
	}
	jsonReply(w, 200, result)
}

func (s *Service) projectMaterialPreview(w http.ResponseWriter, r *http.Request, project, path string) {
	var file *os.File
	var material workspace.MaterialFile
	var mediaType string
	err := s.WithProjectDirectory(project, func(directory string) error {
		var err error
		file, material, mediaType, err = workspace.MaterialPreview(directory, path)
		return err
	})
	if err != nil {
		fileError(w, err)
		return
	}
	defer file.Close()
	name := filepath.Base(material.Path)
	w.Header().Set("Content-Type", mediaType)
	w.Header().Set("Content-Disposition", mime.FormatMediaType("inline", map[string]string{"filename": name}))
	w.Header().Set("Content-Security-Policy", "default-src 'none'; sandbox; frame-ancestors 'self'")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	http.ServeContent(w, r, name, material.Modified, file)
}

func fileError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, os.ErrNotExist):
		jsonFail(w, 404, "未找到该项目或文件")
	case errors.Is(err, os.ErrPermission):
		jsonFail(w, 403, "项目文件夹未授权或不可访问")
	case errors.Is(err, workspace.ErrConflict):
		jsonFail(w, 409, "文件已被修改，请重读后保存")
	case errors.Is(err, workspace.ErrInvalid):
		jsonFail(w, 400, "所选路径、文件类型或预览大小不可用")
	default:
		jsonFail(w, 500, "无法访问所选文件夹")
	}
}
