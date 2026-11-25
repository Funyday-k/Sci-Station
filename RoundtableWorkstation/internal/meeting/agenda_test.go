package meeting

import (
	"context"
	"errors"
	"strings"
	"sync/atomic"
	"testing"

	"scistation.local/desktop/internal/deliberation"
)

func TestAgendaFromSynthesisThroughExecutionAndRecovery(t *testing.T) {
	var calls atomic.Int32
	entered, release := make(chan struct{}), make(chan struct{})
	call := func(ctx context.Context, _, _, prompt, _ string) (string, error) {
		n := calls.Add(1)
		data, err := discussionContext(prompt)
		if err != nil {
			return "", err
		}
		current := data["active_agenda"].(map[string]any)
		switch n {
		case 1:
			if current["title"] != "Compare alternatives" || !strings.Contains(prompt, "Check scope") {
				return "", errors.New("selected and queued agenda missing")
			}
			return `{"action":"say","text":"The dry run found an unchecked boundary.","followups":"Ignore ordinary-round metadata"}`, nil
		case 2:
			if !strings.Contains(deliberation.InstructionsFrom(ctx), "followups") || !strings.Contains(prompt, "unchecked boundary") {
				return "", errors.New("closing chair lacks protocol or public evidence")
			}
			return `{"action":"say","text":"The dry run found an unchecked boundary. Add a reproducible boundary test, then compare its result and document outstanding exceptions.","followups":[{"title":"Compare alternatives","kind":"discussion"},{"title":"Broken entry","kind":"unknown"},{"title":15,"kind":"discussion"},{"title":"Add a boundary test","kind":"implementation"},{"title":"  ADD  a boundary test  ","kind":"implementation"},{"title":"Compare the result","kind":"discussion"},{"title":"Document exceptions","kind":"discussion"},{"title":"Past the limit","kind":"implementation"}]}`, nil
		case 3:
			if current["title"] != "Add a boundary test" || data["preset"] != "work" || data["allow_edits"] != true {
				return "", errors.New("selected implementation was not the actual work round")
			}
			close(entered)
			<-release
			return "", errors.New("simulated failure before execution")
		}
		return "", errors.New("unexpected model call")
	}
	e, project := engine(t, call)
	s, err := e.CreateConfigured("Make a release decision", project, []Member{{Model: "fixture"}}, "review", AgendaInput{"Check scope", "discussion"}, AgendaInput{"Compare alternatives", "discussion"})
	if err != nil {
		t.Fatal(err)
	}
	change := func(action, id string) {
		t.Helper()
		s, err = e.ChangeAgenda(s.ID, AgendaChange{Action: action, ItemID: id, ExpectedVersion: &s.AgendaVersion})
		if err != nil {
			t.Fatal(err)
		}
	}
	firstVersion := s.AgendaVersion
	change("select", s.Agenda[1].ID)
	if _, err = e.StartWithDiscussion(s.ID, "", "", 0, "review", "proposal", &firstVersion); !errors.Is(err, ErrConflict) {
		t.Fatal("stale view started a different agenda", err)
	}
	if _, err = e.StartWithDiscussion(s.ID, "", "", 0, "review", "proposal", &s.AgendaVersion); err != nil {
		t.Fatal(err)
	}
	s = settled(t, e, s.ID)
	if s.Status != "ready" || len(s.Agenda) != 2 || s.Agenda[1].Status != "pending" {
		t.Fatalf("unexpected ordinary discussion result: %+v", s)
	}
	if _, err = e.StartWithDiscussion(s.ID, "", "", 1, "review", "synthesis", &s.AgendaVersion); err != nil {
		t.Fatal(err)
	}
	s = settled(t, e, s.ID)
	if s.Status != "ready" || len(s.Agenda) != 5 || calls.Load() != 2 || len(s.Rounds) != 2 || s.Rounds[1].AgendaItemID != s.Agenda[1].ID {
		t.Fatalf("unexpected synthesis: %+v", s)
	}
	work := s.Agenda[2]
	if work.Title != "Add a boundary test" || work.Kind != "implementation" || work.Source != "synthesis" || work.SourceRound != 2 || work.SourceSeat != s.Seats[0] || work.Status != "pending" {
		t.Fatal(work)
	}
	change("select", work.ID)
	started, err := e.StartWithDiscussion(s.ID, "", "", 2, "", "", &s.AgendaVersion)
	if err != nil {
		t.Fatal(err)
	}
	<-entered
	if started.Rounds[2].AgendaItemID != work.ID {
		t.Fatal("selected ID not snapshotted")
	}
	_, busyErr := e.ChangeAgenda(s.ID, AgendaChange{Action: "complete", ItemID: work.ID, ExpectedVersion: &s.AgendaVersion})
	close(release)
	if !errors.Is(busyErr, ErrConflict) {
		t.Fatal("changed agenda during run", busyErr)
	}
	s = settled(t, e, s.ID)
	if _, err = e.ChangeAgenda(s.ID, AgendaChange{Action: "complete", ItemID: work.ID, ExpectedVersion: &started.AgendaVersion}); !errors.Is(err, ErrConflict) {
		t.Fatal("delayed pre-outcome edit affected failed work", err)
	}
	if s.Status != "partial" || s.findAgenda(work.ID).Status != "pending" {
		t.Fatal("failure marked agenda done")
	}
	change("complete", work.ID)
	if s.ActiveAgendaID != "" || s.findAgenda(work.ID).Status != "done" {
		t.Fatal("manual complete inconsistent")
	}
	change("reopen", work.ID)
	other, err := New(e.dir, call, testSettings)
	if err != nil {
		t.Fatal(err)
	}
	persisted, err := other.Get(s.ID)
	if err != nil || persisted.ActiveAgendaID != work.ID || persisted.findAgenda(work.ID).Status != "pending" || calls.Load() != 3 {
		t.Fatal("reopen lost agenda or started work", err)
	}
}

