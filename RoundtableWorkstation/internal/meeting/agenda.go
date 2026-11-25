package meeting

import (
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"unicode/utf8"

	"scistation.local/desktop/internal/deliberation"
)

const (
	maxAgendaItems   = 96
	maxAgendaTitle   = 240
	maxFollowups     = 3
	maxContextAgenda = 24
)

// AgendaInput is also the optional follow-up format for a synthesis statement.
type AgendaInput struct {
	Title string `json:"title"`
	Kind  string `json:"kind"`
}

type AgendaItem struct {
	SourceModel       string `json:"source_model,omitempty"`
	SourceModelLabel  string `json:"source_model_label,omitempty"`
	SourceModelSource string `json:"source_model_source,omitempty"`
	EditedBy          string `json:"edited_by,omitempty"`
	Version           int    `json:"version,omitempty"`
	AgendaInput
	ID          string            `json:"id"`
	Status      string            `json:"status"`
	Source      string            `json:"source"`
	SourceRound int               `json:"source_round,omitempty"`
	SourceSeat  string            `json:"source_seat,omitempty"`
	Reason      string            `json:"reason,omitempty"`
	Revisions   []AgendaRevision  `json:"revisions,omitempty"`
	Candidates  []AgendaCandidate `json:"candidates,omitempty"`
	Preset      string            `json:"preset,omitempty"`
	Phase       string            `json:"phase,omitempty"`
}

// AgendaCandidate preserves a valid same-round revision that lost to another
// seat's revision of the same item. The host can adopt or dismiss it later.
type AgendaCandidate struct {
	ID string `json:"id"`
	AgendaInput
	Round         int    `json:"round"`
	Seat          string `json:"seat"`
	Reason        string `json:"reason"`
	PreviousTitle string `json:"previous_title"`
	PreviousKind  string `json:"previous_kind"`
}

type AgendaChange struct {
	Action      string `json:"action"`
	ItemID      string `json:"item_id,omitempty"`
	CandidateID string `json:"candidate_id,omitempty"`
	AgendaInput
	ExpectedVersion *int `json:"expected_version"`
}

func defaultKind(preset string) string {
	if preset == "work" || preset == "" {
		return "implementation"
	}
	return "discussion"
}

func cleanAgendaInput(input AgendaInput, fallback string) (AgendaInput, error) {
	input.Title = strings.Join(strings.Fields(input.Title), " ")
	if input.Title == "" || utf8.RuneCountInString(input.Title) > maxAgendaTitle {
		return input, fmt.Errorf("议程标题须为 1 至 %d 个字符", maxAgendaTitle)
	}
	if input.Kind == "" {
		input.Kind = fallback
	}
	if input.Kind != "discussion" && input.Kind != "implementation" {
		return input, errors.New("请选择讨论或实施")
	}
	return input, nil
}

func (s *Session) findAgenda(id string) *AgendaItem {
	for i := range s.Agenda {
		if s.Agenda[i].ID == id {
			return &s.Agenda[i]
		}
	}
	return nil
}

func (s *Session) appendAgenda(item AgendaItem) error {
	for _, old := range s.Agenda {
		if strings.EqualFold(old.Title, item.Title) {
			return errors.New("议程中已有同名事项")
		}
	}
	if len(s.Agenda) >= maxAgendaItems {
		return fmt.Errorf("每场会议最多保存 %d 项议程", maxAgendaItems)
	}
	item.ID, item.Status = newID(), "pending"
	s.Agenda = append(s.Agenda, item)
	if s.AgendaDraftStatus != "drafting" {
		s.Board.revealPreset("agenda")
	}
	return nil
}

