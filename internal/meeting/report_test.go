package meeting

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"scistation.local/desktop/internal/deliberation"
	"scistation.local/desktop/internal/workspace"
)

func reportAction(s *Session, action string) ReportAction {
	n := len(s.Rounds)
	a := ReportAction{Action: action, ExpectedRound: &n, AgendaVersion: &s.AgendaVersion}
	if action == "retry" {
		a.Attempt = &s.Report.Attempt
	}
	return a
}

func reportSettled(t *testing.T, e *Engine, id string) *Session {
	t.Helper()
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		s, err := e.Get(id)
		if err != nil {
			t.Fatal(err)
		}
		if s.Report != nil && !s.Report.active() {
			return s
		}
		time.Sleep(time.Millisecond)
	}
	t.Fatal("report did not settle")
	return nil
}

const draftReply = `{"outcome":[{"text":"Keep the pilot.","evidence":[{"id":"R1-T1","quote":"I propose a limited pilot"}]}]}`
const reviewedReply = `{"accuracy":"The pilot is proposed, not approved.","readability":"Name the missing approval in the opening.","evidence":[{"id":"R1-T1","quote":"a limited pilot"}]}`
const finalReply = `{"outcome":[{"text":"The first seat proposes a limited pilot. Approval remains open.","evidence":[{"id":"R1-T1","quote":"I propose a limited pilot"}]}]}`

func reportFixture(t *testing.T, e *Engine, project string, models ...string) *Session {
	t.Helper()
	members := []Member{}
	for _, model := range models {
		members = append(members, Member{Model: model, Effort: "high"})
	}
	s, err := e.CreateConfigured("Assess pilot", project, members, "review", AgendaInput{Title: "decide on pilot", Kind: "discussion"})
	if err != nil {
		t.Fatal(err)
	}
	s.Rounds = []Round{{Number: 1, Note: "Check readiness", Turns: []Turn{{Seat: "member-1", Model: models[0], Status: "done", Text: "I propose a limited pilot.", Points: []DiscussionPoint{{ID: "p1", Text: "a limited pilot"}}, Positions: []Position{{PointID: "p1", Stance: "support", Reason: "I propose a limited pilot"}}, Children: []Child{{Text: "PRIVATE_CHILD"}}, Reads: map[string]workspace.File{"hidden": {Text: "PRIVATE_READ"}}, Changes: []workspace.Change{{Path: "result.txt", Before: "b", After: "a", Diff: "PRIVATE_FULL_DIFF"}}}}}}
	s.Events = append(s.Events, Event{RawExcerpt: "PRIVATE_DIAGNOSTIC"})
	s.UserChanges = []UserChange{{Change: workspace.Change{Path: "instructions.md", Before: "b", After: "c", Diff: "PRIVATE_USER_DIFF"}}}
	s.Operations = []Operation{{Text: "PRIVATE_OP_BODY"}}
	if len(models) > 1 {
		s.Rounds[0].Turns = append(s.Rounds[0].Turns, Turn{Seat: "member-2", Model: models[1], Status: "done", Text: "I prefer to wait.", Positions: []Position{{PointID: "p1", Stance: "oppose", Reason: "I prefer to wait."}}})
	}
	if err = e.locked(func() error { return e.save(s) }); err != nil {
		t.Fatal(err)
	}
	return s
}

