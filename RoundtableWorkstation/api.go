package main

import (
	"embed"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"mime"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"

	"scistation.local/desktop/internal/cli"
	"scistation.local/desktop/internal/deliberation"
	"scistation.local/desktop/internal/meeting"
	"scistation.local/desktop/internal/plugins"
	"scistation.local/desktop/internal/sessionstore"
	"scistation.local/desktop/internal/workspace"
)

//go:embed static/*
var assets embed.FS

type apiServer struct {
	savePick      func(filename, extension string) (string, error)
	saveDialog    sync.Mutex
	plugins       *plugins.Store
	pluginErr     error
	desktop       bool
	diag          diagnosticStore
	prefs         *settingsStore
	meetings      *meeting.Engine
	research      http.Handler
	selectedPaths sync.Map
	pickMu        sync.RWMutex
	pick          func() (string, error)
}

func (a *apiServer) setPicker(p func() (string, error)) {
	a.pickMu.Lock()
	defer a.pickMu.Unlock()
	a.pick = p
}

func reply(w http.ResponseWriter, code int, value any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(value)
}

func reject(w http.ResponseWriter, code int, msg string) {
	reply(w, code, map[string]string{"error": msg})
}

func jsonBody(w http.ResponseWriter, r *http.Request, out any) bool {
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4<<20))
	dec.DisallowUnknownFields()
	if err := dec.Decode(out); err != nil {
		reject(w, 400, "请求内容格式有误或超出大小限制")
		return false
	}
	var extra any
	if dec.Decode(&extra) != io.EOF {
		reject(w, 400, "请求应包含一个 JSON 对象")
		return false
	}
	return true
}

func fail(w http.ResponseWriter, err error) {
	if replyUnreadableSession(w, err) {
		return
	}
	status := 400
	if errors.Is(err, errModelCatalog) {
		status = http.StatusBadGateway
	}
	if errors.Is(err, os.ErrNotExist) {
		status = 404
	}
	if errors.Is(err, meeting.ErrConflict) || errors.Is(err, workspace.ErrConflict) {
		status = 409
	}
	reject(w, status, err.Error())
}

func replyUnreadableSession(w http.ResponseWriter, err error) bool {
	var issue *sessionstore.Unreadable
	if !errors.As(err, &issue) {
		return false
	}
	reply(w, http.StatusUnprocessableEntity, map[string]any{"error": issue.Error(), "unreadable_session": issue})
	return true
}

