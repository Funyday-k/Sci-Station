package meeting

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
	"unicode/utf8"

	"scistation.local/desktop/internal/workspace"
)

func TestLongMeetingKeepsReferencesAndFetchesVisibleOriginal(t *testing.T) {
	const oldPoint = "r1-s1-p1"
	const oldTail = "ORIGINAL_OLD_CONCLUSION"
	const peerCurrent = "SEALED_CURRENT_ROUND"
	const partial = "INCOMPLETE_EARLIER_TURN"
	const private = "OTHER_SEAT_PRIVATE_EVIDENCE"
	oldText := "A testable proposal. " + strings.Repeat("观测<\n", 850) + oldTail
	largeFile := strings.Repeat("project evidence\n", 9000) + "LARGE_FILE_END"
	routes := []Round{}
	legacyStatements := []publicStatement{}
	for round := 1; round <= 24; round++ {
		turns := []Turn{}
		for _, seat := range []string{"codex", "cursor"} {
			turn := Turn{Seat: seat, Model: seat + "/main", Status: "done",
				Text: fmt.Sprintf("Round %d from %s. ", round, seat) + strings.Repeat("实测<\n", 850)}
			if round == 1 && seat == "codex" {
				turn.Text = oldText
				turn.Points = []DiscussionPoint{{ID: oldPoint, Text: "A testable proposal."}}
				turn.Children = []Child{{Status: "done", Text: private}}
			}
			if round == 2 && seat == "codex" {
				turn.Status, turn.Text = "error", partial
			}
			turns = append(turns, turn)
			if turn.Status == "done" {
				legacyStatements = append(legacyStatements, publicStatement{
					Round: round, Seat: seat, Model: turn.Model, Text: turn.Text, Points: turn.Points,
				})
			}
		}
		routes = append(routes, Round{Number: round, Note: fmt.Sprintf("host constraint %d", round), Turns: turns})
	}

	var legacyChange workspace.Change
	var legacyFile workspace.File
	cursorCalls, childCalls := 0, 0
	e, project := engine(t, func(ctx context.Context, seat, model, prompt, executable string) (string, error) {
		if seat == "codex" {
			return say(peerCurrent), nil
		}
		for _, hidden := range []string{peerCurrent, partial, private} {
			if strings.Contains(prompt, hidden) {
				return "", fmt.Errorf("hidden statement leaked: %s", hidden)
			}
		}
		if model == "cursor/child" {
			childCalls++
			switch childCalls {
			case 1:
				return `{"action":"read_statement","round":25,"seat":"codex"}`, nil
			case 2:
				if !strings.Contains(prompt, "no completed public statement is visible") {
					return "", errors.New("private child fetched the current, independent seat's statement")
				}
				return `{"action":"read_statement","round":1,"seat":"codex"}`, nil
			default:
				if strings.Count(prompt, marshal(oldText)) != 1 {
					return "", errors.New("child did not receive the exact earlier statement")
				}
				return say("Child checked public evidence."), nil
			}
		}
		cursorCalls++
		switch cursorCalls {
		case 1:
			if !strings.Contains(prompt, oldPoint) || !strings.Contains(prompt, "host constraint 1") ||
				!strings.Contains(prompt, `"text_omitted":true`) || !strings.Contains(prompt, `"diff_omitted":true`) ||
				strings.Contains(prompt, oldTail) || strings.Contains(prompt, "LARGE_FILE_END") {
				return "", errors.New("base context did not compact evidence or lost the source references")
			}
			contextData, err := discussionContext(prompt)
			if err != nil {
				return "", err
			}
			contextData["prior_statements"] = legacyStatements
			contextData["peer_changes"] = []map[string]any{{
				"round": 24, "seat": "codex", "change": legacyChange, "current_content": legacyFile,
			}}
			_, suffix, found := strings.Cut(prompt, "\nSTEPS REMAINING:")
			if !found {
				return "", errors.New("serialized model input missing step suffix")
			}
			legacy := "CONTEXT:\n" + marshal(contextData) + "\nSTEPS REMAINING:" + suffix
			t.Logf("synthetic 24-round initial model input: %d → %d serialized bytes", len(legacy), len(prompt))
			if len(prompt)*3 >= len(legacy) {
				return "", errors.New("long meeting input should remove substantial repeated evidence")
			}
			return `{"action":"read_statement","round":25,"seat":"codex"}`, nil
		case 2:
			if !strings.Contains(prompt, "no completed public statement is visible") {
				return "", errors.New("independent parent fetched a same-round statement")
			}
			return `{"action":"read_statement","round":2,"seat":"codex"}`, nil
		case 3:
			if strings.Count(prompt, "no completed public statement is visible") != 2 {
				return "", errors.New("incomplete historical turn was accessible")
			}
			return `{"action":"read_statement","round":1,"seat":"codex"}`, nil
		case 4:
			if strings.Count(prompt, marshal(oldText)) != 1 {
				return "", errors.New("earlier original text was not restored verbatim")
			}
			return `{"action":"read_statement","round":1,"seat":"codex"}`, nil
		case 5:
			if strings.Count(prompt, marshal(oldText)) != 1 || !strings.Contains(prompt, `"already_read":true`) {
				return "", errors.New("repeated statement read was not deduplicated")
			}
			return `{"action":"delegate","task":"Inspect the old public source"}`, nil
		default:
			if !strings.Contains(prompt, "Child checked public evidence.") {
				return "", errors.New("parent did not receive the child's evidence check")
			}
			return `{"action":"say","text":"Keep the testable proposal.","positions":[{"point_id":"r1-s1-p1","stance":"support","reason":"Keep the testable proposal."}]}`, nil
		}
	})
	var err error
	legacyChange, err = workspace.Write(project, "evidence.md", largeFile, workspace.MissingVersion)
	if err != nil {
		t.Fatal(err)
	}
	legacyFile, err = workspace.Read(project, "evidence.md")
	if err != nil {
		t.Fatal(err)
	}
	routes[23].Turns[0].Changes = []workspace.Change{legacyChange}
	s, err := e.Create("Long meeting", project, []string{"codex", "cursor"})
	if err != nil {
		t.Fatal(err)
	}
	err = e.locked(func() error {
		s.Rounds = routes
		return e.save(s)
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err = e.StartWithDiscussion(s.ID, "verify source", "", 24, "review", "challenge"); err != nil {
		t.Fatal(err)
	}
	// Polling Get would repeatedly decode the full archive under the worker's
	// storage lock. Wait for the worker to finish its final save instead.
	ended := make(chan struct{})
	go func() {
		e.workers.Wait()
		close(ended)
	}()
	select {
	case <-ended:
	case <-time.After(30 * time.Second):
		t.Fatal("long meeting worker did not finish")
	}
	s, err = e.Get(s.ID)
	if err != nil {
		t.Fatal(err)
	}
	turn := s.Rounds[24].Turns[1]
	if s.Status != "ready" || len(turn.Positions) != 1 || turn.Positions[0].PointID != oldPoint {
		t.Fatalf("long-round discussion failed: status = %s, turn error = %q, positions = %+v", s.Status, turn.Error, turn.Positions)
	}
	if s.Rounds[0].Turns[0].Text != oldText || childCalls != 3 {
		t.Fatal("source was rewritten or child did not finish both reads")
	}
}

func TestPromptEvidenceOmitsRepeatedFileAndBlockedWriteBodies(t *testing.T) {
	const initialMarker = "INITIAL_FILE_BODY_TAIL"
	const newMarker = "BLOCKED_FILE_BODY_TAIL"
	initial := strings.Repeat("first revision\n", 9000) + initialMarker
	written := strings.Repeat("second revision\n", 9000) + newMarker
	parentCalls, childCalls := 0, 0
	e, project := engine(t, func(ctx context.Context, seat, model, prompt, executable string) (string, error) {
		if model == "codex/child" {
			childCalls++
			switch childCalls {
			case 1:
				if strings.Contains(prompt, initialMarker) || !strings.Contains(prompt, `"text_omitted":true`) {
					return "", errors.New("large selected file was duplicated in the child handoff")
				}
			case 2:
				if strings.Count(prompt, marshal(initial)) != 1 {
					return "", errors.New("child explicit read did not preserve exact file content")
				}
			default:
				if strings.Count(prompt, marshal(initial)) != 1 || !strings.Contains(prompt, `"already_read":true`) {
					return "", errors.New("child repeated file read repeated content")
				}
				return say("Checked the file."), nil
			}
			return `{"action":"read","path":"work.md"}`, nil
		}
		parentCalls++
		switch parentCalls {
		case 1, 2:
			return `{"action":"read","path":"work.md"}`, nil
		case 3:
			if strings.Count(prompt, marshal(initial)) != 1 || !strings.Contains(prompt, `"already_read":true`) {
				return "", errors.New("parent repeated file read repeated content")
			}
			return `{"action":"delegate","task":"Check work.md"}`, nil
		case 4:
			if !strings.Contains(prompt, "Checked the file.") {
				return "", errors.New("child's check was not returned")
			}
			return marshal(map[string]string{"action": "write", "path": "work.md", "text": written}), nil
		case 5:
			if strings.Contains(prompt, newMarker) || !strings.Contains(prompt, `"action":{"action":"write","path":"work.md"}`) ||
				!strings.Contains(prompt, modelFileEditUnavailable) {
				return "", errors.New("blocked write feedback lost the redirect or echoed the submitted body")
			}
			return `{"action":"read","path":"work.md"}`, nil
		default:
			if strings.Count(prompt, marshal(initial)) != 1 || strings.Contains(prompt, newMarker) {
				return "", errors.New("blocked edit invalidated the authorized read or was echoed")
			}
			return say("Confirmed the original version."), nil
		}
	})
	if err := os.WriteFile(filepath.Join(project, "work.md"), []byte(initial), 0600); err != nil {
		t.Fatal(err)
	}
	s, err := e.Create("File evidence", project, []string{"codex"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err = e.Start(s.ID, "", "", 0); err != nil {
		t.Fatal(err)
	}
	s = settled(t, e, s.ID)
	turn := s.Rounds[0].Turns[0]
	if s.Status != "ready" || len(turn.Changes) != 0 || len(s.Operations) != 0 {
		t.Fatalf("file workflow changed: status = %s, turn error = %q", s.Status, turn.Error)
	}
}

func TestStatementBudgetAccountsForJSONEscaping(t *testing.T) {
	prior := []publicStatement{
		{Round: 1, Seat: "first", Text: strings.Repeat("猫", 2000)},
		{Round: 2, Seat: "second", Text: strings.Repeat("<", 6000)},
		{Round: 3, Seat: "third", Text: "Latest complete statement."},
	}
	packed := compactStatements(prior)
	if !packed[1].TextOmitted || packed[1].Text != "" || !strings.HasPrefix(prior[1].Text, packed[1].TextExcerpt) ||
		packed[2].Text != prior[2].Text || prior[1].TextOmitted {
		t.Fatal("escaped text escaped the budget or originals were modified")
	}
	prefix := prefixBytes(prior[0].Text, 400)
	if len(prefix) != 399 || !utf8.ValidString(prefix) {
		t.Fatal("text excerpt bisected a UTF-8 rune")
	}
}
