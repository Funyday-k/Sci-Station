package meeting

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"testing"
	"unicode/utf8"
)

func continuousSummaryEngine(reply string, calls *int) *Engine {
	return &Engine{
		call: func(_ context.Context, seat, model, prompt, _ string) (string, error) {
			(*calls)++
			if seat != "chair" || model != "summary-model" || !strings.Contains(prompt, "host_instructions") {
				return "", errors.New("summary request omitted required routing or context")
			}
			return reply, nil
		},
		settings: func() Settings { return Settings{Models: map[string]string{"chair": "summary-model"}, Timeout: 30} },
	}
}

func TestSummarizeContinuousRollsFromCheckpointAndValidatesSources(t *testing.T) {
	var calls int
	e := continuousSummaryEngine(`{"items":[{"text":"Open disagreement remains","round":2,"seat":"pro","quote":"I still oppose the launch."},{"text":"The deadline is Friday","round":3,"seat":"chair","quote":"The deadline is Friday."}]}`, &calls)
	s := &Session{ID: "continuous-test", Seats: []string{"chair"}, Continuous: &ContinuousState{Config: ContinuousConfig{Goal: "Decide launch", Criteria: "Resolve blockers"}, Checkpoint: &ContinuousCheckpoint{ThroughRound: 1, Items: []ContinuousItem{{Text: "Pilot proposed", Round: 1, Seat: "pro", Quote: "A pilot is acceptable."}}}}, Agenda: []AgendaItem{{AgendaInput: AgendaInput{Title: "Launch readiness", Kind: "discussion"}, Status: "pending"}}, Rounds: []Round{
		{Number: 1, Turns: []Turn{{Seat: "pro", Status: "done", Text: "A pilot is acceptable."}}},
		{Number: 2, Note: "Keep the rollback criterion explicit", Turns: []Turn{{Seat: "pro", Status: "done", Text: "I still oppose the launch."}, {Seat: "chair", Status: "error", Text: "not public"}}},
		{Number: 3, Note: "Check the deadline", Turns: []Turn{{Seat: "chair", Status: "done", Text: "The deadline is Friday."}}},
		{Number: 4, Auto: true, Note: "automatic note must not be exposed", Turns: []Turn{{Seat: "chair", Status: "done", Text: "automatic statement"}}},
	}}
	s.Rounds[3].Settings = Settings{Models: map[string]string{"chair": "summary-model"}, Timeout: 30}
	got, err := e.summarizeContinuous(context.Background(), s, 3)
	if err != nil {
		t.Fatal(err)
	}
	if got.ThroughRound != 3 || len(got.Items) != 2 || calls != 1 {
		t.Fatalf("unexpected checkpoint: %+v calls=%d", got, calls)
	}

	// A fabricated citation must fail and leave the supplied old checkpoint intact.
	old := s.Continuous.Checkpoint
	e.call = func(context.Context, string, string, string, string) (string, error) {
		return `{"items":[{"text":"Fabricated","round":2,"seat":"pro","quote":"not in the statement"}]}`, nil
	}
	if _, err := e.summarizeContinuous(context.Background(), s, 3); err == nil {
		t.Fatal("accepted a fabricated quote")
	}
	if s.Continuous.Checkpoint != old || old.ThroughRound != 1 {
		t.Fatal("failed summary mutated prior checkpoint")
	}
}

func TestSummarizeContinuousRejectsUnindexedOrOversizedHistory(t *testing.T) {
	var calls int
	e := continuousSummaryEngine(`{"items":[]}`, &calls)
	s := &Session{ID: "continuous-test", Seats: []string{"chair"}, Continuous: &ContinuousState{Checkpoint: &ContinuousCheckpoint{ThroughRound: 1}}, Rounds: []Round{
		{Number: 1, Turns: []Turn{{Seat: "chair", Status: "done", Text: "prior"}}},
		{Number: 2, Turns: []Turn{{Seat: "chair", Status: "done", Text: strings.Repeat("x", continuousSummaryInputLimit)}}},
	}}
	s.Rounds[1].Settings = Settings{Models: map[string]string{"chair": "summary-model"}, Timeout: 30}
	s.Rounds[1].Turns = make([]Turn, 20)
	for i := range s.Rounds[1].Turns {
		s.Rounds[1].Turns[i] = Turn{Seat: "chair", Status: "done", Text: strings.Repeat("\"", continuousSummarySpeechLimit+1)}
	}
	if _, err := e.summarizeContinuous(context.Background(), s, 2); err == nil || calls != 0 {
		t.Fatalf("oversized history should fail before invocation, calls=%d err=%v", calls, err)
	}

	// A checkpoint source that has disappeared cannot be cited safely.
	s.Continuous.Checkpoint = &ContinuousCheckpoint{ThroughRound: 1, Items: []ContinuousItem{{Text: "old", Round: 1, Seat: "gone", Quote: "proof"}}}
	s.Rounds[0].Turns = nil
	if _, err := e.summarizeContinuous(context.Background(), s, 2); err == nil {
		t.Fatal("accepted an unindexed retained citation")
	}
}

