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
	"sync/atomic"
	"testing"
	"time"

	"scistation.local/desktop/internal/deliberation"
)

func TestBoardFirstChairAndSuccessfulPublicEdits(t *testing.T) {
	var calls atomic.Int32
	var materialID string
	entered, resume := make(chan struct{}), make(chan struct{})
	e, project := engine(t, func(ctx context.Context, seat, _, prompt, _ string) (string, error) {
		calls.Add(1)
		rules := deliberation.InstructionsFrom(ctx)
		if strings.HasPrefix(prompt, "AGENDA DRAFT REQUEST") {
			if !strings.Contains(rules, "board object") || !strings.Contains(prompt, materialID) {
				return "", errors.New("missing chair instructions or material")
			}
			return fmt.Sprintf(`{"agenda":[{"kind":"discussion","title":"At what load does queueing start?"}],"board":{"title":"Queueing evidence","modules":[{"kind":"materials","title":"Load test notes","body":"Check the test range.","material_ids":[%q]},{"kind":"agenda","title":"Questions about saturation"}]}}`, materialID), nil
		}
		data, err := discussionContext(prompt)
		if err != nil {
			return "", err
		}
		board, ok := data["board"].(map[string]any)
		if !ok || board["title"] != "Queueing evidence" || !strings.Contains(rules, "board_updates") {
			return "", errors.New("missing original shared board")
		}
		if seat == "member-1" {
			return fmt.Sprintf(`{"action":"say","text":"The pilot uses 40 workers.","board_updates":[{"op":"rename_board","title":"Pilot saturation"},{"op":"revise_module","module_id":"materials","title":"Pilot evidence","body":"The pilot uses 40 workers.","material_ids":[%q]},{"op":"add_note","title":"Workers","body":"The pilot uses 40 workers."}],"points":[{"text":"The pilot uses 40 workers."}]}`, materialID), nil
		}
		if strings.Contains(marshal(data["prior_statements"]), "The pilot uses 40 workers.") {
			return "", errors.New("blind proposal leaked")
		}
		close(entered)
		select {
		case <-resume:
		case <-ctx.Done():
			return "", ctx.Err()
		}
		return `{"action":"say","text":"Review the control group.","board_updates":[{"op":"rename_board","title":"Competing header"},{"op":"add_note","title":"Control group","body":"Review the control group."}],"agenda_updates":[{"op":"add","title":"Which control should we use?","kind":"discussion","reason":"The control group is unspecified."}]}`, nil
	})
	material, err := e.StoreMaterial("load.txt", strings.NewReader("The pilot uses 40 workers."))
	if err != nil {
		t.Fatal(err)
	}
	materialID = material.ID
	s, err := e.CreateConfiguredWithMaterials("Discuss queueing", project, []Member{{Model: "first"}, {Model: "second"}}, "review", nil, []string{materialID})
	if err != nil {
		t.Fatal(err)
	}
	if calls.Load() != 0 || s.Board.SourceSeat != "" || s.Board.State != boardEmpty || len(s.Board.Modules) != 0 {
		t.Fatal("creation attributed or requested a model response")
	}
	if _, err = e.StartAgendaDraft(s.ID, &s.AgendaVersion); err != nil {
		t.Fatal(err)
	}
	s = waitForAgenda(t, e, s.ID)
	if s.Board.Title != "Queueing evidence" || s.Title != s.Board.Title || s.Board.SourceSeat != "member-1" || s.Board.SourceRound != 0 || s.Board.Modules[0].Kind != "materials" || s.Board.Modules[0].Body != "Check the test range." || !slices.Equal(s.Board.Modules[0].MaterialIDs, []string{materialID}) || s.Board.State != boardPublished || len(s.Board.Modules) != 2 || s.Board.module("positions") != nil || len(s.Agenda) != 1 || calls.Load() != 1 {
		t.Fatalf("incorrect draft or second chair request %+v, calls %d", s.Board, calls.Load())
	}
	if _, err = e.StartWithDiscussion(s.ID, "", "", 0, "review", "proposal"); err != nil {
		t.Fatal(err)
	}
	select {
	case <-entered:
	case <-time.After(3 * time.Second):
		t.Fatal("second seat did not start")
	}
	current, readErr := e.Get(s.ID)
	close(resume)
	if readErr != nil || current.Board.Title != "Queueing evidence" || len(current.Board.Modules) != 2 {
		t.Fatalf("unconfirmed board published %v", readErr)
	}
	s = settled(t, e, s.ID)
	if s.Status != "ready" || len(s.Rounds) != 1 || calls.Load() != 3 {
		t.Fatalf("failed round %+v", s.Rounds)
	}
	if s.Board.Title != "Pilot saturation" || s.Title != s.Board.Title || s.Board.SourceRound != 1 || s.Board.SourceSeat != "member-1" || len(s.Board.Modules) != 5 {
		t.Fatal(s.Board)
	}
	review := s.Board.module("materials")
	if review.Title != "Pilot evidence" || review.Body != "The pilot uses 40 workers." || !slices.Equal(review.MaterialIDs, []string{materialID}) || review.SourceSeat != "member-1" || review.SourceRound != 1 {
		t.Fatal(review)
	}
	if s.Board.Modules[4].Kind != "positions" {
		t.Fatal("new confirmed points did not reveal their own module", s.Board.Modules)
	}
	last := s.Board.Modules[3]
	if last.ID == "" || last.ID == s.Board.Modules[2].ID || last.Title != "Control group" || last.SourceSeat != "member-2" {
		t.Fatal(s.Board.Modules)
	}
	if len(s.Rounds[0].Turns[0].Points) != 1 || len(s.Rounds[0].Turns[0].ProposedBoardUpdates) != 0 || len(s.Agenda) != 2 || s.Agenda[1].Status != "pending" {
		t.Fatal("board changed canonical agenda/point semantics")
	}
	heading, err := e.GenerateTitle(context.Background(), s.ID)
	if err != nil || heading != s.Board.Title || calls.Load() != 3 {
		t.Fatalf("navigation requested a second title: %q, %v (calls %d)", heading, err, calls.Load())
	}
	reopen, err := New(e.dir, e.call, testSettings)
	if err != nil {
		t.Fatal(err)
	}
	saved, err := reopen.Get(s.ID)
	if err != nil || marshal(saved.Board) != marshal(s.Board) {
		t.Fatal("saved board differed after reopen", err)
	}
}

