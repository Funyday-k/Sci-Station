package main

import (
	"net/http"

	"scistation.local/desktop/internal/meeting"
)

func (a *apiServer) agenda(w http.ResponseWriter, r *http.Request, id string) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", "POST")
		reject(w, http.StatusMethodNotAllowed, "请通过 POST 更新议程")
		return
	}
	var change meeting.AgendaChange
	if !jsonBody(w, r, &change) {
		return
	}
	if change.Action == "draft" {
		session, err := a.meetings.StartAgendaDraft(id, change.ExpectedVersion)
		if err != nil {
			fail(w, err)
			return
		}
		reply(w, http.StatusAccepted, session)
		return
	}
	session, err := a.meetings.ChangeAgenda(id, change)
	if err != nil {
		fail(w, err)
		return
	}
	reply(w, http.StatusOK, session)
}
