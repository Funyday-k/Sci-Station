package meeting

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"scistation.local/desktop/internal/deliberation"
)

func TestPublicPromptRefreshesHostBoardBetweenCalls(t *testing.T) {
	entered, proceed := make(chan string), make(chan struct{})
	var calls atomic.Int32
	publicCall := func(ctx context.Context, seat, _, prompt, _ string) (string, error) {
		var reply string
		switch calls.Add(1) {
		case 1:
			if !strings.Contains(prompt, `"state":"empty"`) || !strings.Contains(prompt, `"topic":"Original heading"`) {
				return "", errors.New("missing original board")
			}
			reply = `{"action":"read","path":"probe.md"}`
		case 2:
			for _, want := range []string{`"title":"First host edit"`, `"edited_by":"user"`, "Use the host scope", "Original heading", "Attached material annotation"} {
				if !strings.Contains(prompt, want) {
					return "", fmt.Errorf("same turn did not receive the host edit %q", want)
				}
			}
			if !strings.Contains(deliberation.InstructionsFrom(ctx), "Address relevant host edits") {
				return "", errors.New("missing attribution instructions")
			}
			reply = `{"action":"say","text":"The sample remains small.","board_updates":[{"op":"rename_board","title":"Stale model heading"},{"op":"add_note","title":"Sample size","body":"The sample remains small."}]}`
		case 3:
			data, err := discussionContext(prompt)
			if err != nil {
				return "", err
			}
			var board MeetingBoard
			if err = json.Unmarshal([]byte(marshal(data["board"])), &board); err != nil {
				return "", err
			}
			if seat != "cursor" || board.Title != "Second host edit" || board.SourceSeat != "user" || board.Version != 2 {
				return "", fmt.Errorf("next seat did not receive the latest saved heading: %+v", board)
			}
			return say("I will compare the bounded sample."), nil
		default:
			return "", errors.New("unexpected model request")
		}
		select {
		case entered <- seat:
		case <-ctx.Done():
			return "", ctx.Err()
		}
		select {
		case <-proceed:
			return reply, nil
		case <-ctx.Done():
			return "", ctx.Err()
		}
	}
	e, project := engine(t, publicCall)
	s, err := e.Create("Original heading", project, []string{"codex", "cursor"})
	if err != nil {
		t.Fatal(err)
	}
	s, err = e.ChangeAgenda(s.ID, AgendaChange{Action: "add", AgendaInput: AgendaInput{Title: "Original scope", Kind: "implementation"}, ExpectedVersion: &s.AgendaVersion})
	if err != nil {
		t.Fatal(err)
	}
	material, err := e.StoreMaterial("sample.txt", strings.NewReader("Recorded attachment text"))
	if err != nil {
		t.Fatal(err)
	}
	if _, err = e.StartRound(s.ID, "", "", 0, RoundOptions{Preset: "work", Phase: "work", MaterialIDs: []string{material.ID}}); err != nil {
		t.Fatal(err)
	}
	waitEntered := func() {
		t.Helper()
		select {
		case seat := <-entered:
			if seat != "codex" {
				t.Fatalf("in-flight request for %q", seat)
			}
		case <-time.After(2 * time.Second):
			t.Fatal("request did not reach the local model")
		}
	}
	save := func(change HostBoardChange) {
		t.Helper()
		s, err = e.ChangeBoard(s.ID, change)
		if err != nil {
			t.Fatal(err)
		}
	}
	waitEntered()
	title, scope, annotation, zero := "First host edit", "Use the host scope", "Attached material annotation", 0
	save(HostBoardChange{Op: "rename_board", Title: &title, ExpectedVersion: &zero})
	save(HostBoardChange{Op: "edit_agenda", ItemID: s.ActiveAgendaID, Title: &scope, ExpectedVersion: &zero})
	save(HostBoardChange{Op: "annotate_material", MaterialID: material.ID, Body: &annotation, ExpectedVersion: &zero})
	if calls.Load() != 1 {
		t.Fatal("saving a board edit invoked an additional model")
	}
	proceed <- struct{}{}
	waitEntered()
	title = "Second host edit"
	save(HostBoardChange{Op: "rename_board", Title: &title, ExpectedVersion: &s.Board.Version})
	proceed <- struct{}{}
	s = settled(t, e, s.ID)
	if s.Status != "ready" || s.Board.Title != title || s.Board.SourceSeat != "user" || calls.Load() != 3 {
		t.Fatalf("round lost the saved title or added calls: %+v, calls %d", s, calls.Load())
	}
	for _, module := range s.Board.Modules {
		if module.Title == "Sample size" && module.SourceSeat == "codex" && module.Body == "The sample remains small." {
			return
		}
	}
	t.Fatal("valid public contribution was not added to the host-edited board")
}