func TestSummarizeContinuousChecksSameRoundCitationAndItemBounds(t *testing.T) {
	var calls int
	s := &Session{ID: "continuous-test", Seats: []string{"chair"}, Continuous: &ContinuousState{}, Rounds: []Round{{Number: 1, Turns: []Turn{{Seat: "chair", Status: "done", Text: "I support the limited pilot."}}}}}
	s.Rounds[0].Settings = Settings{Models: map[string]string{"chair": "summary-model"}, Timeout: 30}
	for _, tc := range []struct{ name, reply string }{
		{"wrong quote", `{"items":[{"text":"Support","round":1,"seat":"chair","quote":"I oppose the pilot"}]}`},
		{"too many", `{"items":[` + strings.TrimSuffix(strings.Repeat(`{"text":"x","round":1,"seat":"chair","quote":"pilot"},`, continuousSummaryItemsLimit+1), ",") + `]}`},
		{"too long", `{"items":[{"text":"` + strings.Repeat("x", continuousSummaryTextLimit+1) + `","round":1,"seat":"chair","quote":"pilot"}]}`},
	} {
		t.Run(tc.name, func(t *testing.T) {
			calls = 0
			e := continuousSummaryEngine(tc.reply, &calls)
			if _, err := e.summarizeContinuous(context.Background(), s, 1); err == nil {
				t.Fatal("invalid summary accepted")
			}
		})
	}
}

func TestContinuousCheckpointJSONShape(t *testing.T) {
	b, err := json.Marshal(ContinuousCheckpoint{ThroughRound: 7, Items: []ContinuousItem{{Text: "constraint", Round: 5, Seat: "seat-a", Quote: "keep rollback"}}})
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(b), `"through_round":7`) || !strings.Contains(string(b), `"seat":"seat-a"`) {
		t.Fatalf("unexpected checkpoint JSON: %s", b)
	}
}

func TestSummarizeContinuousIncludesAutomatedRoundSpeechesAndOnlyPriorQuotes(t *testing.T) {
	var calls int
	var prompt string
	e := continuousSummaryEngine(`{"items":[{"text":"Automated round recorded the checkpoint","round":2,"seat":"chair","quote":"The result is logged."},{"text":"Prior disagreement retained","round":1,"seat":"pro","quote":"I still object."}]}`, &calls)
	e.call = func(_ context.Context, seat, model, p, _ string) (string, error) {
		calls++
		prompt = p
		return `{"items":[{"text":"Automated round recorded the checkpoint","round":2,"seat":"chair","quote":"The result is logged."},{"text":"Prior disagreement retained","round":1,"seat":"pro","quote":"I still object."}]}`, nil
	}
	s := &Session{Topic: "持续推进", ID: "continuous-auto", Seats: []string{"chair"}, Continuous: &ContinuousState{Checkpoint: &ContinuousCheckpoint{ThroughRound: 1, Items: []ContinuousItem{{Text: "Objection remains", Round: 1, Seat: "pro", Quote: "I still object."}}}}, Rounds: []Round{
		{Number: 1, Turns: []Turn{{Seat: "pro", Status: "done", Text: "Earlier context: I still object. There is another unshown detail."}}},
		{Number: 2, Auto: true, Note: "system-generated continuation note", Turns: []Turn{{Seat: "chair", Status: "done", Text: "The result is logged."}}},
	}}
	s.Rounds[1].Settings = Settings{Models: map[string]string{"chair": "summary-model"}, Timeout: 30}
	got, err := e.summarizeContinuous(context.Background(), s, 2)
	if err != nil {
		t.Fatal(err)
	}
	if got.ThroughRound != 2 || calls != 1 {
		t.Fatalf("unexpected summary: %+v calls=%d", got, calls)
	}
	if strings.Contains(prompt, "system-generated continuation note") || !strings.Contains(prompt, "The result is logged.") || !strings.Contains(prompt, "I still object.") {
		t.Fatal("automated round speech or previously retained quote was not handled correctly")
	}
	e.call = func(context.Context, string, string, string, string) (string, error) {
		return `{"items":[{"text":"Unsupported old detail","round":1,"seat":"pro","quote":"There is another unshown detail."}]}`, nil
	}
	if _, err := e.summarizeContinuous(context.Background(), s, 2); err == nil {
		t.Fatal("accepted old source wording that was not in the previous checkpoint quote")
	}
}

func TestContinuousQuoteOptionsAreVerbatimBoundedAndUnicodeSafe(t *testing.T) {
	text := "第一句。第二句保留。Third line!\n" + "开头" + strings.Repeat("界", 220) + "结尾。" + "\n[… middle omitted …]\nTail evidence?"
	options := continuousQuoteOptions(text)
	if len(options) == 0 || len(options) > 3 {
		t.Fatalf("unexpected candidate count: %d", len(options))
	}
	for _, option := range options {
		if !strings.Contains(text, option) || strings.Contains(option, "middle omitted") || strings.ContainsRune(option, utf8.RuneError) || utf8.RuneCountInString(option) > 180 {
			t.Fatalf("candidate is not a short verbatim Unicode-safe source excerpt: %q", option)
		}
	}
}

