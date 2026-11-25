package meeting

import (
	"context"
	"errors"
	"fmt"
	"os"
	"slices"
	"strings"
)

type MeetingReport struct {
	PluginGuidance []PluginGuidance `json:"plugin_guidance,omitempty"`
	Coverage       string           `json:"coverage,omitempty"`
	DraftText      string           `json:"draft_text,omitempty"`
	Status         string           `json:"status"`
	Attempt        int              `json:"attempt"`
	AuthorSeat     string           `json:"author_seat"`
	AuthorModel    string           `json:"author_model"`
	ReviewerSeat   string           `json:"reviewer_seat"`
	ReviewerModel  string           `json:"reviewer_model"`
	ReviewMode     string           `json:"review_mode"`
	SourceCount    int              `json:"source_count"`
	HasDraft       bool             `json:"has_draft"`
	Markdown       string           `json:"markdown"`
	ReviewNotes    string           `json:"review_notes,omitempty"`
	Error          string           `json:"error,omitempty"`
}

type ReportAction struct {
	Action        string `json:"action"`
	ExpectedRound *int   `json:"expected_round"`
	AgendaVersion *int   `json:"agenda_version"`
	Attempt       *int   `json:"attempt,omitempty"`
}

func (r *MeetingReport) active() bool {
	return r != nil && (r.Status == "drafting" || r.Status == "reviewing" || r.Status == "revising")
}

func (s *Session) requireOpen() error {
	if s.Status == "closed" || s.Report != nil {
		return fmt.Errorf("%w: 主持人已结束本场会议", ErrConflict)
	}
	return nil
}

func (e *Engine) recoverReport(s *Session) error {
	lease, err := e.lease(s.ID)
	if err != nil || lease == nil {
		return err
	}
	defer release(lease)
	failReport(s, "上次报告整理已中断，可从已保存的阶段重试。")
	return e.save(s)
}

func failReport(s *Session, message string) {
	s.Report.Status, s.Report.Error = "failed", message
	addEvent(s, "report_failed", "", message)
}

