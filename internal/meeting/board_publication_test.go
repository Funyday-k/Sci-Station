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

func boardKinds(b MeetingBoard) []string {
	kinds := make([]string, 0, len(b.Modules))
	for _, m := range b.Modules {
		kinds = append(kinds, m.Kind)
	}
	return kinds
}

func TestBoardPublishedByChairAndExtendedByCanonicalEvents(t *testing.T) {
	started, release := make(chan struct{}), make(chan struct{})
	var calls atomic.Int32
	e, project := engine(t, func(ctx context.Context, _, _, prompt, _ string) (string, error) {
		calls.Add(1)
		if strings.HasPrefix(prompt, "AGENDA DRAFT REQUEST") {
			if !strings.Contains(deliberation.InstructionsFrom(ctx), "Choose only the presets") || !strings.Contains(prompt, `"state":"empty"`) || !strings.Contains(prompt, "Unselected attachment") {
				return "", errors.New("chair did not receive module choices or inputs")
			}
			close(started)
			select {
			case <-ctx.Done():
				return "", ctx.Err()
			case <-release:
			}
			// A board-only reply, with no invented agenda or prescribed cards.
			return `{"board":{"title":"Pilot evidence","modules":[{"kind":"note","title":"Boundary","body":"Look for a repeatable acceptance criterion."}]}}`, nil
		}
		return `{"action":"say","text":"Measure the queue.","points":[{"text":"Measure the queue."}]}`, nil
	})
	m, err := e.StoreMaterial("raw.txt", strings.NewReader("Unselected attachment"))
	if err != nil {
		t.Fatal(err)
	}
	s, err := e.CreateConfiguredWithMaterials("Review the pilot", project, []Member{{Model: "first"}}, "review", nil, []string{m.ID}, AgendaInput{Title: "Host question", Kind: "discussion"})
	if err != nil {
		t.Fatal(err)
	}
	if s.Board.State != boardEmpty || s.Board.Title != "" || len(s.Board.Modules) != 0 || calls.Load() != 0 {
		t.Fatal("creation fabricated a board", s.Board)
	}
	s, err = e.StartAgendaDraft(s.ID, &s.AgendaVersion)
	if err != nil {
		t.Fatal(err)
	}
	select {
	case <-started:
	case <-time.After(3 * time.Second):
		t.Fatal("chair not invoked")
	}
	if s.Board.State != boardEmpty || s.AgendaDraftStatus != "drafting" {
		t.Fatal(s.Board, s.AgendaDraftStatus)
	}
	check, rev, err := e.Snapshot(s.ID, nil)
	if err != nil || check.Board.State != boardEmpty || len(check.Board.Modules) != 0 {
		t.Fatal("poll created a page", check, err)
	}
	unchanged, _, err := e.Snapshot(s.ID, func(current string) bool { return current == rev })
	if err != nil || unchanged != nil {
		t.Fatal("poll rewrote the meeting", err)
	}
	close(release)
	s = waitForAgenda(t, e, s.ID)
	if s.AgendaDraftStatus != "ready" || s.Board.State != boardPublished || s.Board.Title != "Pilot evidence" || !slices.Equal(boardKinds(s.Board), []string{"note"}) || calls.Load() != 1 {
		t.Fatal("chair's selected subset was not preserved", s.Board, s.AgendaDraftStatus)
	}
	original := s.Board.Modules[0]
	s, err = e.ChangeAgenda(s.ID, AgendaChange{Action: "add", AgendaInput: AgendaInput{Title: "Follow-up question", Kind: "discussion"}, ExpectedVersion: &s.AgendaVersion})
	if err != nil || !slices.Equal(boardKinds(s.Board), []string{"note", "agenda"}) {
		t.Fatal("new agenda did not acquire a live view", s, err)
	}
	s, err = e.StartRound(s.ID, "Assess evidence", "", 0, RoundOptions{Preset: "review", Phase: "proposal", MaterialIDs: []string{m.ID}})
	if err != nil || !slices.Equal(boardKinds(s.Board), []string{"note", "agenda", "materials"}) {
		t.Fatal("material was not visible at round submission", s, err)
	}
	s = settled(t, e, s.ID)
	if s.Status != "ready" || !slices.Equal(boardKinds(s.Board), []string{"note", "agenda", "materials", "positions"}) || marshal(s.Board.Modules[0]) != marshal(original) || calls.Load() != 2 {
		t.Fatal("confirmed point did not extend the chair's layout", s.Board, s.Status)
	}
	restored, err := e.Get(s.ID)
	if err != nil || marshal(s.Board) != marshal(restored.Board) {
		t.Fatal("saved layout changed on read", err)
	}
}