func TestContinuousQuoteOptionsCoverBeginningMiddleEndAndEnglishBoundaries(t *testing.T) {
	text := "First point is in source.go. Second point is concise. Third point has a 1.25 second cutoff. Fourth point is central. Fifth point closes it."
	options := continuousQuoteOptions(text)
	if len(options) != 3 || !strings.HasPrefix(options[0], "First point") || !strings.Contains(options[1], "Third point") || !strings.Contains(options[2], "Fifth point") {
		t.Fatalf("candidates should cover first/middle/last sentences: %#v", options)
	}
	if !strings.Contains(options[0], "source.go") || !strings.Contains(options[1], "1.25") {
		t.Fatalf("filename or decimal was split as a sentence: %#v", options)
	}
}

func TestContinuousSummaryAllowsVerifiedLegacyCitationWhenOptionsDoNotFit(t *testing.T) {
	text := "A candidate can say that evidence was logged, but the precise fact is: the rollback deadline is Friday."
	snippet := continuousSummaryExcerpt(text, continuousSummarySpeechLimit)
	items := []continuousSpeech{{Round: 2, Seat: "reviewer", Text: snippet}}
	originals := map[statementRef]string{{2, "reviewer"}: text}
	visible := map[statementRef][]string{{2, "reviewer"}: {snippet}}
	got, err := validateContinuousSummary(`{"items":[{"text":"The rollback deadline is Friday","round":2,"seat":"reviewer","quote":"the rollback deadline is Friday."}]}`, 2, originals, items, nil, visible, map[string]ContinuousItem{})
	if err != nil {
		t.Fatal(err)
	}
	if got.Items[0].Round != 2 || got.Items[0].Seat != "reviewer" || got.Items[0].Quote != "the rollback deadline is Friday." {
		t.Fatalf("legacy citation fields were not preserved: %+v", got.Items[0])
	}
}

func TestSummarizeContinuousUsesQuoteIDsAndRetriesOnlyBadFormatOnce(t *testing.T) {
	var calls int
	var prompts []string
	e := &Engine{
		settings: func() Settings { return Settings{} },
		call: func(_ context.Context, _, _, prompt, _ string) (string, error) {
			calls++
			prompts = append(prompts, prompt)
			if calls == 1 {
				return `{"items":[{"text":"wrong id","quote_id":"missing"}]}`, nil
			}
			return `{"items":[{"text":"The objection remains unresolved","quote_id":"p1.1"}]}`, nil
		},
	}
	s := &Session{Topic: "持续推进", ID: "quote-ids", Seats: []string{"chair"}, Continuous: &ContinuousState{Checkpoint: &ContinuousCheckpoint{ThroughRound: 1, Items: []ContinuousItem{{Text: "Objection remains", Round: 1, Seat: "pro", Quote: "I still object."}}}}, Rounds: []Round{
		{Number: 1, Turns: []Turn{{Seat: "pro", Status: "done", Text: "I still object."}}},
		{Number: 2, Auto: true, Turns: []Turn{{Seat: "chair", Status: "done", Text: "Nothing changed."}}, Settings: Settings{Models: map[string]string{"chair": "summary-model"}, Timeout: 30}},
	}}
	got, err := e.summarizeContinuous(context.Background(), s, 2)
	if err != nil {
		t.Fatal(err)
	}
	if calls != 2 || len(got.Items) != 1 || got.Items[0].Round != 1 || got.Items[0].Seat != "pro" || got.Items[0].Quote != "I still object." || got.Items[0].QuoteID != "" {
		t.Fatalf("quote_id was not restored to a canonical citation: calls=%d items=%+v", calls, got.Items)
	}
	if !strings.Contains(prompts[0], `"id":"p1.1"`) || !strings.Contains(prompts[0], "quote_options") || !strings.Contains(prompts[1], "格式修正") {
		t.Fatal("prompt omitted deterministic quote candidates or one-time corrective feedback")
	}
}

func TestSummarizeContinuousDoesNotRetryInvocationErrors(t *testing.T) {
	calls := 0
	e := &Engine{settings: func() Settings { return Settings{} }, call: func(context.Context, string, string, string, string) (string, error) {
		calls++
		return "", context.Canceled
	}}
	s := &Session{ID: "cancelled-summary", Seats: []string{"chair"}, Continuous: &ContinuousState{}, Rounds: []Round{
		{Number: 1, Turns: []Turn{{Seat: "chair", Status: "done", Text: "A completed statement."}}, Settings: Settings{Models: map[string]string{"chair": "summary-model"}, Timeout: 30}},
	}}
	if _, err := e.summarizeContinuous(context.Background(), s, 1); !errors.Is(err, context.Canceled) || calls != 1 {
		t.Fatalf("invocation error was retried or lost: calls=%d err=%v", calls, err)
	}
}
