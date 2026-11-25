package meeting

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"
)

func hostEdit(t *testing.T, e *Engine, id, raw string) (*Session, error) {
	t.Helper()
	var change HostBoardChange
	if err := json.Unmarshal([]byte(raw), &change); err != nil {
		t.Fatal(err)
	}
	return e.ChangeBoard(id, change)
}

func TestHostBoardIndependentVersionsAndRecovery(t *testing.T) {
	call := func(context.Context, string, string, string, string) (string, error) {
		t.Fatal("host edits called a model")
		return "", nil
	}
	e, project := engine(t, call)
	m, err := e.StoreMaterial("notes.txt", strings.NewReader("test source"))
	if err != nil {
		t.Fatal(err)
	}
	s, err := e.CreateConfiguredWithMaterials("Board topic", project, []Member{{Model: "first"}}, "review", nil, []string{m.ID}, AgendaInput{Title: "Original question", Kind: "discussion"})
	if err != nil {
		t.Fatal(err)
	}
	other, err := New(e.dir, call, testSettings)
	if err != nil {
		t.Fatal(err)
	}
	if err := e.locked(func() error {
		s.Rounds = []Round{{Number: 1, Turns: []Turn{{Seat: "first", Status: "done", Text: "Original", Points: []DiscussionPoint{{ID: "point", Text: "Original"}}, Positions: []Position{{PointID: "point", Stance: "qualified", Reason: "Original"}}}}}}
		return e.save(s)
	}); err != nil {
		t.Fatal(err)
	}
	save := func(backend *Engine, raw string) *Session {
		t.Helper()
		result, err := hostEdit(t, backend, s.ID, raw)
		if err != nil {
			t.Fatalf("%s: %v", raw, err)
		}
		return result
	}
	titleChange := `{"op":"rename_board","title":"Shared title","expected_version":0}`
	result := save(e, titleChange)
	if result.Title != "Shared title" || result.Board.SourceSeat != "user" || result.Board.Version != 1 {
		t.Fatal(result.Board)
	}
	path := filepath.Join(e.dir, s.ID+".json")
	disk, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if retry := save(other, titleChange); retry.UpdatedAt != result.UpdatedAt {
		t.Fatal("retry caused a physical save")
	}
	same, err := os.ReadFile(path)
	if err != nil || string(disk) != string(same) {
		t.Fatal("identical request rewrote the file", err)
	}
	if conflict, err := hostEdit(t, other, s.ID, `{"op":"rename_board","title":"Second tab","expected_version":0}`); !errors.Is(err, ErrConflict) || conflict.Board.Title != "Shared title" {
		t.Fatal("missing winning title on conflict", err, conflict)
	}
	result = save(other, fmt.Sprintf(`{"op":"revise_module","module_id":"materials","body":"Read page two","material_ids":[%q],"expected_version":0}`, m.ID))
	result = save(e, `{"op":"revise_module","module_id":"materials","title":"Readings","expected_version":1}`)
	if mod := result.Board.module("materials"); mod.Body != "Read page two" || !slices.Equal(mod.MaterialIDs, []string{m.ID}) || mod.Version != 2 {
		t.Fatal("field patch lost material citations", mod)
	}
	save(e, fmt.Sprintf(`{"op":"annotate_material","material_id":%q,"body":"Check figure one","expected_version":0}`, m.ID))
	save(e, `{"op":"annotate_point","point_id":"point","body":"From the host","expected_version":0}`)
	result = save(other, `{"op":"annotate_point","point_id":"point","body":"","expected_version":1}`)
	if kept := result.Board.PointAnnotations["point"]; kept.Body != "" || kept.Version != 2 || kept.SourceSeat != "user" {
		t.Fatal(kept)
	}
	if _, err := hostEdit(t, other, s.ID, `{"op":"annotate_point","point_id":"point","body":"From the host","expected_version":0}`); !errors.Is(err, ErrConflict) {
		t.Fatal("stale request resurrected a deleted annotation", err)
	}
	note := `{"op":"add_note","module_id":"00000000-0000-4000-8000-000000000001","title":"A note","body":"Working text"}`
	result = save(e, note)
	if again := save(other, note); len(again.Board.Modules) != 3 || again.UpdatedAt != result.UpdatedAt {
		t.Fatal("add_note retry duplicated or rewrote a note")
	}
	for i := range 20 {
		result = save(e, fmt.Sprintf(`{"op":"edit_agenda","item_id":%q,"title":"Question %d","expected_version":%d}`, s.Agenda[0].ID, i, i))
	}
	item := result.Agenda[0]
	if item.Version != 20 || item.EditedBy != "user" || len(item.Revisions) != 1 || item.Revisions[0].PreviousTitle != "Original question" || item.Revisions[0].Seat != "user" || result.AgendaVersion != s.AgendaVersion+20 {
		t.Fatal("incorrect agenda change history", item, result.AgendaVersion)
	}
	if len(result.Events) != len(s.Events) || len(result.Board.RecentChanges) != 6 || result.Board.MaterialAnnotations[m.ID].Body != "Check figure one" || marshal(result.Rounds[0].Turns) != marshal(s.Rounds[0].Turns) {
		t.Fatal("autosaves grew event log or changed the signed public statements", result.Board)
	}
	before := marshal(result.Board)
	if err := e.locked(func() error {
		// Simulate termination with work in flight. Recovery must not replay a
		// still-pending proposal over any part of the host's latest version.
		result.Status = "running"
		result.Rounds[0].Turns[0].ProposedBoardUpdates = []boardUpdate{{Op: "rename_board", BaseVersion: result.Board.Version, BoardText: BoardText{Title: "Unconfirmed"}}}
		return e.save(result)
	}); err != nil {
		t.Fatal(err)
	}
	reopened, err := New(e.dir, call, testSettings)
	if err != nil {
		t.Fatal(err)
	}
	stored, err := reopened.Get(s.ID)
	if err != nil || marshal(stored.Board) != before || stored.Agenda[0].Title != "Question 19" {
		t.Fatal("restart lost committed host edits", err, stored)
	}
	stored.Status = "closed"
	if err := e.locked(func() error { return e.save(stored) }); err != nil {
		t.Fatal(err)
	}
	if closed, err := hostEdit(t, e, s.ID, titleChange); !errors.Is(err, ErrConflict) || closed.Status != "closed" {
		t.Fatal("closed meeting accepted an edit", err)
	}
}

