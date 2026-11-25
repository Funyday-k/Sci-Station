package main

import (
	"net/http"
	"strings"
	"time"

	"scistation.local/desktop/internal/research"
)

type calendarItem struct {
	ID         string `json:"id,omitempty"`
	Kind       string `json:"kind,omitempty"`
	Title      string `json:"title"`
	Start      string `json:"start"`
	End        string `json:"end,omitempty"`
	Calendar   string `json:"calendar"`
	CalendarID string `json:"calendarId,omitempty"`
	HasTime    bool   `json:"hasTime,omitempty"`
	Marker     string `json:"marker,omitempty"`
	Notes      string `json:"notes,omitempty"`
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
	case "discover", "feedback", "archive-discovery", "select-discovery", "discovery-defaults":
		a.serveDiscovery(lab, w, r, route)
	case "events", "schedule", "reminder", "reminder-sync", "reminder-settings":
		a.serveCalendarTools(lab, w, r, route)
	case "mineru/credential":
		a.minerCredential(w, r)
	case "mineru/start", "mineru/status", "mineru/result":
		a.mineruTool(lab, w, r, route)
	default:
		http.NotFound(w, r)
	}
}