// Report actions never start or replay a discussion round. A retry identifies
// the failed attempt observed by the host, so a repeated POST cannot start a
// second worker even if the first retry has already failed again.
func (e *Engine) ChangeReport(id string, a ReportAction) (*Session, error) {
	if a.ExpectedRound == nil || a.AgendaVersion == nil || *a.ExpectedRound < 0 || *a.AgendaVersion < 0 {
		return nil, errors.New("请携带当前轮数和议程版本")
	}
	switch a.Action {
	case "finish":
		if a.Attempt != nil {
			return nil, errors.New("结束会议无需提供重试编号")
		}
	case "retry":
		if a.Attempt == nil || *a.Attempt < 1 {
			return nil, errors.New("请提供所见失败稿的编号")
		}
	default:
		return nil, errors.New("不支持这个报告操作")
	}
	var result *Session
	var ctx context.Context
	var stop context.CancelFunc
	var lease *os.File
	var settings Settings
	var material, projection reportMaterial
	var projectionErr error
	err := e.locked(func() error {
		s, err := e.load(id)
		if err != nil {
			return err
		}
		if err = e.recover(s); err != nil {
			return err
		}
		if s.Status == "running" || s.AgendaDraftStatus == "drafting" {
			return fmt.Errorf("%w: 请等当前轮次或议程起草结束", ErrConflict)
		}
		if len(s.Rounds) != *a.ExpectedRound || s.AgendaVersion != *a.AgendaVersion {
			return fmt.Errorf("%w: 会议记录已更新，请刷新后重试", ErrConflict)
		}
		if a.Action == "retry" {
			if s.Report == nil || *a.Attempt > s.Report.Attempt {
				return fmt.Errorf("%w: 没有对应的失败报告", ErrConflict)
			}
			if *a.Attempt < s.Report.Attempt || s.Report.Status != "failed" {
				result = s
				return nil
			}
		} else if s.Report != nil {
			result = s
			return nil
		}
		material = reportMaterials(s)
		count := 0
		for _, src := range material.Sources {
			if src.Kind == "public" {
				count++
			}
		}
		if count == 0 || len(s.Seats) == 0 {
			return fmt.Errorf("%w: 至少需要一条已完成的公开发言", ErrConflict)
		}
		settings, err = e.snapshotSettings(s)
		if err != nil {
			return err
		}
		// A legacy meeting's current app defaults can differ from the actual
		// seats recorded in its rounds. Retain those meeting-specific models.
		if len(s.Members) == 0 {
			configured := settings.Models
			settings.Models = map[string]string{}
			for _, round := range s.Rounds {
				for seat, model := range round.Settings.Models {
					if model != "" {
						settings.Models[seat] = model
					}
				}
				for _, turn := range round.Turns {
					if turn.Model != "" {
						settings.Models[turn.Seat] = turn.Model
					}
				}
			}
			for _, seat := range s.Seats {
				if s.memberForSeat(seat) != nil {
					settings.Models[seat] = configured[seat]
				}
			}
		}
		projection, projectionErr = material.forReportPrompt()
		if s.Report == nil {
			pluginGuidance, err := e.snapshotPluginGuidance(reportGuidance)
			if err != nil {
				return err
			}
			s.Report = newMeetingReport(s, settings, count)
			s.Report.PluginGuidance = pluginGuidance
			s.Status = "closed"
			s.Report.Coverage = projection.Coverage
			s.Report.Markdown = reportDocument(s, material, material.sourceDraft(), false)
			addEvent(s, "meeting_closed", "user", "主持人结束会议并请求整理报告。")
		}
		r := s.Report
		r.Coverage = projection.Coverage
		lease, err = e.lease(id)
		if err != nil {
			return err
		}
		if lease == nil {
			return fmt.Errorf("%w: 会议仍在运行", ErrConflict)
		}
		e.cancelMu.Lock()
		defer e.cancelMu.Unlock()
		if e.shuttingDown {
			release(lease)
			return fmt.Errorf("%w: 应用正在关闭", ErrConflict)
		}
		r.Attempt++
		r.Error = ""
		r.Status = "drafting"
		if r.HasDraft {
			r.Status = "reviewing"
		}
		if r.ReviewNotes != "" {
			r.Status = "revising"
		}
		addEvent(s, "report_started", r.AuthorSeat, fmt.Sprintf("正在整理报告（第 %d 次）。", r.Attempt))
		if err = e.save(s); err != nil {
			release(lease)
			return err
		}
		ctx, stop = context.WithCancel(context.Background())
		if e.reportCancels == nil {
			e.reportCancels = map[string]context.CancelFunc{}
		}
		e.reportCancels[id] = stop
		e.workers.Add(1)
		result = s
		return nil
	})
	if err != nil {
		return nil, err
	}
	if stop != nil {
		// Keep the worker separate from the caller without cloning private logs,
		// file snapshots or the entire round history.
		r := *result.Report
		r.PluginGuidance = slices.Clone(r.PluginGuidance)
		work := &Session{ID: result.ID, Title: result.Title, Topic: result.Topic, Report: &r}
		go e.runReport(ctx, stop, work, material, projection, projectionErr, settings, lease)
	}
	return result, nil
}

func modelIdentity(name string) string {
	parts := strings.Split(strings.ToLower(strings.TrimSpace(name)), "/")
	return parts[len(parts)-1]
}

func newMeetingReport(s *Session, settings Settings, count int) *MeetingReport {
	chair := s.Seats[0]
	for _, seat := range s.Seats {
		if settings.Models[seat] != "" {
			chair = seat
			break
		}
	}
	r := &MeetingReport{SourceCount: count, AuthorSeat: chair, AuthorModel: settings.Models[chair], ReviewMode: "self"}
	r.ReviewerSeat, r.ReviewerModel = r.AuthorSeat, r.AuthorModel
	for _, seat := range s.Seats {
		if seat == chair {
			continue
		}
		model := settings.Models[seat]
		if model == "" {
			continue
		}
		if r.ReviewMode == "self" {
			r.ReviewerSeat, r.ReviewerModel, r.ReviewMode = seat, model, "same_model"
		}
		if modelIdentity(model) != modelIdentity(r.AuthorModel) {
			r.ReviewerSeat, r.ReviewerModel, r.ReviewMode = seat, model, "peer"
			break
		}
	}
	return r
}

