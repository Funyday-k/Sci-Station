package meeting

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"testing"

	"scistation.local/desktop/internal/deliberation"
)

func TestDiscussionPointsSurviveRoundsWithIndependentAttribution(t *testing.T) {
	const firstID = "r1-s1-p1"
	const secondID = "r1-s1-p2"
	peerCalls := 0
	e, project := engine(t, func(ctx context.Context, seat, model, prompt, path string) (string, error) {
		if model == "cursor/child" {
			return `{"action":"say","text":"Private child proposal.","points":[{"text":"Private child proposal."}]}`, nil
		}
		data, err := discussionContext(prompt)
		if err != nil {
			return "", err
		}
		prior := data["prior_statements"].([]any)
		switch data["phase"] {
		case "proposal":
			if len(prior) != 0 {
				return "", errors.New("a peer's live statement appeared in independent submission")
			}
			if seat == "codex" {
				return `{"action":"say","text":"Retain independent rounds. I support them because early answers stay private. Should we test two rounds?","points":[{"text":"Retain independent rounds.","stance":"support","reason":"I support them because early answers stay private."},{"text":"Should we test two rounds?"}]}`, nil
			}
			peerCalls++
			switch peerCalls {
			case 1:
				return `{"action":"delegate","task":"Check independently"}`, nil
			case 2:
				return `{"action":"say","text":"My guess.","positions":[{"point_id":"r1-s1-p1","stance":"support","reason":"My guess."}]}`, nil
			default:
				if !strings.Contains(prompt, "prior_statements 中可见") {
					return "", errors.New("guessed ID did not receive a correction")
				}
				return say("No additional proposal."), nil
			}
		case "challenge":
			if len(prior) != 2 || strings.Contains(marshal(prior), "Private child proposal") {
				return "", errors.New("earlier public record or child isolation was lost")
			}
			origin := prior[0].(map[string]any)
			if origin["seat"] != "codex" || origin["model"] != "codex/main" || origin["points"].([]any)[0].(map[string]any)["id"] != firstID {
				return "", fmt.Errorf("incorrect provenance in preceding statement %v", origin)
			}
			if seat == "codex" {
				return `{"action":"say","text":"I now have a reservation about the cost.","positions":[{"point_id":"r1-s1-p1","stance":"qualified","reason":"I now have a reservation about the cost."}]}`, nil
			}
			if strings.Contains(marshal(prior), "a reservation about the cost") {
				return "", errors.New("a same-round position leaked")
			}
			return `{"action":"say","text":"I oppose independent rounds on urgent jobs. I need timing evidence before deciding on two rounds.","positions":[{"point_id":"r1-s1-p1","stance":"oppose","reason":"I oppose independent rounds on urgent jobs."},{"point_id":"r1-s1-p2","stance":"undecided","reason":"I need timing evidence before deciding on two rounds."}]}`, nil
		}
		return "", errors.New("unexpected phase")
	})
	s, err := e.Create("Compare discussion designs", project, nil)
	if err != nil {
		t.Fatal(err)
	}
	for index, phase := range []string{"proposal", "challenge"} {
		if _, err := e.StartWithDiscussion(s.ID, "", "", index, "review", phase); err != nil {
			t.Fatal(err)
		}
		s = settled(t, e, s.ID)
		if s.Status != "ready" {
			t.Fatalf("%s did not finish: %+v", phase, s.Rounds[index].Turns)
		}
	}
	origin, silent := s.Rounds[0].Turns[0], s.Rounds[0].Turns[1]
	if len(origin.Points) != 2 || origin.Points[0].ID != firstID || origin.Points[1].ID != secondID || len(origin.Positions) != 1 || origin.Positions[0].Stance != "support" || origin.Positions[0].PointID != firstID {
		t.Fatalf("lost proposed points or inferred support from a question: %+v", origin)
	}
	if len(silent.Points) != 0 || len(silent.Positions) != 0 || len(silent.Children) != 1 || silent.Children[0].Text != "Private child proposal." {
		t.Fatalf("silence, private advice or guessed ID got credit: %+v", silent)
	}
	first, second := s.Rounds[1].Turns[0], s.Rounds[1].Turns[1]
	if len(first.Positions) != 1 || first.Positions[0].Stance != "qualified" || first.Positions[0].PointID != firstID || len(second.Positions) != 2 || second.Positions[0].Stance != "oppose" || second.Positions[1].PointID != secondID || second.Positions[1].Stance != "undecided" {
		t.Fatalf("wrong attribution or change of stance: %+v %+v", first, second)
	}
}

func TestPositionsRequireRealPublicExcerptsAndVisibleIDs(t *testing.T) {
	invalid := []string{
		`"points":[{"text":"Invented claim."}]`,
		`"points":[{"text":"My actual statement.","id":"invented"}]`,
		`"points":[{"text":"My actual statement.","stance":"yes","reason":"My actual statement."}]`,
		`"points":[{"text":"My actual statement.","stance":"support"}]`,
		`"positions":[{"point_id":"known","seat":"someone else","stance":"oppose","reason":"My actual statement."}]`,
		`"positions":[{"point_id":"known","stance":"support","stance":"oppose","reason":"My actual statement."}]`,
		`"positions":[{"point_id":"unknown","stance":"oppose","reason":"My actual statement."}]`,
		`"positions":[{"point_id":"known","stance":"oppose","reason":"Fabricated quotation."}]`,
		`"positions":[{"point_id":"known","stance":"support","reason":"My actual statement."},{"point_id":"known","stance":"oppose","reason":"My actual statement."}]`,
	}
	for _, field := range invalid {
		a, err := decodeAction(`{"action":"say","text":"My actual statement.",` + field + `}`)
		if err != nil {
			t.Fatal(err)
		}
		if points, positions, err := parsePositions(a, map[string]bool{"known": true}, 2, 1); err == nil || len(points)+len(positions) != 0 {
			t.Errorf("accepted invalid field %s", field)
		}
	}
	old, err := decodeAction(say("Prior unstructured statement."))
	if err != nil {
		t.Fatal(err)
	}
	points, positions, err := parsePositions(old, nil, 1, 0)
	if err != nil || len(points)+len(positions) != 0 {
		t.Fatal("plain say gained a position")
	}
}

func TestProposalRequiresObservableAcceptanceCriterion(t *testing.T) {
	plan, err := deliberation.Resolve("review", "proposal")
	if err != nil || !strings.Contains(plan.Instructions(), "observable acceptance criterion") {
		t.Fatal("proposal instructions no longer require a checkable acceptance criterion")
	}
}
