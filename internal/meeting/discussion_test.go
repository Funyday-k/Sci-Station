package meeting

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"scistation.local/desktop/internal/deliberation"
	"scistation.local/desktop/internal/workspace"
)

func discussionContext(prompt string) (map[string]any, error) {
	_, body, ok := strings.Cut(prompt, "CONTEXT:\n")
	if !ok {
		return nil, errors.New("dynamic context missing")
	}
	var data map[string]any
	err := json.NewDecoder(strings.NewReader(body)).Decode(&data)
	return data, err
}

func TestDiscussionStagesBlindReadOnlyAndSelectedSynthesis(t *testing.T) {
	for _, preset := range []string{"review", "prioritize", "forum"} {
		t.Run(preset, func(t *testing.T) {
			calls := map[string]int{}
			order := []string{}
			call := func(ctx context.Context, seat, model, prompt, path string) (string, error) {
				program := deliberation.InstructionsFrom(ctx)
				if !strings.Contains(program, "Return exactly ONE JSON object") || strings.Contains(prompt, "Return exactly ONE JSON object") {
					return "", errors.New("stable action policy was not separated from user data")
				}
				if model == seat+"/child" {
					if !strings.Contains(program, "PRIVATE read-only child") || strings.Contains(program, "current parent/chair") {
						return "", errors.New("child inherited public parent instructions")
					}
					if strings.Contains(prompt, "PRIVATE read-only child") {
						return "", errors.New("child policy duplicated in user data")
					}
					calls[model]++
					switch calls[model] {
					case 1:
						return `{"action":"write","path":"evidence.txt","text":"child-must-not-write"}`, nil
					case 2:
						return `{"action":"read","path":"evidence.txt"}`, nil
					default:
						return say("private evidence for owning parent"), nil
					}
				}
				data, err := discussionContext(prompt)
				if err != nil {
					return "", err
				}
				phase, _ := data["phase"].(string)
				round := int(data["round"].(float64))
				key := fmt.Sprintf("%s:%s:%d", seat, phase, round)
				calls[key]++
				order = append(order, key)
				if phase != "work" {
					if data["allow_edits"] != false {
						return "", errors.New("discussion context allowed writes")
					}
					if strings.Contains(prompt, "private evidence for owning parent") && seat == "cursor" {
						return "", errors.New("private child result leaked to peer")
					}
				}
				switch phase {
				case "proposal":
					if len(data["prior_statements"].([]any)) != 0 || strings.Contains(prompt, "codex independent proposal") || strings.Contains(prompt, "cursor independent proposal") {
						return "", errors.New("proposal was not blind")
					}
					if seat == "codex" {
						switch calls[key] {
						case 1:
							return `{"action":"read","path":"evidence.txt"}`, nil
						case 2:
							return `{"action":"write","path":"evidence.txt","text":"discussion-must-not-write"}`, nil
						case 3:
							if !strings.Contains(prompt, modelFileEditUnavailable) {
								return "", errors.New("write prohibition was not enforced")
							}
							return `{"action":"delegate","task":"check evidence privately"}`, nil
						case 4:
							if !strings.Contains(prompt, "private evidence for owning parent") {
								return "", errors.New("parent did not receive private report")
							}
						}
					}
					return say(seat + " independent proposal"), nil
				case "challenge":
					if !strings.Contains(prompt, "codex independent proposal") || !strings.Contains(prompt, "cursor independent proposal") {
						return "", errors.New("challenge did not receive prior proposals")
					}
					if strings.Contains(prompt, "codex current challenge") || strings.Contains(prompt, "cursor current challenge") {
						return "", errors.New("challenge leaked a same-round peer answer")
					}
					return say(seat + " current challenge"), nil
				case "synthesis":
					if !strings.Contains(prompt, "codex current challenge") || !strings.Contains(prompt, "cursor current challenge") {
						return "", errors.New("synthesis lacks verifiable preceding exchange")
					}
					return say(seat + " synthesis"), nil
				case "work":
					if data["allow_edits"] != false {
						return "", errors.New("project collaboration enabled automatic file edits")
					}
					switch calls[key] {
					case 1:
						return `{"action":"read","path":"evidence.txt"}`, nil
					case 2:
						return `{"action":"write","path":"evidence.txt","text":"work-edited"}`, nil
					default:
						if !strings.Contains(prompt, modelFileEditUnavailable) {
							return "", errors.New("legacy work write was not rejected")
						}
						return say("review completed"), nil
					}
				}
				return "", errors.New("unexpected stage")
			}
			e, project := engine(t, call)
			evidence := filepath.Join(project, "evidence.txt")
			if err := os.WriteFile(evidence, []byte("original evidence"), 0600); err != nil {
				t.Fatal(err)
			}
			s, err := e.Create("Assess evidence", project, nil)
			if err != nil {
				t.Fatal(err)
			}
			for index, stage := range []string{"proposal", "challenge", "synthesis", "synthesis"} {
				target := ""
				if index == 3 {
					target = "cursor"
				}
				if _, err = e.StartWithDiscussion(s.ID, "", target, index, preset, stage); err != nil {
					t.Fatal(err)
				}
				s = settled(t, e, s.ID)
				if s.Status != "ready" {
					t.Fatalf("%s failed: %+v", stage, s.Rounds[index].Turns)
				}
				r := s.Rounds[index]
				if r.Preset != preset || r.Phase != stage || r.Settings.AllowEdits {
					t.Fatal("stage metadata/permissions not snapshotted")
				}
				if stage == "synthesis" {
					want := "codex"
					if index == 3 {
						want = "cursor"
					}
					if len(r.Turns) != 1 || r.Turns[0].Seat != want || r.Target != want {
						t.Fatal("wrong synthesis chair")
					}
				}
			}
			body, _ := os.ReadFile(evidence)
			if string(body) != "original evidence" {
				t.Fatal("discussion or child mutated a project file")
			}
			if c := s.Rounds[0].Turns[0].Children; len(c) != 1 || c[0].Status != "done" || s.Rounds[0].Turns[0].Text == c[0].Text {
				t.Fatal("private helper became a public speaker")
			}
			if len(s.Rounds[0].Turns[1].Children) != 0 {
				t.Fatal("child attached to peer")
			}
			if _, err = e.Start(s.ID, "review the remaining evidence", "codex", 4); err != nil {
				t.Fatal(err)
			}
			s = settled(t, e, s.ID)
			body, _ = os.ReadFile(evidence)
			if s.Status != "ready" || string(body) != "original evidence" || s.Rounds[4].Preset != "work" || s.Rounds[4].Phase != "work" {
				t.Fatal("legacy collaboration round altered the file or lost its preset")
			}
			md, err := e.Markdown(s.ID)
			if err != nil || !strings.Contains(md, "Mode:") || strings.Contains(md, "private evidence for owning parent") {
				t.Fatal("mode export or child privacy failed")
			}
			// The independent visibility boundary did not alter the established scheduler.
			firstCursor := -1
			lastCodex := -1
			for i, key := range order {
				if strings.HasPrefix(key, "cursor:proposal:") {
					firstCursor = i
				}
				if strings.HasPrefix(key, "codex:proposal:") {
					lastCodex = i
				}
			}
			if firstCursor <= lastCodex {
				t.Fatal("sequential execution was changed")
			}
		})
	}
}