func TestReportDiscussionAndFrozenMeeting(t *testing.T) {
	const hostAnnotation = "Confirm capacity with the host."
	const hostAgenda = "Clarify the pilot approval conditions"
	const annotatedFinalReply = `{"outcome":[{"text":"The first seat proposes a limited pilot. Approval remains open.","evidence":[{"id":"R1-T1","quote":"I propose a limited pilot"}]}],"open":[{"text":"The host requested a capacity check.","evidence":[{"id":"B1","quote":"Confirm capacity with the host."}]}]}`
	started := make(chan struct{})
	proceed := make(chan struct{})
	var calls atomic.Int32
	call := func(ctx context.Context, seat, model, prompt, _ string) (string, error) {
		calls.Add(1)
		var p struct {
			Stage, Draft string
			ReviewNotes  string `json:"review_notes"`
			Meeting      reportMaterial
		}
		if err := json.Unmarshal([]byte(prompt), &p); err != nil {
			return "", err
		}
		for _, secret := range []string{"PRIVATE_", "/private/", "cli_paths", "workspace_catalog", "imported_project_reference"} {
			if strings.Contains(prompt, secret) {
				return "", errors.New("unexpected private material")
			}
		}
		for _, need := range []string{"I propose a limited pilot", "I prefer to wait", "instructions.md", "result.txt", hostAgenda, "Check readiness", "oppose"} {
			if !strings.Contains(prompt, need) {
				return "", errors.New("missing source: " + need)
			}
		}
		rules := deliberation.InstructionsFrom(ctx)
		if !strings.Contains(rules, "explicit point positions") || !strings.Contains(rules, "Attribute") || !strings.Contains(rules, "attribute the wording to the host") {
			return "", errors.New("report policy missing")
		}
		foundAnnotation, foundEditedAgenda := false, false
		for _, source := range p.Meeting.Sources {
			if source.ID == "B1" && source.Kind == "host_board" && source.Seat == "主持人" && source.Text == hostAnnotation && source.TargetID == "p1" && source.Target == "观点 · R1-T1" {
				foundAnnotation = true
			}
			if source.ID == "A1" && source.Kind == "agenda" && source.Seat == "主持人" && source.Text == hostAgenda {
				foundEditedAgenda = true
			}
		}
		if !foundAnnotation || p.Meeting.BoardScope == "" {
			return "", errors.New("host annotation was not separated from the original public statement")
		}
		if !foundEditedAgenda {
			return "", errors.New("host-edited agenda was not attributed to the editor in the report")
		}
		switch p.Stage {
		case "drafting":
			if seat != "member-1" || model != "writer" {
				return "", errors.New("wrong author")
			}
			close(started)
			select {
			case <-proceed:
			case <-ctx.Done():
				return "", ctx.Err()
			}
			return draftReply, nil
		case "reviewing":
			if seat != "member-3" || model != "critic" || !strings.Contains(p.Draft, "Keep the pilot") {
				return "", errors.New("reviewer did not see draft")
			}
			return reviewedReply, nil
		case "revising":
			if seat != "member-1" || model != "writer" || !strings.Contains(p.Draft, "Keep the pilot") || !strings.Contains(p.ReviewNotes, "Name the missing approval") {
				return "", errors.New("revision lost the review")
			}
			return annotatedFinalReply, nil
		}
		return "", errors.New("unexpected call")
	}
	e, project := engine(t, call)
	e.SetProjectContext(func(string) string { t.Error("report read project context"); return "" })
	s := reportFixture(t, e, project, "writer", "writer", "critic")
	s.Agenda[0].Source, s.Agenda[0].SourceSeat = "chair", "member-1"
	if err := e.locked(func() error { return e.save(s) }); err != nil {
		t.Fatal(err)
	}
	body, scope, zero := hostAnnotation, hostAgenda, 0
	s, err := e.ChangeBoard(s.ID, HostBoardChange{Op: "annotate_point", PointID: "p1", Body: &body, ExpectedVersion: &zero})
	if err != nil {
		t.Fatal(err)
	}
	s, err = e.ChangeBoard(s.ID, HostBoardChange{Op: "edit_agenda", ItemID: s.Agenda[0].ID, Title: &scope, ExpectedVersion: &zero})
	if err != nil {
		t.Fatal(err)
	}
	start := reportAction(s, "finish")
	active, err := e.ChangeReport(s.ID, start)
	if err != nil || active.Status != "closed" || active.Report.Status != "drafting" {
		t.Fatal(active, err)
	}
	select {
	case <-started:
	case <-time.After(time.Second):
		t.Fatal("author did not run")
	}
	other, err := New(e.dir, call, testSettings)
	if err != nil {
		t.Fatal(err)
	}
	dup, err := other.ChangeReport(s.ID, start)
	if err != nil || dup.Report.Attempt != 1 || dup.Report.Status != "drafting" {
		t.Fatal(dup, err)
	}
	if _, err = other.Start(s.ID, "", "", 1); !errors.Is(err, ErrConflict) {
		t.Fatal(err)
	}
	if _, err = other.UserWrite(s.ID, "should-not-exist", "oops", "missing"); !errors.Is(err, ErrConflict) {
		t.Fatal(err)
	}
	if _, err = other.ChangeAgenda(s.ID, AgendaChange{Action: "complete", ItemID: s.Agenda[0].ID, ExpectedVersion: &s.AgendaVersion}); !errors.Is(err, ErrConflict) {
		t.Fatal(err)
	}
	if _, err = other.StartAgendaDraft(s.ID, &s.AgendaVersion); !errors.Is(err, ErrConflict) {
		t.Fatal(err)
	}
	if _, err = other.GenerateTitle(context.Background(), s.ID); !errors.Is(err, ErrConflict) {
		t.Fatal(err)
	}
	close(proceed)
	s = reportSettled(t, e, s.ID)
	if r := s.Report; r.Status != "ready" || r.ReviewMode != "peer" || r.SourceCount != 2 || calls.Load() != 3 {
		t.Fatal(r, calls.Load())
	}
	for _, want := range []string{"（定稿）", "Approval remains open", "[R1-T1]", "[R1-T2]", "认同", "不认同", "[F1]", "[F2]", "待处理", "writer · 席位 1", "writer · 席位 2", "critic · 未表态", "The host requested a capacity check. [B1]", "主持人议题板笔记与批注", hostAnnotation} {
		if !strings.Contains(s.Report.Markdown, want) {
			t.Errorf("missing %q", want)
		}
	}
	if strings.Contains(s.Report.Markdown, "Keep the pilot.") {
		t.Fatal("unrevised draft displayed as final")
	}
	if _, err = os.Stat(filepath.Join(project, "should-not-exist")); !os.IsNotExist(err) {
		t.Fatal(err)
	}
	replay, err := e.ChangeReport(s.ID, start)
	if err != nil || replay.Report.Attempt != 1 || replay.Report.Markdown != s.Report.Markdown {
		t.Fatal(replay, err)
	}
}

