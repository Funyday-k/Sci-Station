package desktop

import (
	"errors"
	"net/http"
	"strconv"

	"scistation.local/desktop/internal/meeting"
)

func (a *apiServer) changeBoard(w http.ResponseWriter, r *http.Request, id string) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", "POST")
		reject(w, http.StatusMethodNotAllowed, "请通过 POST 保存议题板")
		return
	}
	var change meeting.HostBoardChange
	if !jsonBody(w, r, &change) {
		return
	}
	s, err := a.meetings.ChangeBoard(id, change)
	if errors.Is(err, meeting.ErrConflict) && s != nil {
		reply(w, http.StatusConflict, map[string]any{"error": err.Error(), "session": s})
		return
	}
	if err != nil {
		fail(w, err)
		return
	}
	reply(w, http.StatusOK, s)
}

func (a *apiServer) boardPresence(w http.ResponseWriter, r *http.Request, id string) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", "GET")
		reject(w, http.StatusMethodNotAllowed, "请通过 GET 查看议题板光标")
		return
	}
	var after *uint64
	if raw, found := r.URL.Query()["after"]; found {
		if len(raw) != 1 {
			reject(w, http.StatusBadRequest, "请提供有效的光标版本")
			return
		}
		seq, err := strconv.ParseUint(raw[0], 10, 64)
		if err != nil {
			reject(w, http.StatusBadRequest, "请提供有效的光标版本")
			return
		}
		after = &seq
	}
	view, err := a.meetings.BoardPresence(r.Context(), id, after)
	if err != nil {
		if r.Context().Err() == nil {
			fail(w, err)
		}
		return
	}
	reply(w, http.StatusOK, view)
}