func TestDiscussionRetainsFailureAndAbsenceWithoutPartialOpinions(t *testing.T) {
	e, project := engine(t, func(ctx context.Context, seat, model, prompt, path string) (string, error) {
		data, err := discussionContext(prompt)
		if err != nil {
			return "", err
		}
		if strings.Contains(prompt, "INCOMPLETE POSITION") {
			return "", errors.New("partial response treated as an opinion")
		}
		statements := data["prior_statements"].([]any)
		if len(statements) != 2 {
			return "", fmt.Errorf("got %d preceding opinions", len(statements))
		}
		records := data["public_participation"].([]any)
		failed, absent := false, false
		for _, value := range records {
			r := value.(map[string]any)
			if r["seat"] == "cursor" && r["status"] == "error" {
				failed = true
			}
			if r["seat"] == "cursor" && r["status"] == "absent" {
				absent = true
			}
		}
		if !failed || !absent {
			return "", errors.New("failure/absence identity was removed")
		}
		return say("Qualified synthesis"), nil
	})
	s, err := e.Create("honest record", project, nil)
	if err != nil {
		t.Fatal(err)
	}
	err = e.locked(func() error {
		old, err := e.load(s.ID)
		if err != nil {
			return err
		}
		old.Rounds = []Round{{Number: 1, Turns: []Turn{{Seat: "codex", Model: "old-codex", Status: "done", Text: "Verified old position"}, {Seat: "cursor", Model: "old-cursor", Status: "error", Text: "INCOMPLETE POSITION"}}}, {Number: 2, Target: "codex", Turns: []Turn{{Seat: "codex", Model: "old-codex", Status: "done", Text: "Verified followup"}}}}
		return e.save(old)
	})
	if err != nil {
		t.Fatal(err)
	}
	// Simulate a saved pre-preset session, without rewriting the old public text.
	file := filepath.Join(e.dir, s.ID+".json")
	b, _ := os.ReadFile(file)
	var legacy map[string]any
	json.Unmarshal(b, &legacy)
	for _, value := range legacy["rounds"].([]any) {
		r := value.(map[string]any)
		delete(r, "preset")
		delete(r, "phase")
	}
	b, _ = json.Marshal(legacy)
	if err = os.WriteFile(file, b, 0600); err != nil {
		t.Fatal(err)
	}
	loaded, err := e.Get(s.ID)
	if err != nil {
		t.Fatal(err)
	}
	if loaded.Rounds[0].Preset != "work" || loaded.Rounds[0].Phase != "work" || loaded.Rounds[0].Turns[0].Text != "Verified old position" {
		t.Fatal("legacy session defaults or text changed")
	}
	if _, err = e.StartWithDiscussion(s.ID, "", "cursor", 2, "review", "synthesis"); err != nil {
		t.Fatal(err)
	}
	loaded = settled(t, e, s.ID)
	if loaded.Status != "ready" {
		t.Fatal(loaded.Rounds[2].Turns[0].Error)
	}
	if _, err = e.StartWithDiscussion(s.ID, "", "", 3, "unknown", "proposal"); err == nil {
		t.Fatal("unknown preset accepted")
	}
	loaded, _ = e.Get(s.ID)
	if len(loaded.Rounds) != 3 {
		t.Fatal("invalid plan modified session")
	}
}