func TestBoardRejectsUnsupportedFieldsAndInvalidReferences(t *testing.T) {
	s := &Session{Topic: "Topic", Materials: []Material{{ID: "attached"}}}
	ensureBoard(s)
	cases := []string{
		`{"op":"rename_board","source_seat":"member-2","title":"Faked"}`,
		`{"op":"rename_board","OP":"do","title":"Spoofed"}`,
		`{"op":"rename_board","title":"First","title":"Second"}`,
		`{"op":"rename_board","body":"Text","title":"Forbidden"}`,
		`{"op":"add_note","kind":"command","title":"Action","body":"Text"}`,
		`{"op":"add_note","title":"Made up","body":"unspoken"}`,
		`{"op":"add_note","title":"Unknown material","body":"Text","material_ids":["foreign"]}`,
		`{"op":"add_note","title":"Repeat","body":"Text","material_ids":["attached","attached"]}`,
		`{"op":"revise_module","module_id":"elsewhere","title":"Missing"}`,
		`{"op":"revise_module","module_id":"materials","title":"Review","body":"Text"}`,
		`{"op":"revise_module","module_id":"positions","title":"Votes","body":"Text"}`,
		`{"op":"set_status","module_id":"agenda","title":"Done"}`,
		`{"op":"rename_board","title":"` + strings.Repeat("中", 81) + `"}`,
		`{"op":"add_note","title":"Long","body":"` + strings.Repeat("中", 801) + `"}`,
	}
	for _, raw := range cases {
		if out := parseBoardUpdates(s, json.RawMessage("["+raw+"]"), "Text "+strings.Repeat("中", 801)); len(out) != 0 {
			t.Fatalf("accepted %s: %+v", raw, out)
		}
	}
	valid := `{"op":"add_note","title":"Quoted","body":"Text","material_ids":["attached"]}`
	updates := parseBoardUpdates(s, json.RawMessage("["+strings.Join(append(cases, valid), ",")+"]"), "Text")
	if len(updates) != 1 || updates[0].Title != "Quoted" {
		t.Fatal(updates)
	}
	applyBoardDraft(s, json.RawMessage(`{"title":"Chair","modules":[{"kind":"custom","title":"Bad"},{"kind":"positions","source_round":7,"title":"Bad"},{"kind":"note","title":"Missing body"},{"kind":"note","title":"One","body":"Review controls"},{"kind":"note","title":"ONE","body":"Repeated"}]}`), BoardSource{SourceSeat: "chair"})
	if len(s.Board.Modules) != 1 || s.Board.Modules[0].Title != "One" || s.Board.module("positions") != nil {
		t.Fatal(s.Board)
	}
	var batch []string
	for i := 0; i < 18; i++ {
		batch = append(batch, fmt.Sprintf(`{"op":"add_note","title":"Note %d","body":"Text"}`, i))
	}
	s.Status = "ready"
	r := &Round{Number: 2}
	for start := 0; start < len(batch); start += 4 {
		end := min(start+4, len(batch))
		proposals := parseBoardUpdates(s, json.RawMessage("["+strings.Join(batch[start:end], ",")+"]"), "Text")
		if len(proposals) != min(maxBoardUpdates, end-start) {
			t.Fatal(len(proposals))
		}
		r.Turns = append(r.Turns, Turn{Seat: "chair", Status: "done", ProposedBoardUpdates: proposals})
	}
	finishBoardRound(s, r, true)
	if len(s.Board.Modules) != maxBoardModules-3 {
		t.Fatalf("module cap failed: %d", len(s.Board.Modules))
	}
}

