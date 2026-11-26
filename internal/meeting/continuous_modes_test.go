package meeting

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"sync"
	"sync/atomic"
	"testing"

	"scistation.local/desktop/internal/deliberation"
)

func TestContinuousModesAdvanceToCompletion(t *testing.T) {
	tests := []struct {
		name       string
		preset     string
		wantPhases []string
	}{
		{name: "review", preset: "review", wantPhases: []string{"proposal", "challenge", "synthesis"}},
		{name: "prioritize", preset: "prioritize", wantPhases: []string{"proposal", "challenge", "synthesis"}},
		{name: "forum", preset: "forum", wantPhases: []string{"proposal", "challenge", "synthesis"}},
		{name: "work", preset: "work", wantPhases: []string{"work", "work"}},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			var reviews, summaries atomic.Int32
			var mu sync.Mutex
			var observedPhases []string
			var observedPermissions []bool
			call := func(ctx context.Context, seat, model, prompt, executable string) (string, error) {
				instructions := deliberation.InstructionsFrom(ctx)
				switch {
				case strings.Contains(instructions, "CONTINUOUS_REVIEW"):
					n := reviews.Add(1)
					round, err := continuousTestReviewRound(prompt)
					if err != nil {
						return "", err
					}
					complete := false
					if tc.preset == "work" {
						complete = n >= 2
					} else {
						complete = round == 3
					}
					decision, reason, next := "continue", "检查显示仍有待核实事项。", "继续到下一个讨论阶段。"
					if complete {
						decision, reason, next = "complete", "目标依据已满足。", ""
					}
					return fmt.Sprintf(`{"decision":%q,"reason":%q,"next":%q,"evidence":[{"id":%q,"quote":"PUBLIC_ORIGINAL_QUOTE"}],"progress":true}`, decision, reason, next, fmt.Sprintf("R%d-T1", round)), nil
				case strings.Contains(instructions, "CONTINUOUS_SUMMARY"):
					summaries.Add(1)
					return say("continuous summary"), nil
				default:
					data, err := continuousTestPromptContext(prompt)
					if err != nil {
						return "", err
					}
					phase, _ := data["phase"].(string)
					allowEdits, _ := data["allow_edits"].(bool)
					mu.Lock()
					observedPhases = append(observedPhases, phase)
					observedPermissions = append(observedPermissions, allowEdits)
					mu.Unlock()
					return say("PUBLIC_ORIGINAL_QUOTE"), nil
				}
			}

			e, project := engine(t, call)
			s, err := e.Create("持续验证目标", project, []string{"codex"})
			if err != nil {
				t.Fatal(err)
			}
			config := &ContinuousConfig{Goal: "确认是否达到交付目标", Criteria: "目标有可核对证据", MaxRounds: 8, SummaryEvery: 12}
			started, err := e.StartRound(s.ID, "", "", 0, RoundOptions{Preset: tc.preset, Phase: tc.wantPhases[0], Continuous: config})
			if err != nil {
				t.Fatal(err)
			}
			if len(started.Rounds) != 1 || started.Status != "running" {
				t.Fatalf("StartRound did not start exactly one initial round: status=%q rounds=%d", started.Status, len(started.Rounds))
			}
			final := settled(t, e, s.ID)
			if final.Status != "ready" || final.Continuous == nil || final.Continuous.Status != "completed" {
				t.Fatalf("continuous run state = session:%q continuous:%+v, want completed; rounds=%+v", final.Status, final.Continuous, final.Rounds)
			}
			if len(final.Rounds) < len(tc.wantPhases) {
				t.Fatalf("continuous run stopped after %d rounds, want at least %d", len(final.Rounds), len(tc.wantPhases))
			}
			if reviews.Load() == 0 {
				t.Fatal("continuous review was not called")
			}
			if summaries.Load() != 0 {
				t.Fatalf("periodic summary ran %d times before summary_every=12", summaries.Load())
			}

			mu.Lock()
			phases := append([]string(nil), observedPhases...)
			permissions := append([]bool(nil), observedPermissions...)
			mu.Unlock()
			if len(phases) < len(tc.wantPhases) {
				t.Fatalf("observed phases %v, want at least %v", phases, tc.wantPhases)
			}
			for i, phase := range tc.wantPhases {
				if phases[i] != phase {
					t.Fatalf("phase %d = %q, want %q; all phases: %v", i, phases[i], phase, phases)
				}
			}
			for i, allowEdits := range permissions {
				if allowEdits {
					t.Fatalf("round %d allow_edits = %v, want false", i+1, allowEdits)
				}
			}
			for i, round := range final.Rounds {
				if round.Preset != tc.preset || round.Phase != tc.wantPhases[min(i, len(tc.wantPhases)-1)] {
					t.Fatalf("round %d plan = %s/%s, phases should follow %v", i+1, round.Preset, round.Phase, tc.wantPhases)
				}
				if round.Settings.AllowEdits {
					t.Fatalf("round %d snapshotted allow_edits = %v, want false", i+1, round.Settings.AllowEdits)
				}
			}
		})
	}
}

