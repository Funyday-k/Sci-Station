package main

import (
	"archive/zip"
	"bytes"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"mime"
	"net/http"
	"strings"
	"time"

	"scistation.local/desktop/internal/meeting"
)

type replayEvent struct {
	ID    int    `json:"id"`
	Kind  string `json:"kind"`
	At    string `json:"at,omitempty"`
	Round int    `json:"round,omitempty"`
	Step  int    `json:"step,omitempty"`
}

// Archive only fields assigned by the scheduler. Prompt text, provider output,
// material bytes, paths, model labels and provider configuration stay local.
func labReplayBundle(room *meeting.Session) ([]byte, error) {
	var buf bytes.Buffer
	archive := zip.NewWriter(&buf)
	events := make([]replayEvent, 0, len(room.Events))
	for _, e := range room.Events {
		var at string
		if timestamp, err := time.Parse(time.RFC3339Nano, e.At); err == nil {
			at = timestamp.UTC().Format(time.RFC3339Nano)
		}
		events = append(events, replayEvent{ID: e.ID, Kind: labEventKind(e.Type), At: at, Round: e.Round, Step: e.Step})
	}
	status := room.Status
	switch status {
	case "ready", "running", "partial", "closed":
	default:
		status = "unknown"
	}
	var paper, local int
	for _, m := range room.Materials {
		switch {
		case strings.HasPrefix(m.Excerpt, "Sci-Station · 论文原文摘录 v1\n"):
			paper++
		case strings.HasPrefix(m.Excerpt, "Sci-Station · 项目原文摘录 v1\n"):
			local++
		}
	}
	scope := "project"
	if room.ProjectID == "" {
		scope = "global"
	}
	provenance := map[string]any{"runtime": "roundtable-go", "scope": scope, "paper_excerpts": paper, "project_excerpts": local, "attachments": len(room.Materials)}
	files := []struct {
		name  string
		value any
	}{
		{"manifest.json", map[string]any{"schema_version": 1, "provenance": provenance, "included_files": []string{"replay.json", "checkpoint.json", "provenance.json"}}},
		{"replay.json", map[string]any{"schema_version": 1, "events": events}},
		{"checkpoint.json", map[string]any{"status": status, "rounds": len(room.Rounds), "cancel_requested": room.CancelRequested}},
		{"provenance.json", provenance},
	}
	for _, file := range files {
		f, err := archive.Create(file.name)
		if err != nil {
			return nil, err
		}
		if err = json.NewEncoder(f).Encode(file.value); err != nil {
			return nil, err
		}
	}
	if err := archive.Close(); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

func labEventKind(kind string) string {
	switch kind {
	case "created", "round_started", "round_finished", "seat_started", "seat_done", "seat_error", "child_started", "child_done", "child_error",
		"read", "action_error", "protocol_error", "cancel_requested", "shutdown_requested", "recovered", "meeting_closed",
		"seat_settings_changed", "continuous_paused", "continuous_completed", "continuous_summary", "report_started", "report_ready", "report_failed",
		"write_intent", "write", "write_failed", "write_outcome_unknown", "user_write_intent", "user_write", "user_write_failed":
		return kind
	}
	if strings.HasPrefix(kind, "agenda_") {
		return "agenda"
	}
	if strings.HasPrefix(kind, "board_") {
		return "board"
	}
	return "other"
}

func (a *apiServer) serveLabReplay(w http.ResponseWriter, r *http.Request, id string) {
	raw, err := hex.DecodeString(id)
	if err != nil || len(raw) != 16 || id != strings.ToLower(id) {
		http.NotFound(w, r)
		return
	}
	if r.Method != http.MethodGet && r.Method != http.MethodPost {
		w.Header().Set("Allow", "GET, POST")
		reject(w, 405, "请选择导出诊断记录")
		return
	}
	if a.meetings == nil {
		reject(w, 503, "未打开会话存档")
		return
	}
	if r.Method == http.MethodPost {
		var in *struct{}
		if !jsonBody(w, r, &in) {
			return
		}
		if in == nil {
			reject(w, 400, "请提交空对象")
			return
		}
	}
	room, err := a.meetings.Get(id)
	if err != nil {
		if !replyUnreadableSession(w, err) {
			reject(w, 404, "未找到会话")
		}
		return
	}
	project, scope := r.URL.Query().Get("project"), r.URL.Query().Get("scope")
	global := scope == "global" && project == "" && room.ProjectID == "" && room.Project == ""
	if len(room.Seats) != 1 || (!global && (scope != "" || project == "" || project != room.ProjectID)) {
		reject(w, 404, "未找到所选范围内的单席会话")
		return
	}
	data, err := labReplayBundle(room)
	if err != nil {
		reject(w, 500, "无法生成诊断包")
		return
	}
	name := fmt.Sprintf("sci-station-run-%s.zip", room.ID)
	if r.Method == http.MethodPost {
		a.saveLocalDownload(w, r, name, bytes.NewReader(data))
		return
	}
	w.Header().Set("Content-Type", "application/zip")
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("Content-Disposition", mime.FormatMediaType("attachment", map[string]string{"filename": name}))
	w.Write(data)
}
