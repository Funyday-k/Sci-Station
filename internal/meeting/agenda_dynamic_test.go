package meeting

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"scistation.local/desktop/internal/deliberation"
)

func waitForAgenda(t *testing.T, e *Engine, id string) *Session {
	t.Helper()
	for until := time.Now().Add(3 * time.Second); time.Now().Before(until); {
		s, err := e.Get(id)
		if err != nil {
			t.Fatal(err)
		}
		if s.AgendaDraftStatus != "drafting" {
			return s
		}
		time.Sleep(time.Millisecond)
	}
	t.Fatal("agenda draft did not settle")
	return nil
}

func TestAgendaDraftFirstChairIsolationRetriesAndRecovery(t *testing.T) {
	entered, resume := make(chan struct{}), make(chan struct{})
	var calls atomic.Int32
	call := func(ctx context.Context, seat, model, prompt, _ string) (string, error) {
		n := calls.Add(1)
		if seat != "member-1" || model != "first" || !strings.HasPrefix(prompt, "AGENDA DRAFT REQUEST") || !strings.Contains(prompt, "rollout latency") || strings.Contains(prompt, "PROJECT_PRIVATE_REFERENCE") || !strings.Contains(deliberation.InstructionsFrom(ctx), "Never execute work") {
			return "", errors.New("wrong model, data or permissions")
		}
		switch n {
		case 1:
			close(entered)
			<-resume
			return `{"action":"write","path":"unexpected.md","text":"bad"}`, nil
		case 2:
			return `{"agenda":[{"title":"Measure rollout latency at peak traffic","kind":"implementation"},{"title":"Test a rolling restart","kind":"implementation"},{"title":"Test a rolling restart","kind":"discussion"}]}`, nil
		}
		return "", errors.New("duplicate call")
	}
	e, project := engine(t, call)
	e.SetProjectContext(func(string) string { return "PROJECT_PRIVATE_REFERENCE" })
	s, err := e.CreateConfigured("Investigate rollout latency", project, []Member{{Model: "first"}, {Model: "second"}}, "review")
	if err != nil || len(s.Agenda) != 0 || s.AgendaDraftStatus != "pending" {
		t.Fatalf("new session was seeded with boilerplate: %+v %v", s, err)
	}
	started, err := e.StartAgendaDraft(s.ID, &s.AgendaVersion)
	if err != nil {
		t.Fatal(err)
	}
	select {
	case <-entered:
	case <-time.After(time.Second):
		t.Fatal("chair not invoked")
	}
	other, err := New(e.dir, call, testSettings)
	if err != nil {
		t.Fatal(err)
	}
	dup, err := other.StartAgendaDraft(s.ID, &s.AgendaVersion)
	if err != nil || dup.AgendaDraftStatus != "drafting" || calls.Load() != 1 {
		t.Fatal("duplicate draft", err)
	}
	if _, err = other.StartWithDiscussion(s.ID, "", "", 0, "review", "proposal"); !errors.Is(err, ErrConflict) {
		t.Fatal("round began before agenda settled", err)
	}
	if _, err = other.ChangeAgenda(s.ID, AgendaChange{Action: "add", AgendaInput: AgendaInput{"host item", "discussion"}, ExpectedVersion: &started.AgendaVersion}); !errors.Is(err, ErrConflict) {
		t.Fatal("draft allowed concurrent agenda change", err)
	}
	close(resume)
	s = waitForAgenda(t, e, s.ID)
	if s.AgendaDraftStatus != "failed" || s.AgendaDraftError == "" || len(s.Agenda) != 0 || len(s.Operations) != 0 {
		t.Fatalf("invalid draft had effects: %+v", s)
	}
	if _, err = other.StartAgendaDraft(s.ID, &started.AgendaVersion); !errors.Is(err, ErrConflict) {
		t.Fatal("stale retry accepted", err)
	}
	if _, err = other.StartAgendaDraft(s.ID, &s.AgendaVersion); err != nil {
		t.Fatal(err)
	}
	s = waitForAgenda(t, e, s.ID)
	if s.AgendaDraftStatus != "ready" || s.AgendaDraftError != "" || len(s.Agenda) != 2 || s.ActiveAgendaID != s.Agenda[0].ID || s.Agenda[0].Kind != "discussion" || s.Agenda[0].SourceSeat != "member-1" || s.Agenda[1].Kind != "implementation" || len(s.Rounds) != 0 {
		t.Fatalf("bad generated agenda: %+v", s)
	}
	if _, err = e.StartAgendaDraft(s.ID, &s.AgendaVersion); err != nil || calls.Load() != 2 {
		t.Fatal("regenerated an existing draft", err)
	}
	// Simulate a saved drafting status left by a dead application. No run
	// lease is held. A new process should expose retry and allow normal rounds.
	s.AgendaDraftStatus = "drafting"
	if err = e.locked(func() error { return e.save(s) }); err != nil {
		t.Fatal(err)
	}
	reopened, err := New(e.dir, call, testSettings)
	if err != nil {
		t.Fatal(err)
	}
	s, err = reopened.Get(s.ID)
	if err != nil || s.AgendaDraftStatus != "failed" || len(s.Agenda) != 2 || calls.Load() != 2 {
		t.Fatal("abandoned draft was blocked or replayed", err)
	}
}

