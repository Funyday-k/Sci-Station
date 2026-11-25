package main

import (
	"encoding/json"
	"errors"
	"html/template"
	"math"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"

	"scistation.local/desktop/internal/research"
)

type workspaceSurface struct {
	name  string
	title string
	page  *template.Template
}

var workspaceSurfaces = func() map[string]workspaceSurface {
	surfaces := map[string]workspaceSurface{
		"/research": {name: "research", title: "科研工作台"},
		"/studio":   {name: "studio", title: "科研圆桌"},
		"/reader":   {name: "reader", title: "论文阅读"},
		"/lab":      {name: "lab", title: "AI 实验室"},
		"/tools":    {name: "science-tools", title: "科研工具"},
		"/api-docs": {name: "api", title: "本机 API"},
	}
	for path, surface := range surfaces {
		surface.page = template.Must(template.ParseFS(assets, "static/workspace-shell.html", "static/"+surface.name+".html"))
		surfaces[path] = surface
	}
	return surfaces
}()

func (a *apiServer) serveWorkspaceSurface(w http.ResponseWriter, r *http.Request) bool {
	path := r.URL.Path
	if path == "/" {
		path = "/research"
	}
	if strings.HasPrefix(path, "/static/") && strings.HasSuffix(path, ".html") {
		for dest, surface := range workspaceSurfaces {
			if path == "/static/"+surface.name+".html" {
				link := *r.URL
				link.Path = dest
				http.Redirect(w, r, link.RequestURI(), http.StatusTemporaryRedirect)
				return true
			}
		}
		http.NotFound(w, r)
		return true
	}
	surface, ok := workspaceSurfaces[path]
	if !ok {
		return false
	}
	link := *r.URL
	link.Path = path
	resolved, err := a.resolveWorkspaceRoute(&link)
	if err != nil {
		reject(w, http.StatusInternalServerError, "无法读取工作区导航设置")
		return true
	}
	if resolved != link.RequestURI() {
		http.Redirect(w, r, resolved, http.StatusTemporaryRedirect)
		return true
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if r.Method != http.MethodHead {
		_ = surface.page.Execute(w, struct {
			Title, Surface string
			Desktop        bool
		}{surface.title, surface.name, a.desktop})
	}
	return true
}

// Scope and module checks also apply to a restored route or a copied link.
func (a *apiServer) resolveWorkspaceRoute(link *url.URL) (string, error) {
	q := link.Query()
	project := q.Get("project")
	service, _ := a.research.(*research.Service)
	if service != nil {
		if project != "" && !service.HasActiveProject(project) {
			return "/research?view=projects", nil
		}
		if id := q.Get("paper"); link.Path == "/reader" && id != "" && !service.HasWorkspacePaper(id, project) {
			return libraryRoute(project), nil
		}
		// Workspace configurations can disable an entire module or a project
		// override can hide it. Module state is owned by the research service.
		module := routeModule(link.Path, q.Get("view"), q.Get("tab"))
		if link.Path == "/research" && q.Get("view") == "" && project != "" {
			module = "projects"
		}
		if module != "" {
			enabled, err := service.ModuleEnabled(project, module)
			if err != nil {
				return "", err
			}
			if !enabled {
				if project != "" && module != "projects" {
					return "/research?project=" + url.QueryEscape(project), nil
				}
				return "/research", nil
			}
		}
		if sessionID := q.Get("session"); link.Path == "/studio" && sessionID != "" && a.meetings != nil {
			session, err := a.meetings.Get(sessionID)
			if errors.Is(err, os.ErrNotExist) || (err == nil && project != "" && session.ProjectID != project) {
				fallback := url.Values{"view": {"meetings"}}
				if project != "" {
					fallback.Set("project", project)
				}
				return "/research?" + fallback.Encode(), nil
			}
			if err == nil && project == "" && session.ProjectID != "" {
				if !service.HasActiveProject(session.ProjectID) {
					return "/research?view=projects", nil
				}
				q.Set("project", session.ProjectID)
				canonical := *link
				canonical.RawQuery = q.Encode()
				return canonical.RequestURI(), nil
			}
		}
	}
	return link.RequestURI(), nil
}

func libraryRoute(project string) string {
	if project == "" {
		return "/research?view=papers"
	}
	return "/research?view=papers&project=" + url.QueryEscape(project)
}

func routeModule(path, view, tab string) string {
	switch path {
	case "/reader":
		return "pdf-reader"
	case "/lab":
		return "ai-lab"
	case "/tools":
		if tab == "calendar" {
			return "calendar"
		}
		if tab == "convert" {
			return "paper-library"
		}
		return "recommendation"
	case "/research":
		if view == "tasks" && tab == "calendar" {
			return "calendar"
		}
		return map[string]string{"projects": "projects", "papers": "paper-library", "tasks": "tasks", "notes": "wiki", "graph": "citation-graph", "materials": "materials", "code": "code", "data": "datasets", "experiments": "experiments", "writing": "writing", "theory": "theory-notes"}[view]
	default:
		return ""
	}
}

// The URL is the per-window navigation state. Preserve only known workstation
// locators in the active root, so /resume can never open another host or an API.
func workspaceLocation(raw string) (*url.URL, error) {
	u, err := url.Parse(raw)
	if err != nil || u.IsAbs() || u.Host != "" || u.User != nil || u.RawPath != "" || len(raw) > 49152 {
		return nil, errors.New("invalid workspace route")
	}
	if u.Path == "/" {
		u.Path = "/research"
	}
	if _, ok := workspaceSurfaces[u.Path]; !ok {
		return nil, errors.New("unknown workspace route")
	}
	q := u.Query()
	for key := range q {
		switch key {
		case "project", "view", "session", "paper", "page", "annotation", "fingerprint", "quote", "start", "end", "ocr", "note", "task", "tab":
		default:
			q.Del(key)
		}
	}
	u.RawQuery = q.Encode()
	return u, nil
}

type workspaceNavigation struct {
	mu        sync.Mutex
	lastEvent float64 // Only compares browser events delivered during this process.
}

func (a *apiServer) navigationPath() string {
	return filepath.Join(filepath.Dir(a.prefs.file), "workspace-navigation.json")
}

func (a *apiServer) savedNavigation() (map[string]json.RawMessage, error) {
	data, err := os.ReadFile(a.navigationPath())
	if errors.Is(err, os.ErrNotExist) {
		return map[string]json.RawMessage{"version": json.RawMessage("1")}, nil
	}
	if err != nil {
		return nil, err
	}
	var record map[string]json.RawMessage
	if json.Unmarshal(data, &record) != nil || string(record["version"]) != "1" {
		return nil, errors.New("unknown or damaged workspace navigation")
	}
	if encoded, exists := record["route"]; exists {
		var raw string
		if json.Unmarshal(encoded, &raw) != nil {
			return nil, errors.New("damaged workspace route")
		}
		if _, err := workspaceLocation(raw); err != nil {
			return nil, err
		}
	}
	return record, nil
}

func (a *apiServer) serveNavigation(w http.ResponseWriter, r *http.Request) {
	if a.prefs == nil {
		reject(w, 503, "工作区不可用")
		return
	}
	a.navigation.mu.Lock()
	defer a.navigation.mu.Unlock()
	record, err := a.savedNavigation()
	if err != nil {
		if r.URL.Path == "/resume" && (r.Method == http.MethodGet || r.Method == http.MethodHead) {
			http.Redirect(w, r, "/research", http.StatusSeeOther)
			return
		}
		reject(w, 500, "无法读取已保存的工作区位置")
		return
	}
	if r.Method == http.MethodGet || r.Method == http.MethodHead {
		raw := "/research"
		if value, ok := record["route"]; ok && json.Unmarshal(value, &raw) != nil {
			reject(w, 500, "已保存的工作区位置无效")
			return
		}
		link, err := workspaceLocation(raw)
		if err != nil {
			reject(w, 500, "已保存的工作区位置无效")
			return
		}
		next, err := a.resolveWorkspaceRoute(link)
		if err != nil {
			reject(w, 500, "无法恢复工作区导航")
			return
		}
		if link.RequestURI() == next && link.Fragment != "" {
			next = link.String()
		}
		if r.URL.Path == "/resume" {
			http.Redirect(w, r, next, http.StatusSeeOther)
			return
		}
		reply(w, 200, map[string]string{"route": next})
		return
	}
	if r.Method != http.MethodPost || r.URL.Path == "/resume" {
		reject(w, 405, "不支持这个操作")
		return
	}
	var in struct {
		Route string  `json:"route"`
		Event float64 `json:"event"`
	}
	if !jsonBody(w, r, &in) {
		return
	}
	link, err := workspaceLocation(in.Route)
	if err != nil || in.Event <= 0 || math.IsInf(in.Event, 0) || math.IsNaN(in.Event) {
		reject(w, 400, "工作区位置无效")
		return
	}
	if in.Event > a.navigation.lastEvent {
		route, _ := json.Marshal(link.String())
		if string(record["route"]) != string(route) {
			record["route"] = route
			data, _ := json.Marshal(record)
			if err := atomicFile(a.navigationPath(), data); err != nil {
				reject(w, 500, "无法保存工作区位置")
				return
			}
		}
		a.navigation.lastEvent = in.Event
	}
	w.WriteHeader(http.StatusNoContent)
}
