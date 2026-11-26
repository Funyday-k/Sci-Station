package meeting

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"testing"

	"scistation.local/desktop/internal/workspace"
)

func TestModelHandoffRetainsPublicRecordAcrossReturnAndIsolatesPrivateMemory(t *testing.T) {
	e, project := engine(t, func(context.Context, string, string, string, string) (string, error) {
		t.Fatal("building a prompt must not call the gateway")
		return "", nil
	})
	const seat = "member-1"
	s := &Session{
		Project: project,
		Members: []Member{{ID: seat, Model: "vendor/a", PreviousModel: "vendor/b", SwitchedAfterRound: 2, ModelEpoch: 2}},
		Seats:   []string{seat},
		Rounds: []Round{
			{Number: 1, Preset: "work", Phase: "work", Settings: Settings{Models: map[string]string{seat: "vendor/a"}}, Turns: []Turn{{
				Seat: seat, Status: "done", Text: "FIRST_PUBLIC", Points: []DiscussionPoint{{ID: "r1-s1-p1", Text: "FIRST_PUBLIC"}},
				Children: []Child{{Status: "done", Text: "FIRST_PRIVATE"}}, Changes: []workspace.Change{{Path: "previously-saved.txt"}},
			}}},
			{Number: 2, Preset: "work", Phase: "work", Turns: []Turn{{
				Seat: seat, Model: "vendor/b", Status: "done", Text: "SECOND_PUBLIC",
				Positions: []Position{{PointID: "r1-s1-p1", Stance: "oppose", Reason: "SECOND_PUBLIC"}},
				Children:  []Child{{Status: "done", Text: "SECOND_PRIVATE"}},
			}}},
			{Number: 3, Preset: "work", Phase: "work", Turns: []Turn{{Seat: seat, Model: "vendor/a", Status: "done", Text: "CURRENT_PUBLIC", Children: []Child{{Status: "done", Text: "CURRENT_PRIVATE"}}}}},
			{Number: 4, Preset: "work", Phase: "work", Turns: []Turn{{Seat: seat, Model: "vendor/a", Status: "running"}}},
		},
	}
	data, err := e.context(s, 0, "")
	if err != nil {
		t.Fatal(err)
	}
	statements := data["prior_statements"].([]publicStatement)
	if len(statements) != 3 || statements[0].Model != "vendor/a" || statements[1].Model != "vendor/b" || statements[1].Positions[0].PointID != "r1-s1-p1" {
		t.Fatalf("public models or point links changed: %+v", statements)
	}
	if !strings.Contains(marshal(data["peer_changes"]), "previously-saved.txt") {
		t.Fatal("the new model did not receive visible earlier work from the same seat")
	}
	if got := marshal(data["model_handoff"]); !strings.Contains(got, `"after_round":2`) || !strings.Contains(got, `"previous_model":"vendor/b"`) {
		t.Fatalf("handoff missing: %s", got)
	}
	prompt := marshal(data)
	if !strings.Contains(prompt, "CURRENT_PRIVATE") || strings.Contains(prompt, "FIRST_PRIVATE") || strings.Contains(prompt, "SECOND_PRIVATE") {
		t.Fatal("private child memory crossed a model handoff or omitted the current model's own memory")
	}
	point := continuousPoints(statements, 2).Points[0]
	if point.Model != "vendor/a" || point.Positions[seat].Model != "vendor/b" {
		t.Fatalf("compacted source lost its model: %+v", point)
	}
}

func TestModelSwitchPreservesHistoricalCitationReportAndTranscript(t *testing.T) {
	e, project := engine(t, func(context.Context, string, string, string, string) (string, error) {
		t.Fatal("inspecting frozen history must not call a model")
		return "", nil
	})
	s, err := e.CreateConfigured("Historical provenance", project, []Member{{Model: "vendor/a", Label: "First version"}}, "work")
	if err != nil {
		t.Fatal(err)
	}
	seat := s.Seats[0]
	s.Rounds = []Round{
		{Number: 1, Preset: "work", Phase: "work", Turns: []Turn{{
			Seat: seat, Model: "vendor/a", ModelLabel: "First version", Status: "done", Text: "The initial model supports the proposal.",
			Points:    []DiscussionPoint{{ID: "r1-s1-p1", Text: "The initial model supports the proposal."}},
			Positions: []Position{{PointID: "r1-s1-p1", Stance: "support", Reason: "The initial model supports the proposal."}},
		}}},
		{Number: 2, Preset: "work", Phase: "work", Settings: Settings{Models: map[string]string{seat: "vendor/b"}}, Turns: []Turn{{
			Seat: seat, Status: "done", Text: "The replacement model has reservations.",
			Positions: []Position{{PointID: "r1-s1-p1", Stance: "qualified", Reason: "The replacement model has reservations."}},
		}}},
	}
	s.Members[0].Model, s.Members[0].Label = "vendor/b", "Second version"
	s.Members[0].PreviousModel, s.Members[0].ModelEpoch, s.Members[0].SwitchedAfterRound = "vendor/a", 1, 1
	if err = e.save(s); err != nil {
		t.Fatal(err)
	}
	s, err = e.Get(s.ID)
	if err != nil {
		t.Fatal(err)
	}
	material := reportMaterials(s)
	projection, err := material.forReportPrompt()
	if err != nil {
		t.Fatal(err)
	}
	if len(projection.Sources) != 2 {
		t.Fatalf("unexpected report sources: %+v", projection.Sources)
	}
	old, current := projection.Sources[0], projection.Sources[1]
	if old.Model != "vendor/a" || old.SeatID != seat || old.Seat != "First version · 席位 1" ||
		current.Model != "vendor/b" || current.SeatID != seat || current.Seat != "Second version" {
		t.Fatalf("report projection confused current and historical speakers: old %+v, current %+v", old, current)
	}
	body := reportBody{Outcome: []reportParagraph{{
		Text:     "The first contribution supports the proposal [R1 · " + seat + "/vendor/a].",
		Evidence: []reportEvidence{{ID: old.ID, Quote: old.Text}},
	}}}
	markdown, err := body.render(projection)
	if err != nil || !strings.Contains(markdown, "第 1 轮 · First version · 席位 1（vendor/a）") {
		t.Fatalf("historical citation failed: %s, %v", markdown, err)
	}
	body.Outcome[0].Text = strings.ReplaceAll(body.Outcome[0].Text, "vendor/a", "vendor/b")
	if _, err = body.render(projection); err == nil {
		t.Fatal("accepted a citation of the old wording under the replacement model")
	}
	appendix := material.appendices()
	if !strings.Contains(appendix, "Second version（vendor/b） · 有保留") || !strings.Contains(appendix, "此前由 First version · 席位 1（vendor/a） 表态为认同") {
		t.Fatalf("position history lost the two speakers: %s", appendix)
	}
	transcript, err := e.Markdown(s.ID)
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{"模型 vendor/a", "模型 vendor/b", old.Text, current.Text} {
		if !strings.Contains(transcript, want) {
			t.Errorf("transcript omitted %q", want)
		}
	}
}