func TestAgendaDraftKeepsHostItemsAndCancelsOnShutdown(t *testing.T) {
	var calls atomic.Int32
	blocked := make(chan struct{})
	e, project := engine(t, func(ctx context.Context, _, _, p, _ string) (string, error) {
		if calls.Add(1) == 1 {
			if !strings.Contains(p, "Preserve timing notes") {
				return "", errors.New("lost host agenda")
			}
			return `{"agenda":[]}`, nil
		}
		close(blocked)
		<-ctx.Done()
		return `{"agenda":[{"title":"Late addition","kind":"implementation"}]}`, nil
	})
	members := []Member{{Model: "chair"}}
	s, err := e.CreateConfigured("Audit timing", project, members, "work", AgendaInput{"Preserve timing notes", "discussion"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err = e.StartAgendaDraft(s.ID, &s.AgendaVersion); err != nil {
		t.Fatal(err)
	}
	s = waitForAgenda(t, e, s.ID)
	if s.AgendaDraftStatus != "ready" || len(s.Agenda) != 1 || s.Agenda[0].Source != "host" {
		t.Fatal("host items replaced or treated as failed")
	}
	next, err := e.CreateConfigured("Audit scheduling", project, members, "work")
	if err != nil {
		t.Fatal(err)
	}
	if _, err = e.StartAgendaDraft(next.ID, &next.AgendaVersion); err != nil {
		t.Fatal(err)
	}
	select {
	case <-blocked:
	case <-time.After(time.Second):
		t.Fatal("draft did not start")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	if err = e.Shutdown(ctx); err != nil {
		t.Fatal(err)
	}
	next, err = e.Get(next.ID)
	if err != nil || next.AgendaDraftStatus != "failed" || len(next.Agenda) != 0 {
		t.Fatal("shutdown published late draft", err)
	}
}

func TestAgendaDiscussionUsesHostEvidenceAndMergesPublicChanges(t *testing.T) {
	var target, doneID, queued string
	var calls atomic.Int32
	call := func(ctx context.Context, seat, _, prompt, _ string) (string, error) {
		calls.Add(1)
		data, err := discussionContext(prompt)
		if err != nil {
			return "", err
		}
		if !strings.Contains(deliberation.InstructionsFrom(ctx), "agenda_updates") || !strings.Contains(prompt, "change cutoff to 200 ms") || !strings.Contains(prompt, queued) {
			return "", errors.New("missing host instruction or editable queue IDs")
		}
		if data["round"].(float64) == 2 {
			if !strings.Contains(prompt, "trace jitter") || !strings.Contains(prompt, "200 ms") {
				return "", errors.New("lost prior public exchange")
			}
			return fmt.Sprintf(`{"action":"say","text":"The earlier measurements also require low-load data.","agenda_updates":[{"op":"revise","item_id":"%s","title":"Trace jitter under low load","reason":"Earlier measurements omitted low load."}]}`, queued), nil
		}
		if seat == "member-1" {
			return fmt.Sprintf(`{"action":"say","text":"The host now requires 200 ms. The pilot found trace jitter.","agenda_updates":[{"op":"revise","item_id":"%s","title":"Compare traces at the 200 ms cutoff","kind":"implementation","reason":"The host requested 200 ms."},{"op":"add","title":"Measure tail latency","kind":"discussion","reason":"The pilot found trace jitter."},{"op":"complete","item_id":"%s","title":"force done","reason":"no"},{"op":"revise","item_id":"%s","title":"rewrite a completed item","reason":"no"}]}`, target, target, doneID), nil
		}
		if strings.Contains(prompt, "The pilot found trace jitter") {
			return "", errors.New("blind proposal leaked")
		}
		if seat == "member-2" {
			return fmt.Sprintf(`{"action":"say","text":"Measure disk load as well.","agenda_updates":[{"op":"revise","item_id":"%s","title":"Competing overwrite","reason":"Independent view."},{"op":"add","title":"Measure tail latency","kind":"discussion","reason":"Independent overlap."},{"op":"add","title":"Isolate disk load","reason":"Disk load could affect timing."}]}`, target), nil
		}
		return fmt.Sprintf(`{"action":"say","text":"Keep the issue focused on the cutoff.","agenda_updates":[{"op":"revise","item_id":"%s","title":"Measure the cutoff independently","reason":"A separate view of the same scope."}]}`, target), nil
	}
	e, project := engine(t, call)
	s, err := e.CreateConfigured("Compare cutoff timing", project, []Member{{Model: "first"}, {Model: "second"}, {Model: "third"}}, "review", AgendaInput{"Compare traces", "discussion"}, AgendaInput{"Collect workload traces", "discussion"}, AgendaInput{"Closed scope", "discussion"})
	if err != nil {
		t.Fatal(err)
	}
	target, queued, doneID = s.Agenda[0].ID, s.Agenda[1].ID, s.Agenda[2].ID
	s, err = e.ChangeAgenda(s.ID, AgendaChange{Action: "complete", ItemID: doneID, ExpectedVersion: &s.AgendaVersion})
	if err != nil {
		t.Fatal(err)
	}
	if _, err = e.StartWithDiscussion(s.ID, "change cutoff to 200 ms", "", 0, "review", "proposal"); err != nil {
		t.Fatal(err)
	}
	s = settled(t, e, s.ID)
	if s.Status != "ready" || len(s.Agenda) != 5 || s.Agenda[0].Kind != "discussion" || s.Agenda[0].Title != "Compare traces at the 200 ms cutoff" || s.ActiveAgendaID != target || s.Agenda[2].Status != "done" || s.Agenda[2].Title != "Closed scope" {
		t.Fatalf("invalid merged agenda: %+v %+v", s.Agenda, s.Rounds)
	}
	rev := s.Agenda[0].Revisions
	if len(rev) != 1 || rev[0].Seat != "member-1" || rev[0].Round != 1 || rev[0].PreviousTitle != "Compare traces" || rev[0].Reason == "" {
		t.Fatal(rev)
	}
	if s.Agenda[4].Source != "discussion" || s.Agenda[4].SourceRound != 1 || s.Agenda[4].SourceSeat != "member-2" || s.Agenda[4].Reason == "" {
		t.Fatal(s.Agenda[4])
	}
	candidates := s.Agenda[0].Candidates
	if len(candidates) != 2 || candidates[0].Title != "Competing overwrite" || candidates[0].Seat != "member-2" || candidates[1].Title != "Measure the cutoff independently" || candidates[1].Seat != "member-3" {
		t.Fatalf("same-round losing revisions were not retained: %+v", candidates)
	}
	staleVersion := s.AgendaVersion - 1
	if _, err = e.ChangeAgenda(s.ID, AgendaChange{Action: "adopt_candidate", ItemID: target, CandidateID: candidates[0].ID, ExpectedVersion: &staleVersion}); !errors.Is(err, ErrConflict) {
		t.Fatalf("stale candidate decision accepted: %v", err)
	}
	s, err = e.ChangeAgenda(s.ID, AgendaChange{Action: "adopt_candidate", ItemID: target, CandidateID: candidates[0].ID, ExpectedVersion: &s.AgendaVersion})
	if err != nil || s.Agenda[0].Title != "Competing overwrite" || len(s.Agenda[0].Candidates) != 1 || len(s.Agenda[0].Revisions) != 2 || s.Agenda[0].Revisions[1].Seat != "member-2" {
		t.Fatalf("host could not adopt competing revision: %+v %v", s.Agenda[0], err)
	}
	candidateID := s.Agenda[0].Candidates[0].ID
	s, err = e.ChangeAgenda(s.ID, AgendaChange{Action: "dismiss_candidate", ItemID: target, CandidateID: candidateID, ExpectedVersion: &s.AgendaVersion})
	if err != nil || len(s.Agenda[0].Candidates) != 0 {
		t.Fatalf("host could not dismiss remaining candidate: %+v %v", s.Agenda[0], err)
	}
	if _, err = e.StartWithDiscussion(s.ID, "", "member-2", 1, "review", "challenge"); err != nil {
		t.Fatal(err)
	}
	s = settled(t, e, s.ID)
	if s.Status != "ready" || s.Agenda[1].Title != "Trace jitter under low load" || len(s.Agenda[1].Revisions) != 1 || s.Agenda[1].Revisions[0].Round != 2 || calls.Load() != 4 {
		t.Fatalf("round 2 failed: %+v %+v", s.Agenda, s.Rounds[1])
	}
}

func TestAgendaUpdatesFromPartialRoundAreDiscarded(t *testing.T) {
	e, project := engine(t, func(_ context.Context, seat, _, _, _ string) (string, error) {
		if seat == "member-2" {
			return "", errors.New("fixture second seat failed")
		}
		return `{"action":"say","text":"Consider disk load.","agenda_updates":[{"op":"add","title":"Check disk load","kind":"discussion","reason":"The timing varies across disks."}]}`, nil
	})
	s, err := e.CreateConfigured("Compare timing", project, []Member{{Model: "one"}, {Model: "two"}}, "review", AgendaInput{"Baseline", "discussion"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err = e.StartWithDiscussion(s.ID, "", "", 0, "review", "proposal"); err != nil {
		t.Fatal(err)
	}
	s = settled(t, e, s.ID)
	if s.Status != "partial" || len(s.Agenda) != 1 || len(s.Rounds[0].Turns[0].ProposedAgendaUpdates) != 0 {
		t.Fatal("partial round published a pending update")
	}
}
