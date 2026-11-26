package meeting

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"scistation.local/desktop/internal/deliberation"
	"scistation.local/desktop/internal/workspace"
)

func TestAssessContinuousUsesIndependentReviewerAndVerifiesEvidence(t *testing.T) {
	project := tempDir(t)
	const fileText = "Status: Ready\n"
	if err := os.WriteFile(filepath.Join(project, "milestone.md"), []byte(fileText), 0600); err != nil {
		t.Fatal(err)
	}
	s := &Session{
		Topic:   "Complete the milestone",
		Project: project,
		Seats:   []string{"codex", "cursor"},
		Continuous: &ContinuousState{
			Config:     ContinuousConfig{Goal: "Complete milestone.md", Criteria: "The file must say Ready", MaxRounds: 8, SummaryEvery: 3},
			StartRound: 1,
			Checkpoint: &ContinuousCheckpoint{ThroughRound: 1, Items: []ContinuousItem{{Round: 1, Seat: "codex", Text: "Investigated the requested change.", Quote: "Investigated"}}},
		},
		ID: "review-session",
		Rounds: []Round{
			{Number: 1, Settings: testSettings(), Turns: []Turn{{Seat: "codex", Status: "done", Text: "Investigated the requested change."}, {Seat: "cursor", Status: "done", Text: "Another older statement."}}},
			{Number: 2, Settings: testSettings(), Turns: []Turn{{Seat: "codex", Status: "done", Text: "The milestone is ready."}}},
		},
	}
	e, err := New(tempDir(t), func(ctx context.Context, seat, model, prompt, executable string) (string, error) {
		if seat != "cursor" || model != "cursor/main" {
			t.Fatalf("reviewer = %s/%s, want independent cursor seat", seat, model)
		}
		if !strings.Contains(deliberation.InstructionsFrom(ctx), "CONTINUOUS_REVIEW") {
			t.Fatal("reviewer instructions missing CONTINUOUS_REVIEW")
		}
		for _, want := range []string{"R2-T1", "milestone.md", "through_round", "acceptance_criteria", "R1-T1", "CONTINUOUS_REVIEW REQUEST"} {
			if !strings.Contains(prompt, want) {
				t.Fatalf("review prompt missing %q", want)
			}
		}
		if strings.Contains(prompt, "You are an independent, read-only reviewer") {
			t.Fatal("system review rules should not be duplicated in the user prompt")
		}
		if _, session := ModelRequest(ctx); session != "review-session-continuous-review-2" {
			t.Fatalf("review session key = %q", session)
		}
		f, err := workspace.Read(project, "milestone.md")
		if err != nil {
			t.Fatal(err)
		}
		verdict, _ := json.Marshal(ContinuousVerdict{Decision: "complete", Reason: "The file meets the criterion.", Progress: true, Evidence: []reportEvidence{{ID: "FILE:milestone.md@" + f.Version, Quote: "Status: Ready"}}})
		return string(verdict), nil
	}, testSettings)
	if err != nil {
		t.Fatal(err)
	}
	verdict, err := e.assessContinuous(context.Background(), s)
	if err != nil {
		t.Fatal(err)
	}
	if verdict.Decision != "complete" || len(verdict.Evidence) != 1 {
		t.Fatalf("unexpected verdict: %+v", verdict)
	}
}

func TestAssessContinuousFindsAdjacentPathsAndReportsMissingFiles(t *testing.T) {
	settings := testSettings()
	s := &Session{
		Project: tempDir(t), Seats: []string{"codex"}, ID: "paths",
		Continuous: &ContinuousState{Config: ContinuousConfig{Goal: "Check a.md,b.md"}},
		Rounds:     []Round{{Number: 1, Settings: settings, Turns: []Turn{{Seat: "codex", Status: "done", Text: "Review the requested files."}}}},
	}
	e, err := New(tempDir(t), func(ctx context.Context, _, _, prompt, _ string) (string, error) {
		for _, want := range []string{"FILE:a.md@missing", "FILE:b.md@missing", "项目中不存在此文件"} {
			if !strings.Contains(prompt, want) {
				t.Fatalf("review prompt missing %q", want)
			}
		}
		return `{"decision":"continue","reason":"The files are not present.","next":"Create or locate the requested files.","progress":false,"evidence":[]}`, nil
	}, testSettings)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := e.assessContinuous(context.Background(), s); err != nil {
		t.Fatal(err)
	}
}

func TestAssessContinuousRejectsQuoteOutsideSentExcerpt(t *testing.T) {
	statement := strings.Repeat("x", 920) + "LATE_UNSENT_QUOTE"
	s := &Session{
		Project: tempDir(t), Seats: []string{"codex"},
		Continuous: &ContinuousState{Config: ContinuousConfig{Goal: "Finish the task"}},
		Rounds:     []Round{{Number: 1, Settings: testSettings(), Turns: []Turn{{Seat: "codex", Status: "done", Text: statement}}}},
	}
	e, err := New(tempDir(t), func(context.Context, string, string, string, string) (string, error) {
		return `{"decision":"complete","reason":"The source proves completion.","next":"","progress":true,"evidence":[{"id":"R1-T1","quote":"LATE_UNSENT_QUOTE"}]}`, nil
	}, testSettings)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := e.assessContinuous(context.Background(), s); err == nil {
		t.Fatal("quote outside sent excerpt should be rejected")
	}
}

