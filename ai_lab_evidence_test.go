package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http/httptest"
	"net/url"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"scistation.local/desktop/internal/meeting"
	"scistation.local/desktop/internal/research"
)

func TestLabClaimInspectionKeepsOriginalRulesAndLimitations(t *testing.T) {
	content := "# Notes\n## Methods\n- This is the best tested option [S1] [evidence:S1].\n- Comparison is still missing a reference.\n" +
		"3. Approximation validity is reported [evidence:unknown].\n" +
		"- One of these sources is unavailable [S1] [S4].\n- The next material was unavailable [S3].\n" +
		"- The same selected source is cited again [S1].\n- Fourth use of the same citation [S1].\n" +
		"```md\n- source in an example [S1]\n```\n## Evidence matrix\n- Matrix rows aren't claims.\n"
	claims, truncated := labClaims(content)
	if truncated || len(claims) != 7 {
		t.Fatalf("claims %+v", claims)
	}
	refs := map[string]labEvidenceReference{"S1": {Status: "located"}, "S4": {Status: "stale"}}
	labClaimStatuses(claims, refs)
	want := []string{"located", "missing_reference", "unresolved", "incomplete", "unresolved", "located", "located"}
	for i, claim := range claims {
		if claim.Line != i+3 || claim.Status != want[i] || !claim.Core {
			t.Fatalf("claim %d = %+v", i, claim)
		}
	}
	if !slices.Equal(claims[0].Warnings, []string{"strong_wording", "reused_source"}) || len(claims[0].References) != 1 {
		t.Fatal(claims[0])
	}
	goal := "第一篇文章的蒸发率公式是什么？"
	if issues := labQualityIssues(goal, "公式为 $$ E = kA $$。来源 [S1]。", true, true); len(issues) != 0 {
		t.Fatal(issues)
	}
	if issues := labQualityIssues(goal, "我使用了工具并找到了答案。", true, false); !slices.Contains(issues, "missing_display_math") || !slices.Contains(issues, "missing_source") {
		t.Fatal(issues)
	}
	if issues := labQualityIssues(goal, "我没有读取到正文或公式证据。", false, false); !slices.Contains(issues, "missing_evidence") || slices.Contains(issues, "missing_content_explanation") {
		t.Fatal(issues)
	}
}