func (a *apiServer) serve(port int) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		host := r.Host
		if host != fmt.Sprintf("127.0.0.1:%d", port) && host != fmt.Sprintf("localhost:%d", port) {
			reject(w, 403, "使用本机圆桌地址访问")
			return
		}
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Referrer-Policy", "no-referrer")
		stylePolicy := "style-src 'self'"
		if r.URL.Path == "/" || r.URL.Path == "/research" || r.URL.Path == "/reader" || r.URL.Path == "/static/research.html" || r.URL.Path == "/static/reader.html" {
			// KaTeX and the PDF reader position glyphs and marks dynamically.
			stylePolicy += " 'unsafe-inline'"
		}
		w.Header().Set("Content-Security-Policy", "default-src 'self'; script-src 'self'; "+stylePolicy+"; img-src 'self' data:; connect-src 'self'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'")
		if r.Method != "GET" && r.Method != "HEAD" {
			isResearch := strings.HasPrefix(r.URL.Path, "/api/research/")
			if r.Method != "POST" && !(isResearch && (r.Method == "PATCH" || r.Method == "PUT" || r.Method == "DELETE")) {
				reject(w, 405, "不支持这个操作")
				return
			}
			origin := r.Header.Get("Origin")
			contentType := strings.ToLower(strings.TrimSpace(strings.Split(r.Header.Get("Content-Type"), ";")[0]))
			expectedType := "application/json"
			if r.URL.Path == materialUploadPath || (isResearch && contentType == "multipart/form-data") {
				expectedType = "multipart/form-data"
			}
			if r.Header.Get("X-Roundtable") != "1" || (origin != "" && origin != "http://"+host) ||
				r.Header.Get("Sec-Fetch-Site") == "cross-site" ||
				(contentType != expectedType && !(isResearch && r.Method == "DELETE" && r.ContentLength == 0)) {
				reject(w, 403, "请从本机圆桌发起操作")
				return
			}
		}
		path := r.URL.Path
		switch {
		case path == "/api/health" && r.Method == "GET":
			reply(w, 200, map[string]any{"name": "sci-station", "version": 2, "desktop": "wails-v3"})
		case strings.HasPrefix(path, "/api/research/lab/"):
			a.serveAILab(w, r)
		case strings.HasPrefix(path, "/api/research/tools/"):
			a.serveScienceTools(w, r)
		case strings.HasPrefix(path, "/api/research/") && a.research != nil:
			a.research.ServeHTTP(w, r)
		case strings.HasPrefix(path, "/api/studio/"):
			a.studio(w, r)
		case strings.HasPrefix(path, "/api/"):
			http.NotFound(w, r)
		default:
			if r.Method != "GET" && r.Method != "HEAD" {
				reject(w, 405, "仅支持读取")
				return
			}
			switch path {
			case "/", "/research":
				path = "/static/research.html"
			case "/studio":
				path = "/static/studio.html"
			case "/lab":
				path = "/static/lab.html"
			case "/reader":
				path = "/static/reader.html"
			case "/tools":
				path = "/static/science-tools.html"
			case "/api-docs":
				path = "/static/api.html"
			case "/openapi.json":
				path = "/static/openapi.json"
			case "/favicon.ico":
				path = "/static/roundtable-mark.png"
			}
			if !strings.HasPrefix(path, "/static/") || !fs.ValidPath(strings.TrimPrefix(path, "/")) {
				http.NotFound(w, r)
				return
			}
			name := strings.TrimPrefix(path, "/")
			body, err := assets.ReadFile(name)
			if err != nil {
				http.NotFound(w, r)
				return
			}
			if kind := mime.TypeByExtension(filepath.Ext(name)); kind != "" {
				w.Header().Set("Content-Type", kind)
			}
			switch {
			case strings.HasSuffix(name, ".html"):
				w.Header().Set("Content-Type", "text/html; charset=utf-8")
			case strings.HasSuffix(name, ".js"):
				w.Header().Set("Content-Type", "text/javascript; charset=utf-8")
			case strings.HasSuffix(name, ".css"):
				w.Header().Set("Content-Type", "text/css; charset=utf-8")
			case strings.HasSuffix(name, ".png"):
				w.Header().Set("Content-Type", "image/png")
			case strings.HasSuffix(name, ".svg"):
				w.Header().Set("Content-Type", "image/svg+xml")
			case strings.HasSuffix(name, ".json"):
				w.Header().Set("Content-Type", "application/json; charset=utf-8")
			}
			w.WriteHeader(200)
			if r.Method != "HEAD" {
				_, _ = w.Write(body)
			}
		}
	})
}