func TestBoardFailureKeepsChatAndSupportsLegacyAgendaRetry(t *testing.T) {
	var calls atomic.Int32
	e, project := engine(t, func(context.Context, string, string, string, string) (string, error) {
		switch calls.Add(1) {
		case 1:
			return `{"agenda":[{"title":"Uncommitted question","kind":"discussion"}],"board":{"modules":[{"kind":"execute","title":"Not a preset"}]}}`, nil
		case 2:
			return `[{"title":"Verified agenda item","kind":"discussion"}]`, nil
		default:
			return "", errors.New("duplicate chair call")
		}
	})
	s, err := e.CreateConfigured("Try again", project, []Member{{Model: "first"}}, "review")
	if err != nil {
		t.Fatal(err)
	}
	for i := range 2 {
		if _, err := e.StartAgendaDraft(s.ID, &s.AgendaVersion); err != nil {
			t.Fatal(err)
		}
		s = waitForAgenda(t, e, s.ID)
		if i == 0 && (s.AgendaDraftStatus != "failed" || s.AgendaDraftError == "" || s.Board.State != boardEmpty || len(s.Board.Modules) != 0 || len(s.Agenda) != 0) {
			t.Fatal("invalid layout escaped its failed draft", s)
		}
	}
	if s.AgendaDraftStatus != "ready" || s.Board.State != boardPublished || !slices.Equal(boardKinds(s.Board), []string{"agenda"}) || len(s.Agenda) != 1 || s.Agenda[0].Title != "Verified agenda item" || calls.Load() != 2 {
		t.Fatal("legacy chair reply did not generate exactly one real agenda view", s)
	}
}

func TestBoardLegacyArchivesRequireActualPublicationEvidence(t *testing.T) {
	e, project := engine(t, func(context.Context, string, string, string, string) (string, error) {
		t.Fatal("opening an archive invoked a model")
		return "", nil
	})
	defaults := []BoardModule{}
	for _, kind := range []string{"agenda", "materials", "positions"} {
		mod, _ := presetBoardModule(kind)
		defaults = append(defaults, mod)
	}
	authored := slices.Clone(defaults)
	authored[1].Title, authored[1].SourceSeat = "Chair's reading plan", "member-1"
	authored = append(authored, BoardModule{ID: "n1", Kind: "note", BoardText: BoardText{Title: "Host note", Body: "Original host wording"}, BoardSource: BoardSource{SourceSeat: "user", Version: 7}})
	for _, tc := range []struct {
		name, draft, agendaSource, wantState string
		modules                              []BoardModule
		want                                 []string
	}{
		{"no board field", "ready", "chair", boardEmpty, nil, []string{}},
		{"default shell", "failed", "host", boardEmpty, defaults, []string{}},
		{"unwritten chair with history", "pending", "chair", boardEmpty, defaults, []string{}},
		{"only automatic template", "ready", "template", boardEmpty, defaults, []string{}},
		{"accepted agenda-only chair", "ready", "chair", boardPublished, defaults, []string{"agenda"}},
		{"real chair and host modules", "ready", "chair", boardPublished, authored, []string{"agenda", "materials", "note"}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			s, err := e.Create("Archived", project, nil)
			if err != nil {
				t.Fatal(err)
			}
			path := filepath.Join(e.dir, s.ID+".json")
			s.Status, s.Title, s.AgendaDraftStatus = "closed", "Archived title", tc.draft
			s.Agenda = []AgendaItem{{ID: "a1", AgendaInput: AgendaInput{Title: "Existing item", Kind: "discussion"}, Source: tc.agendaSource}}
			var raw map[string]any
			if err := json.Unmarshal([]byte(marshal(s)), &raw); err != nil {
				t.Fatal(err)
			}
			delete(raw, "board")
			if tc.modules != nil {
				raw["board"] = map[string]any{"title": s.Title, "modules": tc.modules}
			}
			prior, err := json.Marshal(raw)
			if err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(path, prior, 0600); err != nil {
				t.Fatal(err)
			}
			saved, err := e.Get(s.ID)
			if err != nil || saved.Board.State != tc.wantState || !slices.Equal(boardKinds(saved.Board), tc.want) {
				t.Fatal("unexpected archive view", saved, err)
			}
			if tc.modules != nil && len(tc.modules) > 3 && (saved.Board.module("n1").Version != 7 || saved.Board.module("n1").Body != "Original host wording") {
				t.Fatal("lost saved content or revision", saved.Board)
			}
			after, err := os.ReadFile(path)
			if err != nil || string(prior) != string(after) {
				t.Fatal("opening history rewrote the file", err)
			}
			if _, err := hostEdit(t, e, s.ID, fmt.Sprintf(`{"op":"rename_board","title":"Blocked","expected_version":%d}`, saved.Board.Version)); !errors.Is(err, ErrConflict) {
				t.Fatal("closed archive accepted edit", err)
			}
		})
	}
}