func TestAssessContinuousRejectsUnsupportedCompletion(t *testing.T) {
	s := &Session{
		Project:    tempDir(t),
		Seats:      []string{"codex"},
		Continuous: &ContinuousState{Config: ContinuousConfig{Goal: "Finish the task"}},
		Rounds:     []Round{{Number: 1, Settings: testSettings(), Turns: []Turn{{Seat: "codex", Status: "done", Text: "I will finish it."}}}},
	}
	e, err := New(tempDir(t), func(context.Context, string, string, string, string) (string, error) {
		return `{"decision":"complete","reason":"Done","next":"","progress":false,"evidence":[]}`, nil
	}, testSettings)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := e.assessContinuous(context.Background(), s); err == nil {
		t.Fatal("unsupported completion should be rejected")
	}
}

func TestContinuousVerdictCanCiteOlderCheckpointEvidence(t *testing.T) {
	settings := testSettings()
	state := &Session{
		Project: tempDir(t), Seats: []string{"codex"},
		Continuous: &ContinuousState{Config: ContinuousConfig{Goal: "Check the earlier agreement"}, Checkpoint: &ContinuousCheckpoint{
			ThroughRound: 1, Items: []ContinuousItem{{Text: "Duration settled", Round: 1, Seat: "codex", Quote: "30 minutes"}},
		}},
	}
	for i, speech := range []string{"The group chose 30 minutes.", "Now inspect the agenda.", "Timing satisfies the requirement."} {
		state.Rounds = append(state.Rounds, Round{Number: i + 1, Settings: settings, Turns: []Turn{{Seat: "codex", Status: "done", Text: speech}}})
	}
	e, _ := engine(t, func(_ context.Context, _, _, prompt, _ string) (string, error) {
		if strings.Contains(prompt, "The group chose 30 minutes.") || !strings.Contains(prompt, "R1-T1") {
			t.Fatal("expected the checkpoint citation without the full archived speech")
		}
		return `{"decision":"complete","reason":"Timing verified","next":"","progress":true,"evidence":[{"id":"R1-T1","quote":"30 minutes"}]}`, nil
	})
	if _, err := e.assessContinuous(context.Background(), state); err != nil {
		t.Fatal(err)
	}
}

func TestAssessContinuousRepairsInvalidEvidenceOnceWithOptionID(t *testing.T) {
	settings := testSettings()
	state := &Session{
		ID: "repair", Project: tempDir(t), Seats: []string{"codex"},
		Continuous: &ContinuousState{Config: ContinuousConfig{Goal: "确认任务完成"}},
		Rounds:     []Round{{Number: 1, Settings: settings, Turns: []Turn{{Seat: "codex", Status: "done", Text: "交付文件已经完成并通过检查。"}}}},
	}
	var calls int
	e, err := New(tempDir(t), func(_ context.Context, _, _, prompt, _ string) (string, error) {
		calls++
		if calls == 1 {
			return `{"decision":"complete","reason":"已完成。","next":"","progress":true,"evidence":[{"id":"R1-T1","quote":"这是未展示的引文"}]}`, nil
		}
		if !strings.Contains(prompt, "CORRECTION") || !strings.Contains(prompt, "Q001") {
			t.Fatal("second request must include bounded correction feedback and selectable evidence IDs")
		}
		return `{"decision":"complete","reason":"交付文件已完成并通过检查。","next":"","progress":true,"evidence":[{"id":"Q001"}]}`, nil
	}, testSettings)
	if err != nil {
		t.Fatal(err)
	}
	verdict, err := e.assessContinuous(context.Background(), state)
	if err != nil {
		t.Fatal(err)
	}
	if calls != 2 || verdict.Decision != "complete" || len(verdict.Evidence) != 1 {
		t.Fatalf("calls=%d, verdict=%+v", calls, verdict)
	}
	if verdict.Evidence[0].ID != "R1-T1" || verdict.Evidence[0].Quote != "交付文件已经完成并通过检查。" {
		t.Fatalf("selected quote was not resolved from visible evidence: %+v", verdict.Evidence[0])
	}
}

func TestAssessContinuousDoesNotRetryCancellation(t *testing.T) {
	settings := testSettings()
	state := &Session{
		Project: tempDir(t), Seats: []string{"codex"},
		Continuous: &ContinuousState{Config: ContinuousConfig{Goal: "继续检查"}},
		Rounds:     []Round{{Number: 1, Settings: settings, Turns: []Turn{{Seat: "codex", Status: "done", Text: "本轮已有进展。"}}}},
	}
	ctx, cancel := context.WithCancel(context.Background())
	var calls int
	e, err := New(tempDir(t), func(context.Context, string, string, string, string) (string, error) {
		calls++
		cancel()
		return "", context.Canceled
	}, testSettings)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := e.assessContinuous(ctx, state); err == nil {
		t.Fatal("cancelled review should return an error")
	}
	if calls != 1 {
		t.Fatalf("cancelled review was retried %d times", calls-1)
	}
}

func TestContinuousReviewRejectsArbitraryOptionQuote(t *testing.T) {
	_, err := validateContinuousReply(
		`{"decision":"complete","reason":"完成","next":"","progress":true,"evidence":[{"id":"Q001","quote":"伪造的近似引文"}]}`,
		map[string]string{"R1-T1": "原话确实已经完成。"},
		map[string][]string{"R1-T1": {"原话确实已经完成。"}},
		[]continuousEvidenceOption{{ID: "Q001", SourceID: "R1-T1", Quote: "原话确实已经完成。"}},
	)
	if err == nil {
		t.Fatal("an option ID paired with an approximate quote must be rejected")
	}
}