func (a *apiServer) studio(w http.ResponseWriter, r *http.Request) {
	path := strings.TrimPrefix(r.URL.Path, "/api/studio/")
	if strings.HasPrefix(path, "materials/") {
		id := strings.TrimPrefix(path, "materials/")
		if materialID, match := strings.CutSuffix(id, "/save"); match {
			a.saveMaterial(w, r, materialID)
		} else {
			a.downloadMaterial(w, r, id)
		}
		return
	}
	switch path {
	case "materials":
		a.uploadMaterial(w, r)
		return
	case "plugins/save-output":
		a.savePluginOutput(w, r)
		return
	case "plugins":
		a.pluginMarket(w, r)
		return
	case "models":
		a.models(w, r)
		return
	case "magpie-agent":
		a.magpieAgent(w, r)
		return
	case "cli-health":
		a.cliHealth(w, r)
		return
	case "open-rules":
		a.openRules(w, r)
		return
	case "projects", "projects/import":
		a.projectsHandler(w, r)
		return
	case "projects/rules":
		a.projectRulesHandler(w, r)
		return
	}
	if path == "discussion-presets" {
		if r.Method != http.MethodGet {
			w.Header().Set("Allow", "GET")
			reject(w, http.StatusMethodNotAllowed, "讨论规则仅供读取")
			return
		}
		reply(w, http.StatusOK, map[string]any{"presets": deliberation.Catalog()})
		return
	}
	if path == "clients" {
		a.clients(w, r)
		return
	}
	if path == "diagnostics" {
		a.diagnostics(w, r)
		return
	}
	if path == "settings" {
		if r.Method == "POST" {
			var patch map[string]json.RawMessage
			if !jsonBody(w, r, &patch) {
				return
			}
			if err := a.prefs.update(patch); err != nil {
				fail(w, err)
				return
			}
		} else if r.Method != "GET" {
			reject(w, 405, "不支持这个操作")
			return
		}
		p := a.prefs.get()
		status := map[string]cli.Info{"codex": cli.Discover("codex", p.CLIPaths["codex"]), "cursor": cli.Discover("cursor", p.CLIPaths["cursor"])}
		reply(w, 200, struct {
			preferences
			Status map[string]cli.Info `json:"cli_status"`
		}{p, status})
		return
	}
	if path == "pick-project" && r.Method == "POST" {
		a.pickMu.RLock()
		pick := a.pick
		a.pickMu.RUnlock()
		if pick == nil {
			reject(w, 409, "当前在浏览器模式，请输入项目的绝对路径，也可打开 Mac App 选择文件夹。")
			return
		}
		selected, err := pick()
		if err != nil {
			fail(w, err)
			return
		}
		if selected != "" {
			a.selectedPaths.Store(filepath.Clean(selected), true)
		}
		reply(w, 200, map[string]string{"path": selected})
		return
	}
	if path == "sessions" {
		if r.Method == "GET" {
			list, unreadable, e := a.meetings.ListWithRecovery()
			if e != nil {
				reject(w, http.StatusInternalServerError, "无法访问圆桌存档目录，请检查目录和本机权限后重试。")
				return
			}
			reply(w, 200, map[string]any{"sessions": list, "unreadable_sessions": unreadable})
			return
		}
		if r.Method == "POST" {
			var b struct {
				Topic, Project string
				Seats          []string
				Members        []meeting.Member
				Preset         string
				Agenda         []json.RawMessage
				Continuous     *meeting.ContinuousConfig `json:"continuous"`
				MaterialIDs    []string                  `json:"material_ids"`
			}
			if !jsonBody(w, r, &b) {
				return
			}
			if err := meeting.ValidateTopic(b.Topic); err != nil {
				fail(w, err)
				return
			}
			if b.Members != nil && len(b.Seats) != 0 {
				reject(w, 400, "请仅使用本场圆桌的模型席位")
				return
			}
			dir, e := workspace.Validate(b.Project)
			if e != nil {
				fail(w, e)
				return
			}
			var s *meeting.Session
			if b.Members != nil {
				members, err := a.validateMembers(r.Context(), b.Members)
				if err != nil {
					fail(w, err)
					return
				}
				var items []meeting.AgendaInput
				for _, raw := range b.Agenda {
					var item meeting.AgendaInput
					if err := json.Unmarshal(raw, &item.Title); err != nil {
						if err := json.Unmarshal(raw, &item); err != nil {
							reject(w, 400, "议程项需要标题和类型")
							return
						}
					}
					items = append(items, item)
				}
				s, e = a.meetings.CreateConfiguredWithMaterials(b.Topic, dir, members, b.Preset, b.Continuous, b.MaterialIDs, items...)
			} else {
				if b.Preset != "" || len(b.Agenda) != 0 || b.Continuous != nil {
					reject(w, 400, "请先为新圆桌选择模型")
					return
				}
				s, e = a.meetings.CreateWithMaterials(b.Topic, dir, b.Seats, b.MaterialIDs)
			}
			if e != nil {
				fail(w, e)
				return
			}
			if b.Members != nil {
				// The session already exists even if the service is closing before a
				// draft can start. Returning its ID allows the host to reopen/retry.
				if started, err := a.meetings.StartAgendaDraft(s.ID, &s.AgendaVersion); err == nil {
					s = started
				}
			}
			reply(w, 201, s)
			return
		}
	}
	parts := strings.Split(path, "/")
	if len(parts) < 2 || len(parts) > 3 || parts[0] != "sessions" {
		reject(w, 404, "未找到接口")
		return
	}
	id := parts[1]
	if len(parts) == 3 && parts[2] == "plugin-action" {
		a.pluginAction(w, r, id)
		return
	}
	if len(parts) == 3 && (parts[2] == "report" || parts[2] == "report.md") {
		a.report(w, r, id, parts[2])
		return
	}
	if len(parts) == 3 && parts[2] == "board-presence" {
		a.boardPresence(w, r, id)
		return
	}
	if len(parts) == 3 && parts[2] == "board" {
		a.changeBoard(w, r, id)
		return
	}
	if len(parts) == 3 && parts[2] == "members" {
		a.sessionMembers(w, r, id)
		return
	}
	if len(parts) == 3 && parts[2] == "agenda" {
		a.agenda(w, r, id)
		return
	}
	if len(parts) == 3 && parts[2] == "title" {
		if r.Method != http.MethodPost {
			w.Header().Set("Allow", "POST")
			reject(w, http.StatusMethodNotAllowed, "请通过圆桌请求任务标题")
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
		title, err := a.meetings.GenerateTitle(r.Context(), id)
		if err != nil {
			if replyUnreadableSession(w, err) {
				return
			}
			switch {
			case errors.Is(err, os.ErrNotExist):
				reject(w, http.StatusNotFound, "未找到圆桌")
			case errors.Is(err, meeting.ErrConflict):
				reject(w, http.StatusConflict, "圆桌正在关闭，请稍后重试")
			default:
				reject(w, http.StatusBadGateway, "第一席暂未返回任务标题，可从会话菜单重试")
			}
			return
		}
		reply(w, http.StatusOK, map[string]string{"title": title})
		return
	}
	if len(parts) == 3 && parts[2] == "review" {
		a.review(w, r, id)
		return
	}
	if len(parts) == 2 && r.Method == http.MethodGet {
		requestTags := strings.Split(r.Header.Get("If-None-Match"), ",")
		session, revision, err := a.meetings.Snapshot(id, func(stamp string) bool {
			for _, tag := range requestTags {
				if strings.TrimPrefix(strings.TrimSpace(tag), "W/") == `"`+stamp+`"` {
					return true
				}
			}
			return false
		})
		if err != nil {
			fail(w, err)
			return
		}
		w.Header().Set("ETag", `W/"`+revision+`"`)
		if session == nil {
			w.WriteHeader(http.StatusNotModified)
		} else {
			reply(w, http.StatusOK, session)
		}
		return
	}
	s, e := a.meetings.Get(id)
	if e != nil {
		if errors.Is(e, os.ErrNotExist) {
			reject(w, http.StatusNotFound, "未找到圆桌")
		} else if !replyUnreadableSession(w, e) {
			reject(w, http.StatusInternalServerError, "无法读取圆桌存档，请检查本机存档后重试。")
		}
		return
	}
	if len(parts) != 3 {
		reject(w, 405, "不支持这个操作")
		return
	}
	route := r.Method + " " + parts[2]
	switch route {
	case "GET export.md":
		content, e := a.meetings.Markdown(id)
		if e != nil {
			fail(w, e)
			return
		}
		w.Header().Set("Content-Type", "text/markdown; charset=utf-8")
		w.Header().Set("Content-Disposition", fmt.Sprintf(`attachment; filename="meeting-%s.md"`, url.PathEscape(id)))
		_, _ = io.WriteString(w, content)
	case "GET files":
		files, e := workspace.Catalog(s.Project)
		if e != nil {
			fail(w, e)
			return
		}
		reply(w, 200, map[string]any{"files": files})
	case "GET file":
		file, e := workspace.Read(s.Project, r.URL.Query().Get("path"))
		if e != nil {
			fail(w, e)
			return
		}
		reply(w, 200, file)
	case "POST file":
		var b struct{ Path, Text, Version string }
		if !jsonBody(w, r, &b) {
			return
		}
		change, e := a.meetings.UserWrite(id, b.Path, b.Text, b.Version)
		if e != nil {
			fail(w, e)
			return
		}
		reply(w, 200, change)
	case "POST run":
		var b struct {
			Note, Target, Preset, Phase string
			Expected                    *int                      `json:"expected_round"`
			AgendaVersion               *int                      `json:"agenda_version"`
			AllowEdits                  *bool                     `json:"allow_edits"`
			Continuous                  *meeting.ContinuousConfig `json:"continuous"`
			MaterialIDs                 []string                  `json:"material_ids"`
		}
		if !jsonBody(w, r, &b) {
			return
		}
		if b.Expected == nil {
			reject(w, 400, "需要当前轮号")
			return
		}
		next, e := a.meetings.StartRound(id, b.Note, b.Target, *b.Expected, meeting.RoundOptions{
			Continuous: b.Continuous, Preset: b.Preset, Phase: b.Phase, AgendaVersion: b.AgendaVersion, AllowEdits: b.AllowEdits, MaterialIDs: b.MaterialIDs,
		})
		if e != nil {
			fail(w, e)
			return
		}
		reply(w, 202, next)
	case "POST cancel":
		next, e := a.meetings.Cancel(id)
		if e != nil {
			fail(w, e)
			return
		}
		reply(w, 202, next)
	default:
		reject(w, 404, "未找到接口")
	}
}

func (a *apiServer) approvedResearchPath(path string) bool {
	path = filepath.Clean(path)
	if _, ok := a.selectedPaths.Load(path); ok {
		return true
	}
	if a.prefs == nil {
		return false
	}
	records, err := a.projectRecords()
	_, ok := records[path]
	return err == nil && ok
}