func TestIndependentContextExcludesCurrentPeerArtifacts(t *testing.T) {
	e, project := engine(t, func(context.Context, string, string, string, string) (string, error) { return say("unused"), nil })
	s := &Session{Project: project, Seats: []string{"codex", "cursor"}, Rounds: []Round{
		{Number: 1, Preset: "work", Phase: "work", Turns: []Turn{{Seat: "codex", Model: "old-model", Status: "done", Text: "PAST_PUBLIC"}}},
		{Number: 2, Preset: "review", Phase: "challenge", Settings: testSettings(), Turns: []Turn{
			{Seat: "codex", Model: "codex/main", Status: "done", Text: "CURRENT_PEER_PUBLIC", Changes: []workspace.Change{{Path: "current-peer.md", Diff: "CURRENT_PEER_DIFF"}}, Children: []Child{{Status: "done", Text: "CURRENT_PEER_PRIVATE"}}},
			{Seat: "cursor", Model: "cursor/main", Status: "running"},
		}},
	}, Operations: []Operation{{Seat: "codex", Round: 2, Path: "current-peer.md", Text: "CURRENT_PEER_OPERATION", Status: "unknown"}}}
	data, err := e.context(s, 1, "")
	if err != nil {
		t.Fatal(err)
	}
	encoded := marshal(data)
	if !strings.Contains(encoded, "PAST_PUBLIC") || strings.Contains(encoded, "CURRENT_PEER_") {
		t.Fatalf("same-round peer artifact leaked: %s", encoded)
	}
}