func TestLabEvidenceIsProjectAndRoundScopedAndFormalAdmissionUsesReviewedBody(t *testing.T) {
	dir := t.TempDir()
	prefs, err := openSettings(dir)
	if err != nil {
		t.Fatal(err)
	}
	lab, err := research.New(filepath.Join(dir, "research"))
	if err != nil {
		t.Fatal(err)
	}
	const original = "The small-scale limit assumes a stationary distribution."
	const later = "The later experiment uses a different temperature."
	const answer = "## Methods\n- The zero-drift approximation has an explicit premise [S1].\n- A source added during a later turn is not available [S2].\n- A third claim has no citation."
	prompts := make(chan string, 2)
	engine, err := meeting.New(filepath.Join(dir, "sessions"), func(_ context.Context, _, _, prompt, _ string) (string, error) {
		prompts <- prompt
		text, err := json.Marshal(map[string]string{"action": "say", "text": answer})
		return string(text), err
	}, func() meeting.Settings { return prefs.get().Settings })
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = engine.Shutdown(context.Background()) })
	api := (&apiServer{prefs: prefs, research: lab, meetings: engine}).serve(8765)
	call := func(method, path string, body any, expected int) []byte {
		t.Helper()
		data, err := json.Marshal(body)
		if err != nil {
			t.Fatal(err)
		}
		r := httptest.NewRequest(method, "http://127.0.0.1:8765"+path, bytes.NewReader(data))
		r.Header.Set("X-Roundtable", "1")
		r.Header.Set("Content-Type", "application/json")
		w := httptest.NewRecorder()
		api.ServeHTTP(w, r)
		if w.Code != expected {
			t.Fatalf("%s %s = %d, want %d: %s", method, path, w.Code, expected, w.Body.String())
		}
		return w.Body.Bytes()
	}
	p := scienceWorkflowDecode[research.Project](t, call("POST", "/api/research/projects", map[string]string{"name": "Research fixture"}, 201))
	other := scienceWorkflowDecode[research.Project](t, call("POST", "/api/research/projects", map[string]string{"name": "Unrelated fixture"}, 201))
	projURL := "/api/research/projects/" + p.ID
	attach := func(title, quote string) (research.Note, string, meeting.Material) {
		note := scienceWorkflowDecode[research.Note](t, call("POST", projURL+"/notes", map[string]string{"title": title, "body": "前提\n" + quote}, 201))
		in := labSourcesRequest{ProjectID: p.ID, Workflow: "gap-planning", Location: research.SourceLocation{Kind: "note", ID: note.ID, Offset: 3}}
		source := scienceWorkflowDecode[research.WorkflowSource](t, call("POST", "/api/research/lab/sources/preview", in, 200))
		in.Citations = []labCitation{{SourceLocation: in.Location, Hash: source.Hash, Quote: quote}}
		materials := scienceWorkflowDecode[[]meeting.Material](t, call("POST", "/api/research/lab/sources/prepare", in, 200))
		return note, source.Hash, materials[0]
	}
	note, fingerprint, first := attach("Recorded premise", original)
	_, _, second := attach("Later experiment", later)
	engine.SetProjectAccess(func(id string, work func(string) error) error {
		if id != p.ID {
			return fmt.Errorf("unbound project")
		}
		return work(p.Path)
	})
	room, err := engine.CreateScopedConfiguredWithMaterials("科研工作流 · 研究空缺\n工作流 ID：gap-planning\n\n研究问题\nWhich assumptions are in evidence?", meeting.ProjectScope{ID: p.ID, Directory: p.Path}, []meeting.Member{{Model: "fixture/research", Effort: "auto"}}, "review", nil, []string{first.ID})
	if err != nil {
		t.Fatal(err)
	}
	studioURL := "/api/studio/sessions/" + room.ID
	run := func(expectedRound int, materialIDs []string) string {
		t.Helper()
		call("POST", studioURL+"/run", map[string]any{"expected_round": expectedRound, "allow_edits": false, "material_ids": materialIDs}, 202)
		var prompt string
		select {
		case prompt = <-prompts:
		case <-time.After(5 * time.Second):
			t.Fatal("missing model input")
		}
		for deadline := time.Now().Add(5 * time.Second); time.Now().Before(deadline); {
			room = scienceWorkflowDecode[*meeting.Session](t, call("GET", studioURL, nil, 200))
			if room.Status != "running" && len(room.Rounds) > expectedRound {
				return prompt
			}
			time.Sleep(5 * time.Millisecond)
		}
		t.Fatal("run did not settle")
		return ""
	}
	if prompt := run(0, nil); !strings.Contains(prompt, `"citation_id":"S1"`) || !strings.Contains(prompt, original) || strings.Contains(prompt, later) {
		t.Fatal("first prompt did not match recorded source")
	}
	type dashboardFacts struct {
		UnsupportedClaimCount int
		LastResearchActivity  string
	}
	const dashboardRoute = "/api/research/dashboard/projects"
	dashboard := func(path string) map[string]dashboardFacts {
		t.Helper()
		return scienceWorkflowDecode[map[string]dashboardFacts](t, call("GET", dashboardRoute+path, nil, 200))
	}
	beforeAnyWrite := dashboard("?project=" + p.ID)
	if len(beforeAnyWrite) != 1 || beforeAnyWrite[p.ID].UnsupportedClaimCount != 2 ||
		beforeAnyWrite[p.ID].LastResearchActivity != room.Rounds[0].Turns[0].FinishedAt {
		t.Fatalf("published evidence gaps were lost without a writeback: %+v", beforeAnyWrite)
	}
	scoped := dashboard("?project=" + other.ID)
	if len(scoped) != 1 || scoped[other.ID] != (dashboardFacts{}) {
		t.Fatalf("another project's research influenced selected project facts: %+v", scoped)
	}
	call("GET", dashboardRoute+"?project=missing", nil, 404)
	if prompt := run(1, []string{second.ID}); !strings.Contains(prompt, `"id":"`+second.ID+`","citation_id":"S2"`) || !strings.Contains(prompt, `"id":"`+first.ID+`","citation_id":"S1"`) {
		t.Fatal("follow-up did not retain stable originals")
	}
	if all := dashboard(""); all[p.ID].UnsupportedClaimCount != 3 || all[other.ID] != (dashboardFacts{}) {
		t.Fatalf("workspace summary lost historical publication or project isolation: %+v", all)
	}
	open := *room
	open.Status = "running"
	var incomplete research.DashboardPublishedResearch
	if err := addPublishedDashboardClaims(t.Context(), &open, &incomplete); err != nil || len(incomplete.Claims) != 2 {
		t.Fatalf("an unpublished latest turn contributed to the count: %+v, %v", incomplete, err)
	}
	ordinary := *room
	ordinary.Topic = "An ordinary discussion with recorded excerpts"
	var explicit research.DashboardPublishedResearch
	if err := addPublishedDashboardClaims(t.Context(), &ordinary, &explicit); err != nil || len(explicit.Claims) != 1 {
		t.Fatalf("ordinary prose was treated as uncited formal claims: %+v, %v", explicit, err)
	}
	output := fmt.Sprintf("round-1-%s", room.Rounds[0].Turns[0].Seat)
	inspect := func(project string) string {
		return "/api/research/lab/evidence/" + room.ID + "?" + url.Values{"project": {project}, "output": {output}}.Encode()
	}
	call("GET", inspect(other.ID), nil, 404)
	got := scienceWorkflowDecode[labEvidenceInspection](t, call("GET", inspect(p.ID), nil, 200))
	if !got.Formal || got.ReviewBlock == "" || len(got.Sources) != 1 || len(got.Claims) != 3 {
		t.Fatalf("bad report %+v", got)
	}
	firstRef := got.Sources[0]
	if firstRef.ID != "S1" || firstRef.Status != "located" || firstRef.Evidence.Quote != original || firstRef.Evidence.SourceHash != fingerprint ||
		firstRef.Evidence.Source.Offset != 3 || firstRef.Evidence.Source.ProjectID != p.ID || got.Claims[0].Status != "located" ||
		got.Claims[1].Status != "unresolved" || got.Claims[2].Status != "missing_reference" {
		t.Fatalf("bad citation %+v / claims %+v", firstRef, got.Claims)
	}
	reviewURL := studioURL + "/research-reviews"
	command := research.ReviewRequest{ProjectID: p.ID, Decision: "propose", OperationID: strings.Repeat("1", 32), Proposal: &research.ReviewProposal{
		ProjectRevision: p.Revision, TurnID: output, Action: "create-note", Title: "Reviewed gap", Body: answer,
	}}
	call("POST", reviewURL, command, 422)
	command.Proposal.Body = "The approximation motivates checking the same limit experimentally."
	call("POST", reviewURL, command, 422)
	command.Proposal.Body = "## Methods\n- The small-scale premise comes from the project note [S1]."
	draft := scienceWorkflowDecode[research.MeetingReview](t, call("POST", reviewURL, command, 201))
	if len(draft.Evidence) != 1 || draft.Evidence[0].Quote != original || draft.Status != "pending" || draft.CitationOrdinals["S1"] != 1 {
		t.Fatalf("bad review %#v", draft)
	}
	accepted := scienceWorkflowDecode[research.MeetingReview](t, call("POST", reviewURL, research.ReviewRequest{ProjectID: p.ID, Decision: "accept", OperationID: draft.ID, Revision: draft.Revision}, 200))
	if accepted.Status != "accepted" || accepted.ResultID == "" || accepted.CitationOrdinals["S1"] != 1 {
		t.Fatal("verified draft did not enter the normal human approval path", accepted)
	}
	command.OperationID = strings.Repeat("2", 32)
	command.Proposal.Title = "Stale gap"
	draft = scienceWorkflowDecode[research.MeetingReview](t, call("POST", reviewURL, command, 201))
	call("PATCH", projURL+"/notes/"+note.ID, map[string]any{"revision": note.Revision, "body": "Changed after preview"}, 200)
	graph := call("GET", projURL+"/graph/workflow?operation=unsupported-claims", nil, 200)
	if !bytes.Contains(graph, []byte("S1 原文已改变")) || !bytes.Contains(graph, []byte(accepted.ResultID)) ||
		!bytes.Contains(graph, []byte(fingerprint)) {
		t.Fatalf("saved claim did not retain re-openable evidence: %s", graph)
	}
	if all := dashboard(""); all[p.ID].UnsupportedClaimCount != 3 {
		t.Fatalf("pending proof and source edits changed the original published coverage: %+v", all)
	}
	rechecked := scienceWorkflowDecode[labEvidenceInspection](t, call("GET", inspect(p.ID), nil, 200))
	if rechecked.Sources[0].Status != "stale" {
		t.Fatal("changed original was reported as valid", rechecked.Sources[0])
	}
	if rechecked.Sources[0].Evidence.Quote != original || rechecked.Sources[0].Evidence.SourceHash != fingerprint {
		t.Fatal("changed file replaced the recorded original", rechecked.Sources[0])
	}
	call("POST", reviewURL, research.ReviewRequest{ProjectID: p.ID, Decision: "accept", OperationID: draft.ID, Revision: draft.Revision}, 409)
	stored := scienceWorkflowDecode[[]research.Note](t, call("GET", projURL+"/notes", nil, 200))
	if len(stored) != 3 || !slices.ContainsFunc(stored, func(n research.Note) bool {
		return n.ID == accepted.ResultID && len(n.Evidence) == 1 && n.Evidence[0].Quote == original && n.Evidence[0].SourceHash == fingerprint
	}) {
		t.Fatal("source audit or failed approval wrote a note")
	}
}
