package meeting

import (
	"context"
	"crypto/sha256"
	"errors"
	"fmt"
	"strings"
	"unicode/utf8"

	"scistation.local/desktop/internal/deliberation"
)

type ContinuousConfig struct {
	Goal         string `json:"goal"`
	Criteria     string `json:"criteria,omitempty"`
	MaxRounds    int    `json:"max_rounds"`
	SummaryEvery int    `json:"summary_every"`
}

type ContinuousState struct {
	Config       ContinuousConfig      `json:"config"`
	Status       string                `json:"status"`
	Stage        string                `json:"stage,omitempty"`
	Manual       bool                  `json:"manual,omitempty"`
	StartRound   int                   `json:"start_round,omitempty"`
	Target       string                `json:"target,omitempty"`
	SettledRound int                   `json:"settled_round,omitempty"`
	Reason       string                `json:"reason,omitempty"`
	Next         string                `json:"next,omitempty"`
	Evidence     []reportEvidence      `json:"evidence,omitempty"`
	Stalled      int                   `json:"stalled,omitempty"`
	LastResult   string                `json:"last_result,omitempty"`
	Checkpoint   *ContinuousCheckpoint `json:"checkpoint,omitempty"`
}

func (c *ContinuousState) active() bool { return c != nil && c.Status == "active" }

func continuousConfig(input ContinuousConfig, topic string) (ContinuousConfig, error) {
	input.Goal = strings.TrimSpace(input.Goal)
	input.Criteria = strings.TrimSpace(input.Criteria)
	if input.Goal == "" {
		input.Goal = topic
	}
	if input.MaxRounds == 0 {
		input.MaxRounds = 12
	}
	if input.SummaryEvery == 0 {
		input.SummaryEvery = 4
	}
	if input.MaxRounds < 1 || input.MaxRounds > 60 || input.SummaryEvery < 2 || input.SummaryEvery > 12 {
		return input, errors.New("持续推进每次可运行 1–60 轮，摘要间隔为 2–12 轮")
	}
	if utf8.RuneCountInString(input.Goal) > maxInputCharacters || utf8.RuneCountInString(input.Criteria) > maxInputCharacters {
		return input, errors.New("目标和验收条件各限 12000 字")
	}
	return input, nil
}

func (s *Session) armContinuous(input *ContinuousConfig, preset, note string) error {
	if input == nil {
		if s.Continuous != nil {
			s.Continuous.Manual = true
		}
		return nil
	}
	cfg, err := continuousConfig(*input, s.Topic)
	if err != nil {
		return err
	}
	prior := s.Continuous
	next := &ContinuousState{Config: cfg, Status: "active", Stage: "round", StartRound: len(s.Rounds) + 1}
	if prior != nil && prior.Config.Goal == cfg.Goal && prior.Config.Criteria == cfg.Criteria {
		next.Checkpoint = prior.Checkpoint
		if !prior.Manual && prior.Status == "paused" && note == "" && len(s.Rounds) > 0 && s.Rounds[len(s.Rounds)-1].Preset == preset {
			next.Next = prior.Next
		}
	}
	s.Continuous = next
	return nil
}

// Once the subjects of a round have spoken, persist its agenda outcome once.
// During review the session still owns the same lease and can be paused.
func recordRoundEnd(s *Session, cancelled bool, interruptedMessage string) {
	confirmed := !cancelled && interruptedMessage == ""
	if interruptedMessage == "" {
		interruptedMessage = "Round interrupted."
		if cancelled {
			interruptedMessage = "Cancelled by user."
		}
	}
	r := &s.Rounds[len(s.Rounds)-1]
	for i := range r.Turns {
		t := &r.Turns[i]
		if t.Status == "running" || t.Status == "pending" {
			t.Status, t.Error, t.FinishedAt = "error", interruptedMessage, now()
		}
		for j := range t.Children {
			child := &t.Children[j]
			if child.Status == "running" || child.Status == "pending" {
				child.Status, child.Error, child.FinishedAt = "error", "Child interrupted.", now()
			}
		}
	}
	s.Status = terminal(r)
	finishAgendaRound(s, r, !confirmed)
	finishBoardRound(s, r, confirmed)
	addEvent(s, "round_finished", "", s.Status)
}

func pauseContinuous(s *Session, reason string) {
	c := s.Continuous
	c.Status, c.Stage, c.Reason = "paused", "", reason
	addEvent(s, "continuous_paused", "", reason)
}

func repeatKey(r Round) string {
	h := sha256.New()
	for _, t := range r.Turns {
		fmt.Fprintln(h, t.Seat, strings.Join(strings.Fields(t.Text), " "))
		for _, ch := range t.Changes {
			fmt.Fprintln(h, ch.Path, ch.After)
		}
	}
	return fmt.Sprintf("%x", h.Sum(nil))
}