func TestDiscussionRequestDoesNotInterruptRunningLegacyWork(t *testing.T) {
	started, release := make(chan struct{}), make(chan struct{})
	cancelled := make(chan struct{}, 1)
	e, project := engine(t, func(ctx context.Context, seat, model, prompt, path string) (string, error) {
		close(started)
		select {
		case <-release:
			return say("original work finished"), nil
		case <-ctx.Done():
			cancelled <- struct{}{}
			return "", ctx.Err()
		}
	})
	s, err := e.Create("existing work", project, []string{"codex"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err = e.Start(s.ID, "", "", 0); err != nil {
		t.Fatal(err)
	}
	select {
	case <-started:
	case <-time.After(time.Second):
		t.Fatal("legacy work did not start")
	}
	_, err = e.StartWithDiscussion(s.ID, "do not interrupt", "", 1, "review", "proposal")
	if !errors.Is(err, ErrConflict) {
		close(release)
		t.Fatalf("live work accepted another stage: %v", err)
	}
	select {
	case <-cancelled:
		close(release)
		t.Fatal("discussion request cancelled existing work")
	default:
	}
	close(release)
	s = settled(t, e, s.ID)
	if s.Status != "ready" || len(s.Rounds) != 1 || s.Rounds[0].Preset != "work" || s.Rounds[0].Turns[0].Text != "original work finished" {
		t.Fatal("existing work was disturbed")
	}
}

func TestDiscussionRetainsOriginalPriorHostNotesAsUserData(t *testing.T) {
	const oldNote = "成本权重 70%，只考虑 48 小时内可完成的选项。"
	const middleNote = "保留少数意见；不把票数当证据。"
	const latestNote = "依据此前权重进行汇总。"
	e, project := engine(t, func(ctx context.Context, seat, model, prompt, path string) (string, error) {
		program := deliberation.InstructionsFrom(ctx)
		if strings.Contains(program, oldNote) || strings.Contains(program, middleNote) || strings.Contains(program, latestNote) {
			return "", errors.New("host input became policy")
		}
		data, err := discussionContext(prompt)
		if err != nil {
			return "", err
		}
		rounds := data["prior_rounds"].([]any)
		if len(rounds) != 2 {
			return "", errors.New("prior_rounds includes current stage or omits history")
		}
		first, second := rounds[0].(map[string]any), rounds[1].(map[string]any)
		if first["round"] != float64(1) || first["preset"] != "work" || first["phase"] != "work" || first["target"] != "codex" || first["host_note"] != oldNote {
			return "", errors.New("legacy host note or default stage lost")
		}
		if second["preset"] != "prioritize" || second["phase"] != "challenge" || second["host_note"] != middleNote {
			return "", errors.New("intermediate host constraints or stage lost")
		}
		if data["latest_instruction"] != latestNote {
			return "", errors.New("latest instruction changed")
		}
		return say("Ranked with original constraints"), nil
	})
	s, err := e.Create("prioritize options", project, nil)
	if err != nil {
		t.Fatal(err)
	}
	err = e.locked(func() error {
		old, err := e.load(s.ID)
		if err != nil {
			return err
		}
		old.Rounds = []Round{
			{Number: 1, Target: "codex", Note: oldNote, Turns: []Turn{{Seat: "codex", Model: "codex/main", Status: "done", Text: "first position"}}},
			{Number: 2, Preset: "prioritize", Phase: "challenge", Note: middleNote, Turns: []Turn{{Seat: "cursor", Model: "cursor/main", Status: "done", Text: "checked weights"}}},
		}
		return e.save(old)
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err = e.StartWithDiscussion(s.ID, latestNote, "", 2, "prioritize", "synthesis"); err != nil {
		t.Fatal(err)
	}
	s = settled(t, e, s.ID)
	if s.Status != "ready" {
		t.Fatal(s.Rounds[2].Turns[0].Error)
	}
	if s.Rounds[0].Note != oldNote || s.Rounds[1].Note != middleNote {
		t.Fatal("original host notes were rewritten")
	}
}