func TestHostBoardConflictsWithOnlyStaleChairAndRoundTargets(t *testing.T) {
	entered, resume := make(chan struct{}), make(chan struct{})
	e, project := engine(t, func(ctx context.Context, _, _, prompt, _ string) (string, error) {
		close(entered)
		select {
		case <-ctx.Done():
			return "", ctx.Err()
		case <-resume:
		}
		return `{"agenda":[{"title":"Initial question","kind":"discussion"},{"title":"New question","kind":"discussion"}],"board":{"title":"Stale chair title","modules":[{"kind":"agenda","title":"Stale chair module"},{"kind":"positions","title":"Chair's point index"},{"kind":"note","title":"Chair note","body":"New idea"}]}}`, nil
	})
	s, err := e.CreateConfigured("Meeting topic", project, []Member{{Model: "first"}}, "review", AgendaInput{Title: "Initial question", Kind: "discussion"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := e.StartAgendaDraft(s.ID, &s.AgendaVersion); err != nil {
		t.Fatal(err)
	}
	select {
	case <-entered:
	case <-time.After(3 * time.Second):
		t.Fatal("chair did not start")
	}
	for _, raw := range []string{
		`{"op":"rename_board","title":"Host heading","expected_version":0}`,
		`{"op":"revise_module","module_id":"agenda","title":"Host agenda","expected_version":0}`,
		`{"op":"add_note","module_id":"00000000-0000-4000-8000-000000000001","title":"Host note","body":"Keep me"}`,
		fmt.Sprintf(`{"op":"edit_agenda","item_id":%q,"title":"Host question","expected_version":0}`, s.Agenda[0].ID),
	} {
		if _, err := hostEdit(t, e, s.ID, raw); err != nil {
			t.Fatal(err)
		}
	}
	close(resume)
	s = waitForAgenda(t, e, s.ID)
	if s.AgendaDraftStatus != "ready" || len(s.Agenda) != 2 || s.Agenda[0].Title != "Host question" || s.Agenda[1].Title != "New question" || s.Title != "Host heading" || s.Board.module("agenda").Title != "Host agenda" || s.Board.module("positions").Title != "Chair's point index" || len(s.Board.Modules) != 4 {
		t.Fatal("chair lost host edits or failed to contribute unrelated items", s)
	}
	raw := json.RawMessage(`[{"op":"rename_board","title":"Stale AI heading"},{"op":"revise_module","module_id":"agenda","title":"AI agenda"},{"op":"revise_module","module_id":"positions","title":"AI point index"}]`)
	r := &Round{Number: 1, Turns: []Turn{{Seat: "first", Status: "done", ProposedBoardUpdates: parseBoardUpdates(s, raw, "public")}}}
	p := parseAgendaUpdates(s, json.RawMessage(fmt.Sprintf(`[{"op":"revise","item_id":%q,"title":"AI question","reason":"Changed"}]`, s.Agenda[0].ID)))
	r.Turns[0].ProposedAgendaUpdates = p
	for _, raw := range []string{
		`{"op":"rename_board","title":"Further update","expected_version":1}`,
		`{"op":"revise_module","module_id":"agenda","title":"Further agenda","expected_version":1}`,
		fmt.Sprintf(`{"op":"edit_agenda","item_id":%q,"title":"ABA intermediate","expected_version":1}`, s.Agenda[0].ID),
		fmt.Sprintf(`{"op":"edit_agenda","item_id":%q,"title":"Host question","expected_version":2}`, s.Agenda[0].ID),
	} {
		s, err = hostEdit(t, e, s.ID, raw)
		if err != nil {
			t.Fatal(err)
		}
	}
	finishBoardRound(s, r, true)
	applyRoundAgendaUpdates(s, r)
	if s.Board.Title != "Further update" || s.Board.module("agenda").Title != "Further agenda" || s.Board.module("positions").Title != "AI point index" || s.Agenda[0].Title != "Host question" {
		t.Fatal("stale in-flight proposals published", s.Board, s.Agenda)
	}
}

func TestSimultaneousHostBoardWritesUseDiskRevisionUnderLock(t *testing.T) {
	call := func(context.Context, string, string, string, string) (string, error) {
		return "", errors.New("unexpected model request")
	}
	first, project := engine(t, call)
	s, err := first.Create("Versioned", project, nil)
	if err != nil {
		t.Fatal(err)
	}
	second, err := New(first.dir, call, testSettings)
	if err != nil {
		t.Fatal(err)
	}
	zero := 0
	left, right := "Left", "Right"
	submit := func(a, b HostBoardChange, wantConflicts int) {
		t.Helper()
		start := make(chan struct{})
		results := make(chan error, 2)
		for i, change := range []HostBoardChange{a, b} {
			e := []*Engine{first, second}[i]
			go func() {
				<-start
				_, err := e.ChangeBoard(s.ID, change)
				results <- err
			}()
		}
		close(start)
		conflicts := 0
		for range 2 {
			if err := <-results; errors.Is(err, ErrConflict) {
				conflicts++
			} else if err != nil {
				t.Fatal(err)
			}
		}
		if conflicts != wantConflicts {
			t.Fatalf("got %d conflicts, want %d", conflicts, wantConflicts)
		}
	}
	submit(HostBoardChange{Op: "rename_board", ExpectedVersion: &zero, Title: &left}, HostBoardChange{Op: "rename_board", ExpectedVersion: &zero, Title: &right}, 1)
	submit(HostBoardChange{Op: "revise_module", ModuleID: "agenda", ExpectedVersion: &zero, Title: &left}, HostBoardChange{Op: "revise_module", ModuleID: "positions", ExpectedVersion: &zero, Title: &right}, 0)
	s, err = second.Get(s.ID)
	if err != nil || s.Board.Version != 1 || s.Board.module("agenda").Title != left || s.Board.module("positions").Title != right {
		t.Fatal("concurrent writes lost a commit", s, err)
	}
}
