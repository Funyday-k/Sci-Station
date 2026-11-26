package meeting

import (
	"errors"
	"fmt"
	"slices"
	"strings"
)

// MemberChange identifies the seat whose current configuration the host saw.
// Model and effort must be resolved together against the live Magpie catalog.
type MemberChange struct {
	SeatID          string `json:"seat_id"`
	Model           string `json:"model"`
	Effort          string `json:"effort"`
	ExpectedVersion *int   `json:"expected_version"`
}

// memberForSeat returns explicit configuration only. Old CLI-era seats keep
// using their app preference until the host configures that particular seat.
func (s *Session) memberForSeat(id string) *Member {
	for i := range s.Members {
		if s.Members[i].ID == id {
			return &s.Members[i]
		}
	}
	if m, ok := s.SeatOverrides[id]; ok {
		return &m
	}
	return nil
}

// Older CLI preferences used "model" as shorthand for "codex/model" or
// "cursor/model". Explicit catalog choices, including unqualified aliases,
// must use their exact ID.
func legacyCatalogID(seat, model string) string {
	if model != "" && (seat == "codex" || seat == "cursor") && !strings.Contains(model, "/") {
		return seat + "/" + model
	}
	return model
}

func (s *Session) effectiveMember(id string, defaults Settings) Member {
	if m := s.memberForSeat(id); m != nil {
		out := *m
		if out.Effort == "" {
			out.Effort = "auto"
		}
		return out
	}
	model := legacyCatalogID(id, defaults.Models[id])
	effort := defaults.Efforts[id]
	if effort == "" {
		effort = "auto"
	}
	return Member{ID: id, Model: model, Label: model, Source: id, Effort: effort}
}

func (e *Engine) SessionMembers(id string) ([]Member, error) {
	s, err := e.Get(id)
	if err != nil {
		return nil, err
	}
	defaults := e.settings()
	if s.Status == "running" && len(s.Rounds) > 0 {
		defaults = s.Rounds[len(s.Rounds)-1].Settings
	}
	members := make([]Member, 0, len(s.Seats))
	for _, seat := range s.Seats {
		if s.memberForSeat(seat) == nil && (s.Status == "closed" || s.Report != nil) {
			// A CLI-era archive has no saved roster. Never attribute today's
			// preference to someone who spoke under an earlier configuration.
			member := Member{ID: seat}
			if recorded, ok := s.lastLegacyMember(seat); ok {
				member = recorded
			}
			members = append(members, member)
			continue
		}
		members = append(members, s.effectiveMember(seat, defaults))
	}
	return members, nil
}

func (s *Session) canChangeMember(id string) error {
	if err := s.requireOpen(); err != nil {
		return err
	}
	if s.Status == "running" || s.AgendaDraftStatus == "drafting" {
		return fmt.Errorf("%w: 请在本轮讨论或首席起草结束后更改席位设置", ErrConflict)
	}
	if !slices.Contains(s.Seats, id) {
		return errors.New("未找到本场会议的席位")
	}
	return nil
}

func (s *Session) lastLegacyMember(seat string) (Member, bool) {
	for i := len(s.Rounds) - 1; i >= 0; i-- {
		r := &s.Rounds[i]
		for _, t := range r.Turns {
			if t.Seat != seat {
				continue
			}
			model := r.RecordedTurnModel(t)
			if model == "" {
				continue
			}
			if !r.Settings.CatalogModelIDs[seat] {
				model = legacyCatalogID(seat, model)
			}
			effort := t.Effort
			if effort == "" {
				effort = r.Settings.Efforts[seat]
			}
			label := t.ModelLabel
			if label == "" {
				label = model
			}
			return Member{ID: seat, Model: model, Label: label, Source: t.ModelSource, Effort: effort}, true
		}
	}
	return Member{}, false
}

// Resolve executes network catalog discovery outside the archive lock. The
// second state check prevents a concurrent round start or seat edit from
// crossing the configuration boundary.
func (e *Engine) ChangeMember(id string, change MemberChange, resolve func() (Member, error)) (*Session, error) {
	if change.ExpectedVersion == nil || *change.ExpectedVersion < 0 || change.SeatID == "" || change.Model == "" || change.Effort == "" {
		return nil, errors.New("请提交席位编号、模型、思考强度和当前版本")
	}
	initial, err := e.Get(id)
	if err != nil {
		return nil, err
	}
	if err := initial.canChangeMember(change.SeatID); err != nil {
		return initial, err
	}
	chosen, err := resolve()
	if err != nil {
		return nil, err
	}
	if chosen.Model != change.Model || chosen.Effort != change.Effort {
		return nil, errors.New("席位设置与 Magpie 的模型目录不一致")
	}
	var result *Session
	err = e.locked(func() error {
		s, err := e.load(id)
		if err != nil {
			return err
		}
		if err = e.recover(s); err != nil {
			return err
		}
		result = s
		if err = s.canChangeMember(change.SeatID); err != nil {
			return err
		}
		current := s.effectiveMember(change.SeatID, e.settings())
		explicit := s.memberForSeat(change.SeatID) != nil
		if explicit && current.Model == chosen.Model && current.Effort == chosen.Effort {
			return nil // Idempotent retry, even if the original save already advanced the version.
		}
		if current.Version != *change.ExpectedVersion {
			return fmt.Errorf("%w: 这个席位已更新，请核对最新设置", ErrConflict)
		}
		prev := current.Model
		if !explicit {
			if last, ok := s.lastLegacyMember(change.SeatID); ok {
				prev = last.Model
			}
		}
		next := current
		next.Model, next.Effort, next.Label, next.Source = chosen.Model, chosen.Effort, chosen.Label, chosen.Source
		next.Version++
		if next.Model != prev {
			next.PreviousModel = prev
			next.SwitchedAfterRound = len(s.Rounds)
			next.ModelEpoch++
		}
		if i := slices.IndexFunc(s.Members, func(m Member) bool { return m.ID == next.ID }); i >= 0 {
			s.Members[i] = next
		} else {
			if s.SeatOverrides == nil {
				s.SeatOverrides = make(map[string]Member)
			}
			s.SeatOverrides[next.ID] = next
		}
		addEvent(s, "seat_settings_changed", next.ID, fmt.Sprintf("%s（%s） → %s（%s）", current.Model, current.Effort, next.Model, next.Effort))
		return e.save(s)
	})
	return result, err
}