// InitAgenda is called before creation's single save. Old saved meetings can
// acquire their first item through ChangeAgenda without a migration.
func InitAgenda(s *Session, preset string, inputs []AgendaInput) error {
	plan, err := deliberation.Resolve(preset, "")
	if err != nil {
		return err
	}
	if len(inputs) > 24 {
		return errors.New("新建议程最多 24 项")
	}
	if len(inputs) > 0 {
		for _, input := range inputs {
			clean, err := cleanAgendaInput(input, defaultKind(plan.Preset))
			if err != nil {
				return err
			}
			if err = s.appendAgenda(AgendaItem{AgendaInput: clean, Source: "host"}); err != nil {
				return err
			}
		}
		s.ActiveAgendaID = s.Agenda[0].ID
	}
	s.Preset = plan.Preset
	s.AgendaVersion = 1
	if len(s.Members) > 0 {
		s.AgendaDraftStatus = "pending"
	}

	return nil
}

func (e *Engine) ChangeAgenda(id string, change AgendaChange) (*Session, error) {
	if change.ExpectedVersion == nil {
		return nil, errors.New("请携带当前议程版本")
	}
	var result *Session
	err := e.locked(func() error {
		s, err := e.load(id)
		if err != nil {
			return err
		}
		if err = e.recover(s); err != nil {
			return err
		}
		if err = s.requireOpen(); err != nil {
			return err
		}
		if s.AgendaDraftStatus == "drafting" {
			return fmt.Errorf("%w: 首席正在起草议程", ErrConflict)
		}
		if s.Status == "running" {
			return fmt.Errorf("%w: 本轮运行中，结束后可调整议程", ErrConflict)
		}
		if *change.ExpectedVersion != s.AgendaVersion {
			return fmt.Errorf("%w: 议程已更新，请刷新后再操作", ErrConflict)
		}
		var item *AgendaItem
		if change.Action == "add" {
			input, err := cleanAgendaInput(change.AgendaInput, defaultKind(s.Preset))
			if err != nil {
				return err
			}
			if err = s.appendAgenda(AgendaItem{AgendaInput: input, Source: "host"}); err != nil {
				return err
			}
			item = &s.Agenda[len(s.Agenda)-1]
			if s.ActiveAgendaID == "" {
				s.ActiveAgendaID = item.ID
			}
		} else {
			item = s.findAgenda(change.ItemID)
			if item == nil {
				return errors.New("未找到这项议程")
			}
			switch change.Action {
			case "adopt_candidate", "dismiss_candidate":
				if item.Status == "done" {
					return errors.New("请先恢复已完成的事项")
				}
				index := -1
				var candidate AgendaCandidate
				for i, proposed := range item.Candidates {
					if proposed.ID == change.CandidateID {
						index, candidate = i, proposed
						break
					}
				}
				if index < 0 || change.CandidateID == "" {
					return errors.New("未找到这项议程修订候选")
				}
				if change.Action == "adopt_candidate" {
					for _, other := range s.Agenda {
						if other.ID != item.ID && strings.EqualFold(other.Title, candidate.Title) {
							return errors.New("候选标题与其他议程重复")
						}
					}
					item.Revisions = append(item.Revisions, AgendaRevision{candidate.Round, candidate.Seat, item.Title, item.Kind, candidate.Reason})
					item.AgendaInput = candidate.AgendaInput
					item.EditedBy = candidate.Seat
					item.Version++
				}
				item.Candidates = append(item.Candidates[:index], item.Candidates[index+1:]...)
			case "select":
				if item.Status == "done" {
					return errors.New("请先恢复已完成的事项")
				}
				kind := change.Kind
				if kind == "" {
					kind = item.Kind
				}
				if kind != "discussion" && kind != "implementation" {
					return errors.New("请选择讨论或实施")
				}
				if s.ActiveAgendaID == item.ID && item.Kind == kind {
					result = clone(s)
					return nil
				}
				s.ActiveAgendaID, item.Kind = item.ID, kind
			case "complete":
				if item.Status == "done" {
					return errors.New("这项议程已完成")
				}
				item.Status = "done"
				if s.ActiveAgendaID == item.ID {
					s.ActiveAgendaID = ""
				}
			case "reopen":
				if item.Status != "done" {
					return errors.New("这项议程尚未完成")
				}
				item.Status = "pending"
				if s.ActiveAgendaID == "" {
					s.ActiveAgendaID = item.ID
				}
			default:
				return errors.New("不支持这个议程操作")
			}
		}
		s.AgendaVersion++
		s.Board.revealPreset("agenda")
		addEvent(s, "agenda_"+change.Action, "user", item.Title)
		if err = e.save(s); err != nil {
			return err
		}
		result = clone(s)
		return nil
	})
	return result, err
}

