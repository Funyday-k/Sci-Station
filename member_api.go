package main

import (
	"errors"
	"net/http"

	"scistation.local/desktop/internal/meeting"
)

func (a *apiServer) sessionMembers(w http.ResponseWriter, r *http.Request, id string) {
	switch r.Method {
	case http.MethodGet:
		members, err := a.meetings.SessionMembers(id)
		if err != nil {
			fail(w, err)
			return
		}
		reply(w, http.StatusOK, map[string]any{"members": members})
	case http.MethodPost:
		var change meeting.MemberChange
		if !jsonBody(w, r, &change) {
			return
		}
		s, err := a.meetings.ChangeMember(id, change, func() (meeting.Member, error) {
			list, err := a.validateMembers(r.Context(), []meeting.Member{{Model: change.Model, Effort: change.Effort}})
			if err != nil {
				return meeting.Member{}, err
			}
			return list[0], nil
		})
		if errors.Is(err, meeting.ErrConflict) && s != nil {
			reply(w, http.StatusConflict, map[string]any{"error": err.Error(), "session": s})
			return
		}
		if err != nil {
			fail(w, err)
			return
		}
		reply(w, http.StatusOK, s)
	default:
		w.Header().Set("Allow", "GET, POST")
		reject(w, http.StatusMethodNotAllowed, "请通过 GET 查看席位，或通过 POST 更改席位设置")
	}
}
