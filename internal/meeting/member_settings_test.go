package meeting

import (
	"context"
	"errors"
	"fmt"
	"slices"
	"strings"
	"testing"
	"time"
)

func changeSeatForTest(e *Engine, id, seat, model, effort string, version int) (*Session, error) {
	return e.ChangeMember(id, MemberChange{SeatID: seat, Model: model, Effort: effort, ExpectedVersion: &version}, func() (Member, error) {
		return Member{Model: model, Effort: effort, Label: "Name " + model, Source: "catalog"}, nil
	})
}

func TestSeatSettingsRoundNamespacesAndHistoricalAttribution(t *testing.T) {
	type invocation struct{ model, effort, session string }
	calls := make(chan invocation, 8)
	e, project := engine(t, func(ctx context.Context, seat, model, prompt, _ string) (string, error) {
		effort, key := ModelRequest(ctx)
		calls <- invocation{model, effort, key}
		if strings.HasPrefix(prompt, "AGENDA DRAFT REQUEST") {
			return `{"board":{"title":"Chair title","modules":[{"kind":"note","title":"Keep","body":"Initial finding"}]}}`, nil
		}
		return fmt.Sprintf(`{"action":"say","text":"Public observation.","board_updates":[{"op":"rename_board","title":"Round by %s %s"}]}`, model, effort), nil
	})
	s, err := e.CreateConfigured("Switch seats", project, []Member{{Model: "A", Label: "Name A", Source: "catalog", Effort: "low"}, {Model: "A", Label: "Name A", Source: "catalog", Effort: "low"}}, "review")
	if err != nil {
		t.Fatal(err)
	}
	if _, err = e.StartAgendaDraft(s.ID, &s.AgendaVersion); err != nil {
		t.Fatal(err)
	}
	s = waitForAgenda(t, e, s.ID)
	if s.Board.Model != "A" || s.Board.ModelLabel != "Name A" || s.Board.Modules[0].Model != "A" || (<-calls).model != "A" {
		t.Fatal(s.Board)
	}
	run := func(e *Engine, n int) invocation {
		t.Helper()
		if _, err := e.StartWithDiscussion(s.ID, "Discuss", "member-1", n, "review", "proposal"); err != nil {
			t.Fatal(err)
		}
		s = settled(t, e, s.ID)
		if s.Status != "ready" {
			t.Fatal(s.Rounds[len(s.Rounds)-1])
		}
		select {
		case c := <-calls:
			return c
		case <-time.After(time.Second):
			t.Fatal("missing model request")
			return invocation{}
		}
	}
	original := run(e, 0)
	firstTurn := s.Rounds[0].Turns[0]
	s, err = changeSeatForTest(e, s.ID, "member-1", "A", "high", 0)
	if err != nil || s.Members[0].Version != 1 || s.Members[0].ModelEpoch != 0 {
		t.Fatal(s, err)
	}
	if c := run(e, 1); c.session != original.session || c.effort != "high" {
		t.Fatal(c, original)
	}
	s, err = changeSeatForTest(e, s.ID, "member-1", "B", "auto", 1)
	if err != nil || s.Members[0].PreviousModel != "A" || s.Members[0].ModelEpoch != 1 || s.Members[0].SwitchedAfterRound != 2 || s.Members[1].Version != 0 {
		t.Fatal(s, err)
	}
	same, err := changeSeatForTest(e, s.ID, "member-1", "B", "auto", 1)
	if err != nil || same.UpdatedAt != s.UpdatedAt {
		t.Fatal("retry was not idempotent", same, err)
	}
	conflict, err := changeSeatForTest(e, s.ID, "member-1", "A", "low", 0)
	if !errors.Is(err, ErrConflict) || conflict.Members[0].Model != "B" {
		t.Fatal("stale writer did not receive winning configuration", conflict, err)
	}
	reopen, err := New(e.dir, e.call, testSettings)
	if err != nil {
		t.Fatal(err)
	}
	b := run(reopen, 2)
	if b.model != "B" || b.effort != "auto" || b.session == original.session || s.Board.Model != "B" || s.Board.ModelLabel != "Name B" || s.Board.Modules[0].Model != "A" {
		t.Fatal(b, s.Board)
	}
	if t1 := s.Rounds[0].Turns[0]; t1.Model != firstTurn.Model || t1.ModelLabel != firstTurn.ModelLabel || t1.Effort != "low" || t1.Seat != "member-1" {
		t.Fatal("historical attribution moved", t1)
	}
	s, err = changeSeatForTest(reopen, s.ID, "member-1", "A", "low", 2)
	if err != nil {
		t.Fatal(err)
	}
	a2 := run(reopen, 3)
	if a2.session == original.session || a2.session == b.session || s.Members[0].ModelEpoch != 2 || s.Members[0].PreviousModel != "B" || s.Members[0].SwitchedAfterRound != 3 {
		t.Fatal("switch-back resumed a previous private session", s.Members, a2)
	}
}