func TestBoardIgnoresUnsettledRoundsAndReadsLegacySessions(t *testing.T) {
	e, project := engine(t, func(context.Context, string, string, string, string) (string, error) {
		return "", errors.New("unexpected model request")
	})
	s, err := e.Create("Legacy topic", project, nil)
	if err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(e.dir, s.ID+".json")
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var legacy map[string]json.RawMessage
	if err = json.Unmarshal(data, &legacy); err != nil {
		t.Fatal(err)
	}
	delete(legacy, "board")
	legacy["title"] = json.RawMessage(`"Existing name"`)
	data, err = json.Marshal(legacy)
	if err != nil {
		t.Fatal(err)
	}
	if err = os.WriteFile(path, data, 0600); err != nil {
		t.Fatal(err)
	}
	s, err = e.Get(s.ID)
	if err != nil || s.Title != "Existing name" || s.Board.Title != "" || s.Board.SourceSeat != "" || s.Board.State != boardEmpty || len(s.Board.Modules) != 0 {
		t.Fatalf("legacy %+v %v", s, err)
	}
	unmodified, err := os.ReadFile(path)
	if err != nil || string(unmodified) != string(data) {
		t.Fatal("reading a legacy meeting rewrote it")
	}
	for _, raw := range []string{`[{"title":"One","kind":"discussion"}]`, `{"agenda":[{"title":"One","kind":"discussion"}]}`} {
		agenda, board, err := parseAgendaDraft(raw)
		if err != nil || len(agenda) != 1 || board != nil {
			t.Fatal(agenda, string(board), err)
		}
	}
	for _, tc := range []struct {
		name         string
		lastStatus   string
		cancel       bool
		interruption string
	}{
		{"partial", "error", false, ""},
		{"cancelled", "done", true, ""},
		{"interrupted after last say", "done", false, "process exited"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			snapshot := clone(s)
			snapshot.Status = "running"
			snapshot.Rounds = []Round{{Number: 1, Turns: []Turn{{Seat: "first", Status: "done", ProposedBoardUpdates: []boardUpdate{{Op: "rename_board", BoardText: BoardText{Title: "Unconfirmed"}}}}, {Seat: "second", Status: tc.lastStatus}}}}
			recordRoundEnd(snapshot, tc.cancel, tc.interruption)
			if snapshot.Board.State != boardEmpty || snapshot.Board.Title != "" || len(snapshot.Rounds[0].Turns[0].ProposedBoardUpdates) != 0 {
				t.Fatal(snapshot.Board)
			}
		})
	}
}
