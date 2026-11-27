package desktop

import (
	"net/http"
	"strings"

	"scistation.local/desktop/internal/meeting"
)

func (a *apiServer) serveLabThreads(w http.ResponseWriter, r *http.Request, path string) {
	if a.meetings == nil {
		reject(w, 503, "未打开会话存档")
		return
	}
	lab := a.research
	if lab == nil {
		reject(w, 503, "未打开科研工作区")
		return
	}
	query := r.URL.Query()
	project, kind := query.Get("project"), query.Get("scope")
	var scope meeting.LabScope
	switch {
	case kind == "global" && project == "":
		scope.Global = true
		if !checkLabModule(w, lab, "") {
			return
		}
	case kind == "" && project != "":
		scope.ProjectID = project
		if !checkLabProject(w, lab, project) {
			return
		}
	default:
		reject(w, 400, "请选择科研项目或全局会话")
		return
	}
	if path == "draft" {
		var edit *meeting.LabDraft
		switch r.Method {
		case http.MethodGet:
		case http.MethodPut:
			var in struct {
				Text     *string `json:"text"`
				Revision *int    `json:"revision"`
			}
			if !jsonBody(w, r, &in) {
				return
			}
			if in.Text == nil || in.Revision == nil {
				reject(w, 400, "请提交草稿文本与当前版本")
				return
			}
			edit = &meeting.LabDraft{Text: *in.Text, Revision: *in.Revision}
		default:
			w.Header().Set("Allow", "GET, PUT")
			reject(w, 405, "请读取或保存草稿")
			return
		}
		draft, err := a.meetings.LabDraft(scope, query.Get("thread"), edit)
		if err != nil {
			fail(w, err)
			return
		}
		reply(w, 200, draft)
		return
	}

	if r.Method != http.MethodPatch {
		w.Header().Set("Allow", "PATCH")
		reject(w, 405, "请更新会话名称或归档状态")
		return
	}
	var change meeting.LabThreadChange
	if !jsonBody(w, r, &change) {
		return
	}
	room, err := a.meetings.ChangeLabThread(scope, strings.TrimPrefix(path, "threads/"), change)
	if err != nil {
		fail(w, err)
		return
	}
	reply(w, 200, room)
}