func TestLegacySeatOverridePreservesOtherDefaultsAndExactCatalogAliases(t *testing.T) {
	e, project := engine(t, func(context.Context, string, string, string, string) (string, error) {
		return "", errors.New("unexpected completion")
	})
	e.settings = func() Settings {
		v := testSettings()
		v.Models["codex"] = "main"
		v.Efforts = map[string]string{"codex": "low", "cursor": "medium"}
		return v
	}
	s, err := e.Create("Old archive", project, []string{"codex", "cursor"})
	if err != nil {
		t.Fatal(err)
	}
	members, err := e.SessionMembers(s.ID)
	if err != nil || len(members) != 2 || members[0].Model != "codex/main" || members[1].Effort != "medium" {
		t.Fatal(members, err)
	}
	s, err = changeSeatForTest(e, s.ID, "codex", "catalog-alias", "high", 0)
	if err != nil || len(s.Members) != 0 || len(s.SeatOverrides) != 1 || s.SeatOverrides["codex"].ModelEpoch != 1 || !slices.Equal(s.Seats, []string{"codex", "cursor"}) {
		t.Fatal(s, err)
	}
	settings, err := e.snapshotSettings(s)
	if err != nil || settings.Models["codex"] != "catalog-alias" || settings.ChildModels["codex"] != "catalog-alias" || settings.Efforts["codex"] != "high" || settings.Models["cursor"] != "cursor/main" || settings.ChildModels["cursor"] != "cursor/child" || settings.Efforts["cursor"] != "medium" {
		t.Fatal(settings, err)
	}
	e.call = func(ctx context.Context, seat, model, prompt, exe string) (string, error) {
		if (CatalogModelID(ctx, seat, "alias") == "alias") != (seat == "codex") {
			return "", errors.New("catalog alias routing changed unrelated legacy seat")
		}
		return say("Done"), nil
	}
	if _, err := e.Start(s.ID, "test", "", 0); err != nil {
		t.Fatal(err)
	}
	s = settled(t, e, s.ID)
	if s.Status != "ready" || s.Rounds[0].Turns[0].Model != "catalog-alias" || s.Rounds[0].Turns[1].Model != "cursor/main" {
		t.Fatal(s.Rounds)
	}
}

