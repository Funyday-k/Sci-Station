package main

import "net/http"

func (a *apiServer) serveReadReview(w http.ResponseWriter, r *http.Request, session string) {
	switch r.Method {
	case http.MethodGet:
		reply(w, 200, a.meetings.PendingReadReview(session))
	case http.MethodPost:
		var body struct {
			ID     string `json:"id"`
			Action string `json:"action"`
		}
		if !jsonBody(w, r, &body) {
			return
		}
		if body.ID == "" || (body.Action != "allow" && body.Action != "deny") {
			reject(w, 400, "请选择一次性允许或拒绝读取")
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