func TestReportRetryResumesAfterInvalidRevision(t *testing.T) {
	var calls atomic.Int32
	call := func(_ context.Context, _, _, _, _ string) (string, error) {
		switch calls.Add(1) {
		case 1:
			return draftReply, nil
		case 2:
			return reviewedReply, nil
		case 3:
			return strings.Replace(finalReply, "I propose a limited pilot", "fabricated quotation", 1), nil
		case 4:
			return `{"action":"write","path":"injected.txt","text":"unwanted"}`, nil
		case 5:
			return finalReply, nil
		}
		return "", errors.New("duplicate call")
	}
	e, project := engine(t, call)
	s := reportFixture(t, e, project, "same", "vendor/same")
	if _, err := e.ChangeReport(s.ID, reportAction(s, "finish")); err != nil {
		t.Fatal(err)
	}
	s = reportSettled(t, e, s.ID)
	r := s.Report
	if r.Status != "failed" || r.ReviewMode != "same_model" || r.Error == "" || !r.HasDraft || r.ReviewNotes == "" || !strings.Contains(r.Markdown, "（草稿）") || !strings.Contains(r.Markdown, "Keep the pilot") {
		t.Fatal(r)
	}
	retry := reportAction(s, "retry")
	if _, err := e.ChangeReport(s.ID, retry); err != nil {
		t.Fatal(err)
	}
	s = reportSettled(t, e, s.ID)
	if s.Report.Status != "failed" || s.Report.Attempt != 2 || calls.Load() != 4 {
		t.Fatal(s.Report)
	}
	dup, err := e.ChangeReport(s.ID, retry)
	if err != nil || dup.Report.Attempt != 2 || dup.Report.Status != "failed" {
		t.Fatal(dup, err)
	}
	if _, err = e.ChangeReport(s.ID, reportAction(s, "retry")); err != nil {
		t.Fatal(err)
	}
	s = reportSettled(t, e, s.ID)
	if s.Report.Status != "ready" || s.Report.Attempt != 3 || calls.Load() != 5 {
		t.Fatal(s.Report, calls.Load())
	}
	if _, err = os.Stat(filepath.Join(project, "injected.txt")); !os.IsNotExist(err) {
		t.Fatal(err)
	}
}

