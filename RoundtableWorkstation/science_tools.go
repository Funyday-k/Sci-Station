package main

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"time"

	"scistation.local/desktop/internal/research"
)

type calendarItem struct {
	Title    string `json:"title"`
	Start    string `json:"start"`
	End      string `json:"end"`
	Calendar string `json:"calendar"`
}
type discoveryState struct {
	Query    string                   `json:"query"`
	Items    []research.PaperMetadata `json:"items"`
	Feedback map[string]string        `json:"feedback"`
	Updated  string                   `json:"updated"`
}

var discoveryMu sync.Mutex
var scientificHTTP = &http.Client{Timeout: 45 * time.Second, CheckRedirect: func(req *http.Request, via []*http.Request) error { return http.ErrUseLastResponse }}
var paperArxivID = regexp.MustCompile(`^(?:[a-z][a-zA-Z0-9.-]*/[0-9]{7}|[0-9]{4}\.[0-9]{4,5})(?:v[0-9]+)?$`)

func loadDiscovery(path string) (discoveryState, error) {
	s := discoveryState{Items: []research.PaperMetadata{}, Feedback: map[string]string{}}
	b, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return s, nil
	}
	if err != nil {
		return s, err
	}
	err = json.Unmarshal(b, &s)
	if s.Feedback == nil {
		s.Feedback = map[string]string{}
	}
	return s, err
}
func fetchScientificFeed(ctx context.Context, q string) ([]research.PaperMetadata, error) {
	if q == "" || len([]rune(q)) > 350 {
		return nil, errors.New("请输入 1–350 字的检索式")
	}
	if !strings.Contains(q, ":") {
		q = "all:\"" + strings.ReplaceAll(q, "\"", " ") + "\""
	}
	return research.SearchArxiv(ctx, q)
}
func (a *apiServer) serveScienceTools(w http.ResponseWriter, r *http.Request) {
	route := strings.TrimPrefix(r.URL.Path, "/api/research/tools/")
	lab, ok := a.research.(*research.Service)
	if !ok {
		reject(w, 503, "科研服务未启动")
		return
	}
	switch route {
	case "discover", "feedback":
		name := "discovery.json"
		if project := r.URL.Query().Get("project"); project != "" {
			if !lab.HasActiveProject(project) {
				reject(w, 404, "科研项目不存在或已归档")
				return
			}
			name = "discovery." + project + ".json"
		}
		file := filepath.Join(filepath.Dir(a.prefs.file), name)
		var input struct {
			Query string `json:"query"`
			Arxiv string `json:"arxiv"`
			State string `json:"state"`
		}
		var items []research.PaperMetadata
		if r.Method == http.MethodPost {
			if !jsonBody(w, r, &input) {
				return
			}
			if route == "discover" {
				input.Query = strings.TrimSpace(input.Query)
				var err error
				items, err = fetchScientificFeed(r.Context(), input.Query)
				if err != nil {
					reject(w, 502, err.Error())
					return
				}
			} else if !paperArxivID.MatchString(input.Arxiv) || (input.State != "" && input.State != "saved" && input.State != "hidden") {
				reject(w, 400, "无效的推荐反馈")
				return
			}
		} else if r.Method != http.MethodGet || route != "discover" {
			reject(w, 405, "不支持此请求")
			return
		}
		discoveryMu.Lock()
		defer discoveryMu.Unlock()
		s, err := loadDiscovery(file)
		if err != nil {
			reject(w, 500, "发现记录无法读取")
			return
		}
		if r.Method == http.MethodPost {
			if route == "discover" {
				s.Query = input.Query
				s.Items = items
				s.Updated = time.Now().UTC().Format(time.RFC3339)
			} else {
				key := research.ArxivWorkID(input.Arxiv)
				for id := range s.Feedback {
					if research.ArxivWorkID(id) == key {
						delete(s.Feedback, id)
					}
				}
				if input.State != "" {
					s.Feedback[key] = input.State
				}
			}
			b, err := json.Marshal(s)
			if err == nil {
				err = atomicFile(file, b)
			}
			if err != nil {
				reject(w, 500, "保存发现记录失败")
				return
			}
		}
		reply(w, 200, s)
	case "events", "reminder":
		if r.Method != "POST" {
			reject(w, 405, "请从科研工具发起")
			return
		}
		if !a.desktop {
			reject(w, 409, "请在 Sci-Station 桌面应用连接系统日历或提醒事项")
			return
		}
		if route == "events" {
			events, err := systemCalendarEvents()
			if err != nil {
				reject(w, 409, err.Error())
				return
			}
			reply(w, 200, events)
		} else {
			var input struct {
				Project string `json:"project"`
				Task    string `json:"task"`
			}
			if !jsonBody(w, r, &input) {
				return
			}
			task, exists := lab.Task(input.Project, input.Task)
			if !exists {
				reject(w, 404, "项目任务不存在")
				return
			}
			id, err := publishReminder(input.Project+"/"+input.Task, task.Title, task.Description, task.DueDate)
			if err != nil {
				reject(w, 409, err.Error())
				return
			}
			reply(w, 200, map[string]string{"id": id})
		}
	case "mineru/start", "mineru/status", "mineru/result":
		a.mineruTool(lab, w, r, route)
	default:
		http.NotFound(w, r)
	}
}