func TestAgendaDraftRetryReceivesHostBoard(t *testing.T) {
	var calls atomic.Int32
	e, project := engine(t, func(ctx context.Context, _, _, prompt, _ string) (string, error) {
		if calls.Add(1) == 1 {
			return "", errors.New("first chair failed")
		}
		for _, want := range []string{"Host heading", "Host scoped agenda", "Host note text", `"edited_by":"user"`, "recent_changes", `"source_seat":"user"`} {
			if !strings.Contains(prompt, want) {
				return "", fmt.Errorf("retry did not receive %q", want)
			}
		}
		return `{"agenda":[{"title":"What else needs verifying?","kind":"discussion"}],"board":{"title":"Stale chair heading","modules":[]}}`, nil
	})
	s, err := e.CreateConfigured("Open a meeting", project, []Member{{Model: "chair"}}, "review", AgendaInput{Title: "Initial scope", Kind: "discussion"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err = e.StartAgendaDraft(s.ID, &s.AgendaVersion); err != nil {
		t.Fatal(err)
	}
	s = waitForAgenda(t, e, s.ID)
	if s.AgendaDraftStatus != "failed" {
		t.Fatal(s.AgendaDraftStatus)
	}
	title, scope, noteTitle, noteBody, zero := "Host heading", "Host scoped agenda", "Host note", "Host note text", 0
	for _, change := range []HostBoardChange{
		{Op: "rename_board", Title: &title, ExpectedVersion: &zero},
		{Op: "edit_agenda", ItemID: s.ActiveAgendaID, Title: &scope, ExpectedVersion: &zero},
		{Op: "add_note", ModuleID: "094e46f2d9c64c269a7a17eb751bfb5f", Title: &noteTitle, Body: &noteBody},
	} {
		s, err = e.ChangeBoard(s.ID, change)
		if err != nil {
			t.Fatal(err)
		}
	}
	if calls.Load() != 1 {
		t.Fatal("board edits started a model call")
	}
	if _, err = e.StartAgendaDraft(s.ID, &s.AgendaVersion); err != nil {
		t.Fatal(err)
	}
	s = waitForAgenda(t, e, s.ID)
	if s.AgendaDraftStatus != "ready" || s.Board.Title != title || s.Agenda[0].Title != scope || len(s.Agenda) != 2 || calls.Load() != 2 {
		t.Fatalf("retry did not preserve the host's edits: %+v", s)
	}
}

func TestBoardPromptKeepsBlindRoundPrivate(t *testing.T) {
	const pointID = "r1-s1-p1"
	s := &Session{
		Rounds: []Round{{Number: 1, Turns: []Turn{{Seat: "member-1", Status: "done", Points: []DiscussionPoint{{ID: pointID, Text: "BLIND_PROPOSITION"}}}}}},
		Board: MeetingBoard{
			PointAnnotations: map[string]BoardAnnotation{pointID: {Body: "BLIND_HOST_NOTE", BoardSource: BoardSource{SourceSeat: "user", Version: 1}}},
			RecentChanges:    []BoardChangeSummary{{Op: "annotate_point", TargetID: pointID, After: "BLIND_HOST_NOTE", SourceSeat: "user", Version: 1}},
		},
	}
	data := map[string]any{}
	includeBoardPrompt(data, s, 0)
	if open := marshal(data); !strings.Contains(open, "BLIND_PROPOSITION") || !strings.Contains(open, "BLIND_HOST_NOTE") {
		t.Fatal("verified host note or its original point is missing")
	}
	includeBoardPrompt(data, s, 1)
	if blind := marshal(data); strings.Contains(blind, "BLIND_") || strings.Contains(blind, pointID) {
		t.Fatal("blind round leaked a point or annotation: " + blind)
	}
}
