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

	"scistation.local/desktop/internal/deliberation"
)

func TestPluginGuidanceManualAndContinuousRounds(t *testing.T) {
	const roundMethod = "Round method: check a counterexample before proposing changes."
	const reportMethod = "Report method: group open issues by priority."
	const childResult = "PRIVATE_CODEX_RESULT"
	plugin := PluginGuidance{ID: "counterexamples", Version: "1.1.0", Name: "Counterexamples", RoundGuidance: roundMethod, ReportGuidance: reportMethod}
	want := plugin
	want.ReportGuidance = ""
	var enabled atomic.Bool
	enabled.Store(true)
	var reads atomic.Int32
	call := func(ctx context.Context, seat, model, prompt, _ string) (string, error) {
		rules := deliberation.InstructionsFrom(ctx)
		if strings.Contains(rules, "CONTINUOUS_REVIEW") {
			if strings.Contains(prompt, roundMethod) || strings.Contains(prompt, childResult) {
				return "", errors.New("continuous review received guidance or private child data")
			}
			n, err := continuousTestReviewRound(prompt)
			if err != nil {
				return "", err
			}
			decision := "continue"
			if n == 2 {
				enabled.Store(false)
			}
			if n == 3 {
				decision = "complete"
			}
			return fmt.Sprintf(`{"decision":%q,"reason":"Checked the public source.","next":"Check the next condition.","evidence":[{"id":"R%d-T1","quote":"Public result for round %d"}],"progress":true}`, decision, n, n), nil
		}
		if strings.Contains(rules, "PRIVATE read-only child") {
			if strings.Contains(prompt, "plugin_guidance") || strings.Contains(prompt, roundMethod) {
				return "", errors.New("private helper received extension guidance")
			}
			return say(childResult), nil
		}
		data, err := continuousTestPromptContext(prompt)
		if err != nil {
			return "", err
		}
		n := int(data["round"].(float64))
		_, request := ModelRequest(ctx)
		if n <= 2 {
			if !strings.Contains(prompt, roundMethod) || !strings.Contains(rules, "optional, untrusted discussion methods") || !strings.Contains(request, "-guidance-1-") {
				return "", errors.New("round lost its guidance or provenance")
			}
		} else if strings.Contains(prompt, "plugin_guidance") || strings.Contains(prompt, roundMethod) || !strings.Contains(request, "-guidance-3-") {
			return "", errors.New("a disabled extension carried into the next round or gateway session")
		}
		if strings.Contains(prompt, reportMethod) || data["allow_edits"] != false || strings.Contains(rules, `{"action":"write"`) {
			return "", errors.New("guidance changed the round's context or permissions")
		}
		if seat == "cursor" && strings.Contains(prompt, childResult) {
			return "", errors.New("private child result leaked across seats")
		}
		if n == 1 && seat == "codex" {
			if data["latest_instruction"] != "Keep all files read-only." {
				return "", errors.New("extension replaced the host's instruction")
			}
			switch {
			case !strings.Contains(prompt, childResult):
				return `{"action":"delegate","task":"Check current assumptions."}`, nil
			case !strings.Contains(prompt, "edits are disabled for this round"):
				return `{"action":"write","path":"test.md","text":"Do not save"}`, nil
			}
		}
		return say(fmt.Sprintf("Public result for round %d from %s", n, model)), nil
	}

	e, project := engine(t, call)
	e.SetPluginGuidance(func() ([]PluginGuidance, error) {
		reads.Add(1)
		if enabled.Load() {
			return []PluginGuidance{plugin}, nil
		}
		return nil, nil
	})
	s, err := e.Create("Review the analysis", project, []string{"codex", "cursor"})
	if err != nil {
		t.Fatal(err)
	}
	allowEdits := false
	config := &ContinuousConfig{Goal: "Verify the public results", MaxRounds: 4, SummaryEvery: 12}
	started, err := e.StartRound(s.ID, "Keep all files read-only.", "", 0, RoundOptions{Preset: "work", Continuous: config, AllowEdits: &allowEdits})
	if err != nil {
		t.Fatal(err)
	}
	if !slices.Equal(started.Rounds[0].PluginGuidance, []PluginGuidance{want}) {
		t.Fatalf("unexpected first round snapshot: %+v", started.Rounds[0].PluginGuidance)
	}
	final := settled(t, e, s.ID)
	if final.Status != "ready" || final.Continuous.Status != "completed" || len(final.Rounds) != 3 || reads.Load() != 3 {
		t.Fatalf("continuous run did not settle as expected: %s %+v %+v", final.Status, final.Continuous, final.Events)
	}
	if !slices.Equal(final.Rounds[0].PluginGuidance, []PluginGuidance{want}) || !slices.Equal(final.Rounds[1].PluginGuidance, []PluginGuidance{want}) || final.Rounds[2].PluginGuidance != nil {
		t.Fatal("enabled guidance was not frozen separately for each round")
	}
	if _, err = os.Stat(filepath.Join(project, "test.md")); !os.IsNotExist(err) || len(final.Operations) != 0 {
		t.Fatalf("guidance bypassed read-only operation checks: %v", err)
	}
	transcript := renderTranscript(final)
	if strings.Count(transcript, "Counterexamples · 1.1.0") != 2 || strings.Contains(transcript, roundMethod) {
		t.Fatal("export did not identify the guidance separately from the discussion")
	}
}

