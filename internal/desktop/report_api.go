package desktop

import (
	"fmt"
	"io"
	"net/http"

	"scistation.local/desktop/internal/meeting"
)

func (a *apiServer) report(w http.ResponseWriter, r *http.Request, id, route string) {
	if route == "report.md" {
		if r.Method != http.MethodGet {
			w.Header().Set("Allow", "GET")
			reject(w, http.StatusMethodNotAllowed, "报告下载仅支持 GET")
			return
		}
		s, err := a.meetings.Get(id)
		if err != nil {
			fail(w, err)
			return
		}
		if s.Report == nil {
			reject(w, http.StatusConflict, "主持人尚未结束会议")
			return
		}
		w.Header().Set("Content-Type", "text/markdown; charset=utf-8")
		w.Header().Set("Content-Disposition", fmt.Sprintf(`attachment; filename="report-%s.md"`, s.ID))
		_, _ = io.WriteString(w, s.Report.Markdown)
		return
	}
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", "POST")
		reject(w, http.StatusMethodNotAllowed, "请通过 POST 结束会议或重试报告")
		return
	}
	var action meeting.ReportAction
	if !jsonBody(w, r, &action) {
		return
	}
	s, err := a.meetings.ChangeReport(id, action)
	if err != nil {
		fail(w, err)
		return
	}
	code := http.StatusAccepted
	if s.Report.Status == "failed" || s.Report.Status == "ready" {
		code = http.StatusOK
	}
	reply(w, code, s)
}