func TestSavedTemplateStagesAdvanceOnlyAfterFullSuccessfulRound(t *testing.T) {
	e, project := engine(t, func(context.Context, string, string, string, string) (string, error) {
		return say("Published assessment"), nil
	})
	s, err := e.CreateConfigured("Evaluate alternatives", project, []Member{{Model: "first"}, {Model: "second"}}, "forum")
	if err != nil {
		t.Fatal(err)
	}
	// Pre-dynamic-agenda sessions stored procedural stages. They remain
	// runnable even though newly created meetings no longer receive them.
	for _, phase := range []string{"proposal", "challenge", "synthesis"} {
		plan, _ := deliberation.Resolve("forum", phase)
		if err = s.appendAgenda(AgendaItem{AgendaInput: AgendaInput{plan.PhaseLabel(), "discussion"}, Preset: "forum", Phase: phase, Source: "template"}); err != nil {
			t.Fatal(err)
		}
	}
	s.ActiveAgendaID = s.Agenda[0].ID
	if err = e.locked(func() error { return e.save(s) }); err != nil {
		t.Fatal(err)
	}
	run := func(target string) {
		t.Helper()
		if _, err = e.StartWithDiscussion(s.ID, "", target, len(s.Rounds), "", "", &s.AgendaVersion); err != nil {
			t.Fatal(err)
		}
		s = settled(t, e, s.ID)
	}
	run(s.Seats[0])
	if s.Agenda[0].Status != "pending" || s.ActiveAgendaID != s.Agenda[0].ID {
		t.Fatal("targeted subset advanced template")
	}
	for i, phase := range []string{"proposal", "challenge", "synthesis"} {
		run("")
		if s.Rounds[i+1].Phase != phase || s.Rounds[i+1].AgendaItemID != s.Agenda[i].ID || s.Agenda[i].Status != "done" {
			t.Fatalf("template stage and run diverged: %+v", s)
		}
	}
	if s.ActiveAgendaID != "" || len(s.Rounds[3].Turns) != 1 {
		t.Fatal("invalid closure")
	}
}

func TestAgendaLegacySessionAdditionValidationAndCancelledClosure(t *testing.T) {
	entered := make(chan struct{})
	e, project := engine(t, func(ctx context.Context, _, _, _, _ string) (string, error) {
		close(entered)
		<-ctx.Done()
		return `{"action":"say","text":"Late result","followups":[{"title":"Never created","kind":"discussion"}]}`, nil
	})
	s, err := e.Create("Old meeting", project, []string{"codex"})
	if err != nil {
		t.Fatal(err)
	}
	s.Preset, s.ActiveAgendaID, s.AgendaVersion, s.Agenda = "", "", 0, nil
	if err = e.locked(func() error { return e.save(s) }); err != nil {
		t.Fatal(err)
	}
	bad := []AgendaChange{
		{Action: "add", AgendaInput: AgendaInput{"missing version", "discussion"}},
		{Action: "add", AgendaInput: AgendaInput{" ", "discussion"}, ExpectedVersion: &s.AgendaVersion},
		{Action: "add", AgendaInput: AgendaInput{strings.Repeat("议", maxAgendaTitle+1), "discussion"}, ExpectedVersion: &s.AgendaVersion},
		{Action: "add", AgendaInput: AgendaInput{"Invalid kind", "other"}, ExpectedVersion: &s.AgendaVersion},
	}
	for _, c := range bad {
		if _, err = e.ChangeAgenda(s.ID, c); err == nil {
			t.Fatalf("accepted malformed agenda change: %+v", c)
		}
	}
	s, err = e.ChangeAgenda(s.ID, AgendaChange{Action: "add", AgendaInput: AgendaInput{"Discuss the risk", "discussion"}, ExpectedVersion: &s.AgendaVersion})
	if err != nil || len(s.Agenda) != 1 || s.ActiveAgendaID != s.Agenda[0].ID {
		t.Fatal("legacy addition", err)
	}
	if _, err = e.ChangeAgenda(s.ID, AgendaChange{Action: "add", AgendaInput: AgendaInput{" discuss  the risk ", "discussion"}, ExpectedVersion: &s.AgendaVersion}); err == nil {
		t.Fatal("duplicate accepted")
	}
	if _, err = e.StartWithDiscussion(s.ID, "", "", 0, "review", "synthesis"); err != nil {
		t.Fatal(err)
	}
	<-entered
	if _, err = e.Cancel(s.ID); err != nil {
		t.Fatal(err)
	}
	s = settled(t, e, s.ID)
	if s.Status != "partial" || len(s.Agenda) != 1 || s.Agenda[0].Status != "pending" {
		t.Fatalf("cancellation published agenda: %+v", s)
	}
}