func reportDocument(s *Session, m reportMaterial, body string, ready bool) string {
	r := s.Report
	label := "草稿"
	if ready {
		label = "定稿"
	}
	title := strings.TrimSpace(s.Title)
	if title == "" {
		title = shorten(inlineReport(s.Topic), 100)
	}
	mode := map[string]string{"peer": "另一模型席位复核", "same_model": "另一席位使用同一模型复核", "self": "执笔席自审"}[r.ReviewMode]
	title = strings.TrimSuffix(inlineReport(title), "。")
	header := fmt.Sprintf("# %s · 会议报告（%s）\n\n", title, label)
	if r.Coverage != "" {
		header += r.Coverage + "\n\n"
	}
	var footer strings.Builder
	if ready {
		fmt.Fprintf(&footer, "\n## 报告整理\n\n执笔：%s（%s）。%s：%s（%s）。\n", m.seatName(r.AuthorSeat), r.AuthorModel, mode, m.seatName(r.ReviewerSeat), r.ReviewerModel)
	} else if len(r.PluginGuidance) > 0 {
		footer.WriteString("\n## 报告整理\n")
	}
	writePluginGuidanceNames(&footer, r.PluginGuidance)
	return header + body + "\n" + m.appendices() + footer.String()
}

func (e *Engine) runReport(ctx context.Context, stop context.CancelFunc, s *Session, m, projection reportMaterial, projectionErr error, settings Settings, lease *os.File) {
	defer e.workers.Done()
	defer stop()
	// Registration and the shared file lease stay live until the last write is
	// durable. Remove registration before releasing the lease for another retry.
	released := false
	cleanup := func() {
		if released {
			return
		}
		e.cancelMu.Lock()
		delete(e.reportCancels, s.ID)
		release(lease)
		released = true
		e.cancelMu.Unlock()
	}
	defer cleanup()
	workErr := projectionErr
	if workErr == nil {
		workErr = e.composeReport(ctx, s, m, projection, settings)
	}
	if workErr != nil {
		if ctx.Err() != nil {
			workErr = errors.New("报告整理已中断，可从已保存的阶段重试。")
		}
		err := e.locked(func() error {
			defer cleanup()
			cur, err := e.load(s.ID)
			if err != nil {
				return err
			}
			if !cur.Report.active() || cur.Report.Attempt != s.Report.Attempt {
				return nil
			}
			failReport(cur, workErr.Error())
			return e.save(cur)
		})
		if err != nil {
			e.cancelMu.Lock()
			e.backgroundErr = errors.Join(e.backgroundErr, err)
			e.cancelMu.Unlock()
		}
	}
}

func (e *Engine) advanceReport(ctx context.Context, s *Session, stage, markdown, draft, review string) error {
	return e.locked(func() error {
		if err := ctx.Err(); err != nil {
			return err
		}
		current, err := e.load(s.ID)
		if err != nil {
			return err
		}
		r := current.Report
		if !r.active() || r.Attempt != s.Report.Attempt {
			return ErrConflict
		}
		r.Status = stage
		if markdown != "" {
			r.HasDraft = true
			r.Markdown = markdown
		}
		if draft != "" {
			r.DraftText = draft
		}
		if review != "" {
			r.ReviewNotes = review
		}
		if stage == "ready" {
			r.DraftText = ""
			addEvent(current, "report_ready", r.AuthorSeat, "报告已完成复核和修订。")
		}
		if err = e.save(current); err != nil {
			return err
		}
		s.Report = r
		return nil
	})
}