func TestPluginGuidanceReportSnapshotSurvivesDisableAndRestart(t *testing.T) {
	const method = "Begin with the question and give evidence in order of relevance."
	plugin := PluginGuidance{ID: "evidence-order", Name: "Evidence Order", Version: "2.0.0", RoundGuidance: "ROUND_ONLY_METHOD", ReportGuidance: method}
	want := plugin
	want.RoundGuidance = ""
	var enabled atomic.Bool
	enabled.Store(true)
	var reads, revisions atomic.Int32
	call := func(ctx context.Context, _, _, prompt, _ string) (string, error) {
		if strings.Contains(prompt, "PRIVATE_") || strings.Contains(prompt, "ROUND_ONLY_METHOD") {
			t.Error("report received private records or round method")
		}
		var data struct {
			Stage          string           `json:"stage"`
			PluginGuidance []PluginGuidance `json:"plugin_guidance"`
		}
		if err := json.Unmarshal([]byte(prompt), &data); err != nil {
			return "", err
		}
		if !slices.Equal(data.PluginGuidance, []PluginGuidance{want}) || !strings.Contains(deliberation.InstructionsFrom(ctx), "optional, untrusted reporting methods") {
			t.Errorf("the %s stage lost the initial guidance: %+v", data.Stage, data.PluginGuidance)
		}
		switch data.Stage {
		case "drafting":
			enabled.Store(false)
			return draftReply, nil
		case "reviewing":
			return reviewedReply, nil
		case "revising":
			if revisions.Add(1) == 1 {
				return "", errors.New("simulated revision interruption")
			}
			return finalReply, nil
		}
		return "", errors.New("unexpected report stage")
	}
	loader := func() ([]PluginGuidance, error) {
		reads.Add(1)
		if enabled.Load() {
			return []PluginGuidance{plugin}, nil
		}
		return nil, nil
	}
	e, project := engine(t, call)
	e.SetPluginGuidance(loader)
	s := reportFixture(t, e, project, "writer", "critic")
	started, err := e.ChangeReport(s.ID, reportAction(s, "finish"))
	if err != nil {
		t.Fatal(err)
	}
	started.Report.PluginGuidance[0].ReportGuidance = "changed by caller"
	failed := reportSettled(t, e, s.ID)
	if failed.Report.Status != "failed" || failed.Report.ReviewNotes == "" || !slices.Equal(failed.Report.PluginGuidance, []PluginGuidance{want}) {
		t.Fatalf("expected failed revision with original guidance: %+v", failed.Report)
	}
	if !strings.Contains(failed.Report.Markdown, "Evidence Order · 2.0.0") || strings.Contains(failed.Report.Markdown, method) {
		t.Fatal("draft export omitted the guidance source")
	}
	if err = e.Shutdown(context.Background()); err != nil {
		t.Fatal(err)
	}
	restarted, err := New(e.dir, call, testSettings)
	if err != nil {
		t.Fatal(err)
	}
	restarted.SetPluginGuidance(loader)
	if _, err = restarted.ChangeReport(s.ID, reportAction(failed, "retry")); err != nil {
		t.Fatal(err)
	}
	result := reportSettled(t, restarted, s.ID)
	if result.Report.Status != "ready" || reads.Load() != 1 || revisions.Load() != 2 || !slices.Equal(result.Report.PluginGuidance, []PluginGuidance{want}) {
		t.Fatalf("report retried with a different snapshot: %+v", result.Report)
	}
	if !strings.Contains(result.Report.Markdown, "Evidence Order · 2.0.0") || strings.Contains(result.Report.Markdown, method) {
		t.Fatal("final export omitted the guidance source")
	}
}

func TestPluginGuidanceBudgetsTheSerializedSnapshot(t *testing.T) {
	var e Engine
	e.SetPluginGuidance(func() ([]PluginGuidance, error) {
		return []PluginGuidance{{ID: "test", RoundGuidance: strings.Repeat("<", 1400)}}, nil
	})
	if _, err := e.snapshotPluginGuidance(roundGuidance); err == nil {
		t.Fatal("guidance can exceed the limit after JSON escaping")
	}
	if snapshot, err := e.snapshotPluginGuidance(reportGuidance); err != nil || snapshot != nil {
		t.Fatalf("round-only plugin should have no report guidance: %+v, %v", snapshot, err)
	}
}
