package research

import (
	"errors"
	"net/http"
	"os"

	"scistation.local/desktop/internal/workspace"
)

func (s *Service) files(w http.ResponseWriter, r *http.Request) {
	s.mu.RLock()
	d, ok := s.loadProject(w, r.PathValue("project"))
	s.mu.RUnlock()
	if !ok {
		return
	}
	path := r.URL.Query().Get("path")
	if r.Method == "GET" || r.Method == "HEAD" {
		if path == "" {
			files, err := workspace.Catalog(d.Project.Path)
			if err != nil {
				fileError(w, err)
				return
			}
			if files == nil {
				files = []string{}
			}
			jsonReply(w, 200, files)
			return
		}
		file, err := workspace.Read(d.Project.Path, path)
		if err != nil {
			fileError(w, err)
			return
		}
		if file.Version == workspace.MissingVersion {
			jsonFail(w, 404, "未找到项目文件")
			return
		}
		jsonReply(w, 200, file)
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
	if _, err := workspace.Write(d.Project.Path, in.Path, *in.Text, in.Version); err != nil {
		fileError(w, err)
		return
	}
	jsonReply(w, 200, map[string]bool{"saved": true})
}
func fileError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, os.ErrNotExist):
		jsonFail(w, 404, "未找到该文件")
	case errors.Is(err, workspace.ErrConflict):
		jsonFail(w, 409, "文件已被修改，请重读后保存")
	case errors.Is(err, workspace.ErrInvalid):
		jsonFail(w, 400, "所选路径或文件类型不可用")
	default:
		jsonFail(w, 500, "无法访问所选文件夹")
	}
}