func nextContinuousPhase(r Round) string {
	switch r.Phase {
	case "work":
		return "work"
	case "challenge":
		return "synthesis"
	default:
		return "challenge"
	}
}

// Each continuation reuses the human-started lease. No browser poll, timer,
// or second worker can submit the same round.
func (e *Engine) afterContinuousRound(ctx context.Context, id string) (guidance string, again bool, err error) {
	var snapshot *Session
	err = e.locked(func() error {
		s, err := e.load(id)
		if err != nil {
			return err
		}
		if ctx.Err() != nil || s.CancelRequested {
			return context.Canceled
		}
		c := s.Continuous
		recordRoundEnd(s, false, "")
		c.SettledRound = len(s.Rounds)
		if s.Status != "ready" {
			pauseContinuous(s, "本轮有席位未完成，请检查记录后再继续。")
		} else {
			s.Status, c.Stage = "running", "review"
			snapshot = s
		}
		return e.save(s)
	})
	if err != nil || snapshot == nil {
		return
	}
	v, err := e.assessContinuous(ctx, snapshot)
	if err != nil {
		return "", false, err
	}
	c := snapshot.Continuous
	r := snapshot.Rounds[len(snapshot.Rounds)-1]
	used := r.Number - c.StartRound + 1
	key := repeatKey(r)
	stalled := 0
	if !v.Progress || c.LastResult == key {
		stalled = c.Stalled + 1
	}
	done := v.Decision == "complete" && (r.Preset == "work" || r.Phase == "synthesis")
	phase := nextContinuousPhase(r)
	next := strings.TrimSpace(v.Next)
	if next == "" && !done {
		next = "按本模式的下一阶段核对目标、验收条件和仍待解决的问题。"
	}
	shouldCompact := used%c.Config.SummaryEvery == 0 && r.Number > 1 && !done && v.Decision != "blocked"
	err = e.locked(func() error {
		s, err := e.load(id)
		if err != nil {
			return err
		}
		if ctx.Err() != nil || s.CancelRequested {
			return context.Canceled
		}
		state := s.Continuous
		state.Next, state.Reason, state.Evidence = next, v.Reason, v.Evidence
		state.LastResult, state.Stalled = key, stalled
		if shouldCompact {
			state.Stage = "summary"
		}
		return e.save(s)
	})
	if err != nil {
		return
	}
	var cp *ContinuousCheckpoint
	if shouldCompact {
		snapshot.Continuous.Next, snapshot.Continuous.Reason = next, v.Reason
		cp, err = e.summarizeContinuous(ctx, snapshot, r.Number-1)
		if err != nil {
			return "", false, err
		}
	}
	err = e.locked(func() error {
		s, err := e.load(id)
		if err != nil {
			return err
		}
		if ctx.Err() != nil || s.CancelRequested {
			return context.Canceled
		}
		state := s.Continuous
		if cp != nil {
			state.Checkpoint = cp
			s.Rounds[len(s.Rounds)-1].Checkpoint = cp
			addEvent(s, "continuous_summary", "", fmt.Sprintf("已压缩至第 %d 轮", cp.ThroughRound))
		}
		switch {
		case done:
			s.Status, state.Status, state.Stage, state.Next = "ready", "completed", "", ""
			addEvent(s, "continuous_completed", "", v.Reason)
		case v.Decision == "blocked":
			s.Status = "ready"
			pauseContinuous(s, v.Reason)
		case used >= state.Config.MaxRounds:
			s.Status = "ready"
			pauseContinuous(s, "已达到本次轮数上限。")
		case stalled >= 2:
			s.Status = "ready"
			pauseContinuous(s, "连续两轮没有可核实的新进展。")
		default:
			plan, er := deliberation.Resolve(r.Preset, phase)
			if er != nil {
				return er
			}
			seats := s.Seats
			target := state.Target
			if target == "" && plan.Synthesis() {
				target = seats[0]
			}
			if target != "" {
				seats = []string{target}
			}
			settings, er := e.validatedSettings(s, seats)
			if er != nil {
				return er
			}
			rules, er := e.loadRoundRules(s)
			if er != nil {
				return er
			}
			pluginGuidance, er := e.snapshotPluginGuidance(roundGuidance)
			if er != nil {
				return er
			}
			guidance = rules.Guidance
			appendRound(s, plan, next, target, seats, settings, rules, pluginGuidance, r.MaterialIDs, true)
			state.Stage = "round"
			again = true
		}
		if err = e.save(s); err != nil {
			return err
		}
		if again {
			e.cancelMu.Lock()
			e.activeRounds[id] = len(s.Rounds)
			e.cancelMu.Unlock()
		}
		return nil
	})
	return
}
