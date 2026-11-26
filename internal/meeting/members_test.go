package meeting

import (
	"context"
	"errors"
	"strings"
	"testing"

	"scistation.local/desktop/internal/deliberation"
)

func TestConfiguredMembersKeepIndependentIdentityAndPrivateHelpers(t *testing.T) {
	var parentSteps int
	var requests []string
	e, project := engine(t, func(ctx context.Context, seat, model, prompt, executable string) (string, error) {
		effort, session := ModelRequest(ctx)
		requests = append(requests, session)
		if model != "shared/model" || executable != "" {
			return "", errors.New("unexpected model or executable")
		}
		if strings.HasPrefix(prompt, "TITLE REQUEST:") {
			if seat != "member-1" || effort != "high" || !strings.HasSuffix(session, "-title") || deliberation.InstructionsFrom(ctx) != "" {
				return "", errors.New("wrong first-seat title context")
			}
			return "Title check", nil
		}
		if strings.HasPrefix(prompt, "PRIVATE TASK:") {
			if seat != "member-1" || effort != "high" || !strings.Contains(deliberation.InstructionsFrom(ctx), "PRIVATE read-only child") {
				return "", errors.New("private helper lost its settings")
			}
			return say("private evidence"), nil
		}
		if seat == "member-2" && effort == "auto" {
			if strings.Contains(prompt, "private evidence") {
				return "", errors.New("private child result leaked to another seat")
			}
			return say("second position"), nil
		}
		if seat != "member-1" || effort != "high" {
			return "", errors.New("wrong parent effort")
		}
		parentSteps++
		if parentSteps == 1 {
			return `{"action":"delegate","task":"inspect one detail"}`, nil
		}
		return say("parent position"), nil
	})
	created, err := e.CreateConfigured("Choose an option", project, []Member{
		{ID: "fake", Model: "shared/model", Source: "shared", Label: "Shared", Effort: "high"},
		{Model: "shared/model", Source: "shared", Label: "Shared"},
	}, "review")
	if err != nil {
		t.Fatal(err)
	}
	if len(requests) != 0 || created.Members[0].ID != "member-1" || created.Members[1].Effort != "auto" || created.Preset != "review" {
		t.Fatalf("create=%+v", created)
	}
	if _, err = e.StartWithDiscussion(created.ID, "", "Shared", 0, "review", "proposal"); err == nil {
		t.Fatal("allowed ambiguous target")
	}
	if _, err = e.GenerateTitle(context.Background(), created.ID); err != nil {
		t.Fatal(err)
	}
	if _, err = e.StartWithDiscussion(created.ID, "", "", 0, "review", "proposal"); err != nil {
		t.Fatal(err)
	}
	got := settled(t, e, created.ID)
	first, second := got.Rounds[0].Turns[0], got.Rounds[0].Turns[1]
	if got.Status != "ready" || first.Effort != "high" || second.Effort != "auto" || len(first.Children) != 1 || first.Children[0].Effort != "high" || first.Children[0].Model != first.Model {
		t.Fatalf("members: %+v %+v", first, second)
	}
	if len(requests) != 5 || requests[0] == requests[1] || requests[1] != requests[3] || requests[2] == requests[1] || requests[3] == requests[4] {
		t.Fatal("request contexts were shared or lost", requests)
	}
	list, err := e.List()
	if err != nil || len(list) != 1 || len(list[0].Members) != 2 || list[0].Preset != "review" {
		t.Fatalf("lost summary members or preset %v %v", list, err)
	}
}