func TestLegacyEffortChangePreservesSameModelMemory(t *testing.T) {
	e, project := engine(t, func(context.Context, string, string, string, string) (string, error) {
		t.Fatal("building a prompt must not call the gateway")
		return "", nil
	})
	s := &Session{
		Project:       project,
		Seats:         []string{"codex"},
		SeatOverrides: map[string]Member{"codex": {ID: "codex", Model: "codex/main", Effort: "high", Version: 1}},
		Rounds: []Round{
			{Number: 1, Preset: "work", Phase: "work", Settings: Settings{Models: map[string]string{"codex": "main"}}, Turns: []Turn{{
				Seat: "codex", Status: "done", Text: "Same model in an older archive.", Children: []Child{{Status: "done", Text: "SAME_PROVIDER_HISTORY"}},
			}}},
			{Number: 2, Preset: "work", Phase: "work", Settings: Settings{CatalogModelIDs: map[string]bool{"codex": true}}, Turns: []Turn{{Seat: "codex", Model: "codex/main", Status: "running"}}},
		},
	}
	data, err := e.context(s, 0, "")
	if err != nil {
		t.Fatal(err)
	}
	if data["model_handoff"] != nil || !strings.Contains(marshal(data["own_private_child_memory"]), "SAME_PROVIDER_HISTORY") {
		t.Fatal("changing effort treated the legacy spelling of the same model as a replacement")
	}
	members := data["members"].([]Member)
	if len(members) != 1 || members[0].Model != "codex/main" || members[0].Effort != "high" {
		t.Fatalf("override not represented in the current roster: %+v", members)
	}
}

func TestLegacySeatOverrideAuthorsReportWithoutReassigningOldEvidence(t *testing.T) {
	e, project := engine(t, func(ctx context.Context, seat, model, prompt, _ string) (string, error) {
		var input struct {
			Stage   string
			Meeting reportMaterial
		}
		if err := json.Unmarshal([]byte(prompt), &input); err != nil {
			return "", err
		}
		if seat != "codex" || model != "vendor/replacement" || len(input.Meeting.Sources) != 1 || input.Meeting.Sources[0].Model != "codex/original" {
			return "", fmt.Errorf("report changed author or historical evidence: seat=%q, model=%q, sources=%+v", seat, model, input.Meeting.Sources)
		}
		switch input.Stage {
		case "drafting":
			return draftReply, nil
		case "reviewing":
			return reviewedReply, nil
		case "revising":
			return finalReply, nil
		}
		return "", fmt.Errorf("unexpected report stage %q", input.Stage)
	})
	s, err := e.Create("Consider the pilot", project, []string{"codex"})
	if err != nil {
		t.Fatal(err)
	}
	s.SeatOverrides = map[string]Member{"codex": {ID: "codex", Model: "vendor/replacement", Label: "Replacement", Effort: "auto", ModelEpoch: 1, SwitchedAfterRound: 1}}
	s.Rounds = []Round{{Number: 1, Turns: []Turn{{Seat: "codex", Status: "done", Model: "codex/original", Text: "I propose a limited pilot."}}}}
	if err = e.save(s); err != nil {
		t.Fatal(err)
	}
	if _, err = e.ChangeReport(s.ID, reportAction(s, "finish")); err != nil {
		t.Fatal(err)
	}
	s = reportSettled(t, e, s.ID)
	if s.Report.Status != "ready" || s.Report.AuthorModel != "vendor/replacement" || !strings.Contains(s.Report.Markdown, "codex/original") {
		t.Fatalf("legacy override or historical provenance lost: %+v", s.Report)
	}
}
