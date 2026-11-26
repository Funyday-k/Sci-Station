package desktop

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"

	"scistation.local/desktop/internal/meeting"
	"scistation.local/desktop/internal/plugins"
)

// Only method and editorial contributions enter the model's context. The
// executable module stays in the market store until a user invokes an action.
func (a *apiServer) pluginGuidance() ([]meeting.PluginGuidance, error) {
	enabled, err := a.plugins.EnabledGuidance()
	if err != nil {
		return nil, err
	}
	var result []meeting.PluginGuidance
	for _, p := range enabled {
		c := p.Contributions
		if c.RoundGuidance != "" || c.ReportGuidance != "" {
			result = append(result, meeting.PluginGuidance{ID: p.ID, Name: p.Name, Version: p.Version, RoundGuidance: c.RoundGuidance, ReportGuidance: c.ReportGuidance})
		}
	}
	return result, nil
}

func (a *apiServer) pluginMarketReady(w http.ResponseWriter) bool {
	if a.pluginErr != nil {
		reject(w, http.StatusServiceUnavailable, "插件已暂停，可继续使用圆桌。检查插件目录后重开应用："+a.pluginErr.Error())
		return false
	}
	if a.plugins == nil {
		reject(w, http.StatusServiceUnavailable, "插件市场尚未就绪")
		return false
	}
	return true
}

func (a *apiServer) pluginMarket(w http.ResponseWriter, r *http.Request) {
	if !a.pluginMarketReady(w) {
		return
	}
	switch r.Method {
	case http.MethodGet:
	case http.MethodPost:
		var req struct {
			Action   string   `json:"action"`
			URL      string   `json:"url"`
			SourceID string   `json:"source_id"`
			ID       string   `json:"id"`
			SHA256   string   `json:"sha256"`
			Grants   []string `json:"grants"`
			Version  string   `json:"version"`
		}
		if !jsonBody(w, r, &req) {
			return
		}
		var err error
		switch req.Action {
		case "subscribe":
			err = a.plugins.AddSource(r.Context(), req.URL)
		case "refresh":
			err = a.plugins.Refresh(r.Context(), req.SourceID)
		case "unsubscribe":
			err = a.plugins.RemoveSource(req.SourceID)
		case "install":
			err = a.plugins.Install(r.Context(), req.SourceID, req.ID, req.SHA256, req.Grants, req.Version)
		case "enable", "disable":
			err = a.plugins.SetEnabled(req.ID, req.SourceID, req.Version, req.SHA256, req.Action == "enable")
		case "uninstall":
			err = a.plugins.Uninstall(req.ID, req.SourceID, req.Version, req.SHA256)
		default:
			err = errors.New("未知的市场操作")
		}
		if err != nil {
			fail(w, err)
			return
		}
	default:
		w.Header().Set("Allow", "GET, POST")
		reject(w, http.StatusMethodNotAllowed, "市场支持 GET 和 POST")
		return
	}
	view, err := a.plugins.View()
	if err != nil {
		fail(w, err)
		return
	}
	reply(w, http.StatusOK, view)
}

type pluginActionRequest struct {
	PluginID  string `json:"plugin_id"`
	ActionID  string `json:"action_id"`
	Version   string `json:"version"`
	SourceID  string `json:"source_id"`
	SHA256    string `json:"sha256"`
	FromRound *int   `json:"from_round,omitempty"`
	ToRound   *int   `json:"to_round,omitempty"`
}

type pluginPublicTurn struct {
	Round    int    `json:"round"`
	Seat     string `json:"seat"`
	SeatName string `json:"seat_name"`
	Model    string `json:"model"`
	Text     string `json:"text"`
}