func TestContinuousNilKeepsManualOneRoundWorkflow(t *testing.T) {
	var reviews atomic.Int32
	e, project := engine(t, func(ctx context.Context, seat, model, prompt, executable string) (string, error) {
		if strings.Contains(deliberation.InstructionsFrom(ctx), "CONTINUOUS_REVIEW") {
			reviews.Add(1)
		}
		return say("manual round finished"), nil
	})
	s, err := e.Create("manual workflow", project, []string{"codex"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err = e.StartRound(s.ID, "", "", 0, RoundOptions{Preset: "work", Phase: "work"}); err != nil {
		t.Fatal(err)
	}
	final := settled(t, e, s.ID)
	if final.Status != "ready" || len(final.Rounds) != 1 {
		t.Fatalf("nil continuous config changed the manual workflow: status=%q rounds=%d", final.Status, len(final.Rounds))
	}
	if reviews.Load() != 0 {
		t.Fatalf("nil continuous config invoked review %d times", reviews.Load())
	}
}

func continuousTestPromptContext(prompt string) (map[string]any, error) {
	if !strings.HasPrefix(prompt, "CONTEXT:\n") {
		return nil, fmt.Errorf("public turn prompt has no CONTEXT envelope: %.80q", prompt)
	}
	encoded := strings.TrimPrefix(prompt, "CONTEXT:\n")
	if context, _, ok := strings.Cut(encoded, "\nSTEPS REMAINING:"); ok {
		encoded = context
	}
	var data map[string]any
	if err := json.Unmarshal([]byte(encoded), &data); err != nil {
		return nil, fmt.Errorf("decode public turn context: %w", err)
	}
	return data, nil
}

func continuousTestReviewRound(prompt string) (int, error) {
	_, material, ok := strings.Cut(prompt, "REVIEW MATERIAL\n")
	if !ok {
		return 0, fmt.Errorf("continuous review prompt has no material section")
	}
	var data struct {
		Round int `json:"round"`
	}
	if err := json.Unmarshal([]byte(material), &data); err != nil {
		return 0, fmt.Errorf("decode continuous review material: %w", err)
	}
	if data.Round < 1 {
		return 0, fmt.Errorf("continuous review round is invalid: %d", data.Round)
	}
	return data.Round, nil
}

func TestContinuousManualChoiceSurvivesReturningToMeeting(t *testing.T) {
	s := &Session{Topic: "Test", Continuous: &ContinuousState{Status: "paused", Config: ContinuousConfig{Goal: "Test"}, Next: "Old suggestion"}}
	if err := s.armContinuous(nil, "work", ""); err != nil || !s.Continuous.Manual || s.Continuous.Next == "" {
		t.Fatal("manual run must retain the last checkpoint and paused record", err)
	}
	s.Rounds = []Round{{Number: 1, Preset: "work"}}
	if err := s.armContinuous(&ContinuousConfig{}, "work", ""); err != nil || s.Continuous.Manual || s.Continuous.Next != "" {
		t.Fatal("an explicitly requested new segment must clear manual mode and stale instructions", err)
	}
}