func TestReportShutdownRecoveryAndSingleSeat(t *testing.T) {
	started := make(chan struct{})
	e, project := engine(t, func(ctx context.Context, _, _, _, _ string) (string, error) {
		close(started)
		<-ctx.Done()
		return "", ctx.Err()
	})
	s := reportFixture(t, e, project, "only")
	if _, err := e.ChangeReport(s.ID, reportAction(s, "finish")); err != nil {
		t.Fatal(err)
	}
	select {
	case <-started:
	case <-time.After(time.Second):
		t.Fatal("draft did not start")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	if err := e.Shutdown(ctx); err != nil {
		t.Fatal(err)
	}
	s, err := e.Get(s.ID)
	if err != nil || s.Report.Status != "failed" || s.Report.HasDraft || s.Report.ReviewMode != "self" || !strings.Contains(s.Report.Markdown, "公开发言摘录") {
		t.Fatal(s, err)
	}
	// Simulate a process exit while an active stage was on disk: recovery sees
	// the abandoned lease and records a failed draft without replaying a call.
	s.Report.Status = "drafting"
	if err = e.locked(func() error { return e.save(s) }); err != nil {
		t.Fatal(err)
	}
	var calls atomic.Int32
	other, err := New(e.dir, func(_ context.Context, seat, _, _, _ string) (string, error) {
		if seat != "member-1" {
			return "", errors.New("unselected seat")
		}
		switch calls.Add(1) {
		case 1:
			return draftReply, nil
		case 2:
			return reviewedReply, nil
		case 3:
			return finalReply, nil
		}
		return "", errors.New("extra")
	}, testSettings)
	if err != nil {
		t.Fatal(err)
	}
	s, err = other.Get(s.ID)
	if err != nil || s.Report.Status != "failed" || s.Status != "closed" || calls.Load() != 0 {
		t.Fatal(s, err)
	}
	if _, err = other.ChangeReport(s.ID, reportAction(s, "retry")); err != nil {
		t.Fatal(err)
	}
	s = reportSettled(t, other, s.ID)
	if s.Report.Status != "ready" || s.Report.ReviewMode != "self" || !strings.Contains(s.Report.Markdown, "执笔席自审") || calls.Load() != 3 {
		t.Fatal(s.Report)
	}
}

func TestReportRejectsForeignInlineAndFabricatedReferences(t *testing.T) {
	m := reportMaterial{Sources: []reportSource{{ID: "R1-T1", Kind: "public", Text: "We have limited coverage."}, {ID: "A1", Kind: "agenda", Text: "coverage"}}}
	for _, p := range []reportParagraph{
		{Text: "unbacked"},
		{Text: "bad ID", Evidence: []reportEvidence{{"R99-T1", "coverage"}}},
		{Text: "fabricated", Evidence: []reportEvidence{{"R1-T1", "total coverage"}}},
		{Text: "spurious citation [R90-T4]", Evidence: []reportEvidence{{"R1-T1", "coverage"}}},
		{Text: "agenda only", Evidence: []reportEvidence{{"A1", "coverage"}}},
	} {
		if _, err := (reportBody{Outcome: []reportParagraph{p}}).render(m); err == nil {
			t.Errorf("accepted %+v", p)
		}
	}
}
