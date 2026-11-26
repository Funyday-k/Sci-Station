package desktop

import (
	"crypto/subtle"
	"net/http"
)

func (a *apiServer) serveReadReview(w http.ResponseWriter, r *http.Request, session string) {
	pending := a.meetings.PendingReadReview(session)
	external := pending != nil && pending.Action == "research_read"
	desktop := a.desktop && a.minerCreds != nil && a.minerCreds.reviewProof != "" && subtle.ConstantTimeCompare([]byte(a.minerCreds.reviewProof), []byte(r.Header.Get("X-Sci-Station-Connector-Review"))) == 1
	w.Header().Set("Cache-Control", "no-store")
	switch r.Method {
	case http.MethodGet:
		if external && !desktop {
			reply(w, 200, nil)
			return
		}
		reply(w, 200, pending)
	case http.MethodPost:
		var body struct {
			ProjectID string `json:"project_id,omitempty"`
			ID        string `json:"id"`
			Action    string `json:"action"`
		}
		if !jsonBody(w, r, &body) {
			return
		}
		if body.ID == "" || (body.Action != "allow" && body.Action != "deny") {
			reject(w, 400, "请选择一次性允许或拒绝读取")
			return
		}
		if pending == nil || pending.ID != body.ID {
			reject(w, 409, "此读取请求已结束")
			return
		}
		if external && (!desktop || body.ProjectID == "" || body.ProjectID != pending.ProjectID) {
			reject(w, 403, "请在当前项目的桌面审批页复核科研请求")
			return
		}
		if err := a.meetings.DecideReadReview(session, body.ID, body.Action == "allow"); err != nil {
			fail(w, err)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	default:
		reject(w, 405, "不支持此请求")
	}
}