func TestSeatChangeRechecksMeetingBoundaryAfterCatalogResponses(t *testing.T) {
	callEntered, resume := make(chan struct{}), make(chan struct{})
	e, project := engine(t, func(ctx context.Context, _, _, _, _ string) (string, error) {
		close(callEntered)
		select {
		case <-resume:
			return say("Done"), nil
		case <-ctx.Done():
			return "", ctx.Err()
		}
	})
	s, err := e.CreateConfigured("Interleaved edit", project, []Member{{Model: "A"}}, "review")
	if err != nil {
		t.Fatal(err)
	}
	validating, answer := make(chan struct{}), make(chan struct{})
	result := make(chan error, 1)
	zero := 0
	go func() {
		_, err := e.ChangeMember(s.ID, MemberChange{"member-1", "B", "auto", &zero}, func() (Member, error) {
			close(validating)
			<-answer
			return Member{Model: "B", Effort: "auto"}, nil
		})
		result <- err
	}()
	<-validating
	if _, err = e.Start(s.ID, "go", "", 0); err != nil {
		t.Fatal(err)
	}
	<-callEntered
	close(answer)
	if err := <-result; !errors.Is(err, ErrConflict) {
		t.Fatal("catalog response changed a running seat", err)
	}
	close(resume)
	s = settled(t, e, s.ID)
	if s.Members[0].Model != "A" || s.Rounds[0].Turns[0].Model != "A" {
		t.Fatal(s.Members, s.Rounds)
	}
	for _, state := range []string{"drafting", "closed"} {
		if err = e.locked(func() error {
			if state == "closed" {
				s.Status = "closed"
				s.AgendaDraftStatus = "ready"
			} else {
				s.AgendaDraftStatus = "drafting"
			}
			return e.save(s)
		}); err != nil {
			t.Fatal(err)
		}
		var cleanup func()
		if state == "drafting" {
			lease, err := e.lease(s.ID)
			if err != nil || lease == nil {
				t.Fatal(err)
			}
			cleanup = func() { release(lease) }
		}
		_, err = e.ChangeMember(s.ID, MemberChange{"member-1", "B", "auto", &zero}, func() (Member, error) { t.Fatal("looked up the catalog for a read-only session"); return Member{}, nil })
		if cleanup != nil {
			cleanup()
		}
		if !errors.Is(err, ErrConflict) {
			t.Fatal(state, err)
		}
	}
}

func TestArchivedLegacyRosterUsesActualRoundModels(t *testing.T) {
	e, project := engine(t, func(context.Context, string, string, string, string) (string, error) {
		return "", errors.New("unexpected request")
	})
	s, err := e.Create("Read history", project, nil)
	if err != nil {
		t.Fatal(err)
	}
	s.Status = "closed"
	s.Rounds = []Round{{Number: 1, Settings: Settings{Models: map[string]string{"codex": "archived"}, Efforts: map[string]string{"codex": "low"}}, Turns: []Turn{{Seat: "codex", Status: "done", Text: "Historical statement"}}}}
	if err = e.locked(func() error { return e.save(s) }); err != nil {
		t.Fatal(err)
	}
	roster, err := e.SessionMembers(s.ID)
	if err != nil || len(roster) != 2 || roster[0].Model != "codex/archived" || roster[0].Effort != "low" || roster[1].Model != "" {
		t.Fatal(roster, err)
	}
}

func TestSeatSwitchWithdrawsAnOutstandingTitleFromThePreviousChair(t *testing.T) {
	entered, answer := make(chan struct{}), make(chan struct{})
	e, project := engine(t, func(ctx context.Context, _, model, _, _ string) (string, error) {
		if model == "A" {
			close(entered)
			select {
			case <-answer:
				return "Stale title", nil
			case <-ctx.Done():
				return "", ctx.Err()
			}
		}
		return "New title", nil
	})
	s, err := e.CreateConfigured("Concurrent naming", project, []Member{{Model: "A"}}, "review")
	if err != nil {
		t.Fatal(err)
	}
	result := make(chan error, 1)
	go func() { _, err := e.GenerateTitle(context.Background(), s.ID); result <- err }()
	<-entered
	if _, err := changeSeatForTest(e, s.ID, "member-1", "B", "auto", 0); err != nil {
		t.Fatal(err)
	}
	close(answer)
	if err := <-result; !errors.Is(err, ErrConflict) {
		t.Fatal("late previous chair title accepted", err)
	}
	name, err := e.GenerateTitle(context.Background(), s.ID)
	if err != nil || name != "New title" {
		t.Fatal(name, err)
	}
}