const agendaInstructions = "The active_agenda item is the current focus. Treat other open_agenda items as queued context for later rounds. Act only on the user's current request within this round's permissions."

const synthesisFollowupInstructions = `In your closing say, identify up to three priority follow-ups grounded in this meeting's public evidence or verified project observations. Explain the basis in the public text. If there are useful next steps, also include "followups":[{"title":"specific next step","kind":"discussion"}] in that same say object. Choose kind "discussion" for an unresolved question or "implementation" for work the host may choose to start. Avoid duplicates of the agenda, do not invent work, and omit followups when none are justified. These are proposals for the host to choose; they do not start work.`

type agendaBrief struct {
	ID string `json:"id"`
	AgendaInput
}

func openAgenda(s *Session) []agendaBrief {
	out := []agendaBrief{}
	for _, item := range s.Agenda {
		if item.Status != "done" && item.ID != s.ActiveAgendaID {
			out = append(out, agendaBrief{item.ID, item.AgendaInput})
			if len(out) == maxContextAgenda {
				break
			}
		}
	}
	return out
}

func eligibleFollowups(s *Session, raw json.RawMessage) []AgendaInput {
	// An unusable optional suggestion must not discard a valid public
	// statement, trigger correction calls, or suppress other valid suggestions.
	var inputs []json.RawMessage
	if json.Unmarshal(raw, &inputs) != nil {
		return nil
	}
	var out []AgendaInput
	seen := make(map[string]bool, len(s.Agenda))
	for _, item := range s.Agenda {
		seen[strings.ToLower(item.Title)] = true
	}
	for _, encoded := range inputs {
		var input AgendaInput
		if json.Unmarshal(encoded, &input) != nil {
			continue
		}
		input, err := cleanAgendaInput(input, "")
		if err != nil || seen[strings.ToLower(input.Title)] {
			continue
		}
		out = append(out, input)
		seen[strings.ToLower(input.Title)] = true
		if len(out) == maxFollowups {
			break
		}
	}
	return out
}

// Commit only after the whole round reaches a durable successful outcome.
// A completed work turn is a public statement, not evidence its task is done.
func finishAgendaRound(s *Session, r *Round, cancelled bool) {
	defer func() {
		r.ProposedFollowups = nil
		for i := range r.Turns {
			r.Turns[i].ProposedAgendaUpdates = nil
		}
		// The change from a running agenda to an idle one invalidates any
		// action composed before the outcome was published.
		if len(s.Agenda) > 0 {
			s.AgendaVersion++
		}
	}()
	if cancelled || s.Status != "ready" || len(r.Turns) == 0 {
		return
	}
	if r.Phase == "synthesis" && len(r.Turns) == 1 && r.Turns[0].Status == "done" {
		for _, input := range r.ProposedFollowups {
			item := AgendaItem{AgendaInput: input, Source: "synthesis", SourceRound: r.Number, SourceSeat: r.Turns[0].Seat}
			if err := s.appendAgenda(item); err == nil {
				addEvent(s, "agenda_suggested", item.SourceSeat, item.Title)
			}
		}
	}
	applyRoundAgendaUpdates(s, r)
	item := s.findAgenda(r.AgendaItemID)
	// Only a preset's explicit discussion stage can finish automatically.
	// Targeted proposals from a subset of seats leave the stage open.
	if item != nil && item.Phase != "" && item.Status == "pending" && item.Preset == r.Preset && item.Phase == r.Phase && (r.Phase == "synthesis" || len(r.Turns) == len(s.Seats)) {
		item.Status = "done"
		s.ActiveAgendaID = ""
		for _, next := range s.Agenda {
			if next.Source == "template" && next.Preset == r.Preset && next.Phase != "" && next.Status == "pending" {
				s.ActiveAgendaID = next.ID
				break
			}
		}
		addEvent(s, "agenda_stage_done", "", item.Title)
	}
}
