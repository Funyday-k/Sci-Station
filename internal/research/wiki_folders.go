package research

import (
	"net/http"
	"slices"
	"strings"
)

func projectWikiFolders(d projectData) []string {
	paths := map[string]string{}
	add := func(path string) {
		for path != "" {
			key := strings.ToLower(path)
			if prior := paths[key]; prior == "" || path < prior {
				paths[key] = path
			}
			last := strings.LastIndexByte(path, '/')
			if last < 0 {
				break
			}
			path = path[:last]
		}
	}
	for _, path := range d.WikiFolders {
		add(path)
	}
	for _, note := range d.Notes {
		if !note.Archived {
			add(note.Namespace)
		}
	}
	out := make([]string, 0, len(paths))
	for _, path := range paths {
		out = append(out, path)
	}
	slices.Sort(out)
	return out
}

func (s *Service) wikiFolders(w http.ResponseWriter, r *http.Request) {
	if r.Method == "GET" || r.Method == "HEAD" {
		s.mu.RLock()
		d, ok := s.loadProject(w, r.PathValue("project"))
		s.mu.RUnlock()
		if ok {
			jsonReply(w, 200, projectWikiFolders(d))
		}
		return
	}
	var in struct {
		Path string `json:"path"`
	}
	if !payload(w, r, &in) {
		return
	}
	path := strings.TrimSpace(in.Path)
	if !validWikiPath(path) {
		jsonFail(w, 400, "Wiki 目录路径无效")
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	d, ok := s.loadProject(w, r.PathValue("project"))
	if !ok {
		return
	}
	for _, prior := range d.WikiFolders {
		if strings.EqualFold(prior, path) {
			jsonFail(w, 409, "Wiki 目录已存在")
			return
		}
	}
	d.WikiFolders = append(slices.Clone(d.WikiFolders), path)
	if s.save(w, d) {
		jsonReply(w, 201, projectWikiFolders(d))
	}
}