// Keep this projection explicit. Session also contains private child tasks,
// project paths, file bodies, settings and raw tool events.
func pluginInput(s *meeting.Session, action plugins.Action, req pluginActionRequest) ([]byte, error) {
	data := map[string]any{"action": action.ID, "topic": s.Topic}
	switch action.Input {
	case "report":
		if req.FromRound != nil || req.ToRound != nil {
			return nil, errors.New("报告工具不接受轮次范围")
		}
		if s.Report == nil || s.Report.Status != "ready" {
			return nil, fmt.Errorf("%w: 请等待会议报告定稿", meeting.ErrConflict)
		}
		if len(s.Report.Markdown) > plugins.MaxInputBytes {
			return nil, errors.New("定稿超过该工具可接收的 256 KiB，请使用会议报告下载")
		}
		data["report"] = s.Report.Markdown
	case "public_turns":
		// Mirror the published statements shown in the discussion and report
		// UI. The current round stays private until all its seats settle.
		last := len(s.Rounds)
		if s.Status == "running" && last > 0 {
			last--
		}
		from, to := 1, last
		if req.FromRound != nil {
			from = *req.FromRound
		}
		if req.ToRound != nil {
			to = *req.ToRound
		}
		if (req.FromRound != nil || req.ToRound != nil) && (from < 1 || to < from || to > last) {
			return nil, fmt.Errorf("所选轮次须在已公开的第 1 至 %d 轮内", last)
		}
		names := s.SeatNames()
		turns := make([]pluginPublicTurn, 0)
		rawSize := len(s.Topic)
		for _, round := range s.Rounds[:last] {
			if round.Number < from || round.Number > to {
				continue
			}
			for _, turn := range round.Turns {
				if turn.Status != "done" || strings.TrimSpace(turn.Text) == "" {
					continue
				}
				model := round.RecordedTurnModel(turn)
				name := s.HistoricalSeatName(turn.Seat, model, turn.ModelLabel, names)
				rawSize += len(turn.Text) + len(turn.Seat) + len(name) + len(model) + 32
				if rawSize > plugins.MaxInputBytes {
					return nil, errors.New("公开发言超过工具的 256 KiB 容量，请缩小轮次范围")
				}
				turns = append(turns, pluginPublicTurn{Round: round.Number, Seat: turn.Seat, SeatName: name, Model: model, Text: turn.Text})
			}
		}
		data["turns"] = turns
	default:
		return nil, errors.New("此版本无法提供该插件所需的数据")
	}
	encoded, err := json.Marshal(data)
	if err == nil && len(encoded) > plugins.MaxInputBytes {
		return nil, errors.New("插件输入超过 256 KiB，公开发言工具可选择较短的轮次范围")
	}
	return encoded, err
}

func (a *apiServer) pluginAction(w http.ResponseWriter, r *http.Request, sessionID string) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", "POST")
		reject(w, http.StatusMethodNotAllowed, "请通过会议工具运行插件")
		return
	}
	var req pluginActionRequest
	if !jsonBody(w, r, &req) {
		return
	}
	if !a.pluginMarketReady(w) {
		return
	}
	p, err := a.plugins.ActionPlugin(req.PluginID, req.SourceID, req.Version, req.SHA256)
	if err != nil {
		fail(w, err)
		return
	}
	for _, action := range p.Contributions.Actions {
		if action.ID != req.ActionID {
			continue
		}
		session, err := a.meetings.Get(sessionID)
		if err != nil {
			fail(w, err)
			return
		}
		input, err := pluginInput(session, action, req)
		if err != nil {
			fail(w, err)
			return
		}
		output, err := plugins.Run(r.Context(), p.Module, input)
		if err != nil {
			fail(w, fmt.Errorf("插件运行失败：%w", err))
			return
		}
		ext := "txt"
		if action.Format == "markdown" {
			ext = "md"
		}
		reply(w, http.StatusOK, map[string]any{"native_save": a.savePicker() != nil, "format": action.Format, "text": output, "filename": fmt.Sprintf("%s-%s-%s.%s", session.ID, p.ID, action.ID, ext)})
		return
	}
	reject(w, http.StatusNotFound, "当前插件版本没有这个工具")
}
