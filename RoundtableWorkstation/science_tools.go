package main

import (
	"net/http"
	"strings"
	"time"

	"scistation.local/desktop/internal/research"
)

type calendarItem struct {
	Title    string `json:"title"`
	Start    string `json:"start"`
	End      string `json:"end"`
	Calendar string `json:"calendar"`
}

var scientificHTTP = &http.Client{Timeout: 45 * time.Second, CheckRedirect: func(req *http.Request, via []*http.Request) error { return http.ErrUseLastResponse }}

func (a *apiServer) serveScienceTools(w http.ResponseWriter, r *http.Request) {
	route := strings.TrimPrefix(r.URL.Path, "/api/research/tools/")
	lab, ok := a.research.(*research.Service)
	if !ok {
		reject(w, 503, "科研服务未启动")
		return
	}
	switch route {
	case "discover", "feedback", "archive-discovery", "select-discovery":
		a.serveDiscovery(lab, w, r, route)
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
			due := task.DueDate
			if task.DueTime != "" {
				due += "T" + task.DueTime
			}
			id, err := publishReminder(task.ProjectID+"/"+task.ID, task.Title, task.Description, due)
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
