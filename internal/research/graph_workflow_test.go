package research

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"net/http/httptest"
	"net/url"
	"os"
	"slices"
	"strings"
	"testing"
)

func workflowTestQuery(t *testing.T, s *Service, p Project, operation string, options url.Values) graphWorkflowPreview {
	t.Helper()
	if options == nil {
		options = url.Values{}
	}
	options.Set("operation", operation)
	return decodeResearch[graphWorkflowPreview](t, callResearch(t, s, "GET", "/projects/"+p.ID+"/graph/workflow?"+options.Encode(), nil, 200))
}

func TestGraphWorkflowReadingIncludesFollowUpsSharedMethodsAndUncitedCore(t *testing.T) {
	s := newResearch(t, t.TempDir())
	p := createResearchProject(t, s, "Methods")
	other := createResearchProject(t, s, "Separate project")
	base := "/projects/" + p.ID
	paper := func(project Project, title, doi string, isCore bool, refs ...string) Paper {
		t.Helper()
		in := PaperMetadata{Title: title, DOI: doi, ProjectIDs: []string{project.ID}, References: refs}
		if isCore {
			in.CoreProjectIDs = []string{project.ID}
		}
		return decodeResearch[Paper](t, callResearch(t, s, "POST", "/papers", in, 201))
	}
	note := func(title, namespace string) Note {
		t.Helper()
		return decodeResearch[Note](t, callResearch(t, s, "POST", base+"/notes",
			map[string]any{"title": title, "namespace": namespace}, 201))
	}
	relation := func(from, to, kind string, status int) {
		t.Helper()
		callResearch(t, s, "POST", base+"/graph/relations", map[string]string{"source": from, "target": to, "kind": kind}, status)
	}

	foundation := paper(p, "Foundation", "10.1000/foundation", false)
	center := paper(p, "Center", "10.1000/center", false, foundation.DOI)
	followUp := paper(p, "Follow up", "10.1000/follow-up", false, center.DOI)
	core := paper(p, "Independent core record", "10.1000/core", true)
	methodUser := paper(p, "Uses the same method", "10.1000/other-method-user", false)
	_ = paper(other, "Foreign core record", "10.1000/foreign", true)
	noise := paper(p, "Unconnected paper", "10.1000/noise", false)
	current := note("Current method", "Methods/scattering")
	dependsOn := note("Component method", "method")
	precursor := note("Earlier method", "methods/scattering")
	general := note("Ordinary note", "notes")
	relation(center.ID, current.ID, "uses", 201)
	relation(methodUser.ID, current.ID, "uses", 201)
	relation(current.ID, dependsOn.ID, "uses", 201)
	relation(dependsOn.ID, precursor.ID, "extends", 201)
	relation(center.ID, general.ID, "uses", 400)
	relation(precursor.ID, general.ID, "extends", 201)

	reading := workflowTestQuery(t, s, p, "reading", url.Values{"focus": {center.ID}, "depth": {"2"}})
	titlePosition := func(id string) int {
		return slices.IndexFunc(reading.Findings, func(row graphWorkflowFinding) bool { return row.Links[0].NodeID == id })
	}
	if a, b, c := titlePosition(foundation.ID), titlePosition(center.ID), titlePosition(followUp.ID); a < 0 || a >= b || b >= c {
		t.Fatalf("citation ordering lost: %+v", reading.Findings)
	}
	if titlePosition(core.ID) < 0 || titlePosition(methodUser.ID) < 0 || titlePosition(noise.ID) >= 0 || strings.Contains(reading.Excerpt, "Foreign") {
		t.Fatalf("unexpected reading candidates: %+v", reading)
	}
	if !strings.Contains(reading.Excerpt, "项目核心论文") {
		t.Fatalf("reason missing for uncited core paper: %+v", reading)
	}
	row := reading.Findings[titlePosition(core.ID)]
	if row.Title != core.Title || strings.Contains(row.Text, core.ID) || !strings.Contains(reading.Excerpt, core.ID) {
		t.Fatalf("display and handoff did not preserve their expected locators: %+v", reading)
	}
	lineage := workflowTestQuery(t, s, p, "method-lineage", url.Values{"focus": {current.ID}, "depth": {"3"}})
	if lineage.Total != 2 || !strings.Contains(lineage.Excerpt, "使用") || !strings.Contains(lineage.Excerpt, "Earlier method") ||
		strings.Contains(lineage.Excerpt, "Ordinary") || strings.Contains(lineage.Excerpt, center.ID) {
		t.Fatalf("lineage crossed non-method nodes or lost semantics: %+v", lineage)
	}
	incoming := workflowTestQuery(t, s, p, "method-lineage", url.Values{"focus": {precursor.ID}, "depth": {"2"}, "direction": {"incoming"}})
	if incoming.Total != 2 || !strings.Contains(incoming.Excerpt, "Current method") {
		t.Fatalf("incoming method lineage missing: %+v", incoming)
	}
	callResearch(t, s, "GET", base+"/graph/workflow?operation=method-lineage&focus="+center.ID, nil, 400)

	bridge := workflowTestQuery(t, s, p, "bridge", url.Values{"focus": {foundation.ID}, "target": {followUp.ID}, "depth": {"2"}})
	if bridge.Total != 3 || bridge.Findings[1].Links[0].NodeID != center.ID {
		t.Fatalf("bridge did not return shortest ordered path: %+v", bridge)
	}
	relation(foundation.ID, center.ID, "extends", 201)
	cycle := workflowTestQuery(t, s, p, "reading", url.Values{"focus": {center.ID}, "depth": {"2"}})
	if cycle.Total != reading.Total || !strings.Contains(cycle.Notice, "构成环") {
		t.Fatalf("cyclic reading graph lost papers or warning: %+v", cycle)
	}
}

func TestGraphWorkflowCoreAndStaleCitationsUseRecordedSources(t *testing.T) {
	s := newResearch(t, t.TempDir())
	p := createResearchProject(t, s, "Source citations")
	q := createResearchProject(t, s, "Separate source citations")
	paper := func(project Project, title, doi string, year int, isCore bool, refs ...string) Paper {
		t.Helper()
		in := PaperMetadata{Title: title, DOI: doi, Year: year, ProjectIDs: []string{project.ID}, References: refs}
		if isCore {
			in.CoreProjectIDs = []string{project.ID}
		}
		return decodeResearch[Paper](t, callResearch(t, s, "POST", "/papers", in, 201))
	}
	old := paper(p, "Old baseline", "10.1000/baseline", 1981, false)
	newer := paper(p, "Newer extension", "10.1000/extension", 2021, false)
	unlinked := paper(q, "Unlinked paper", "10.1000/unlinked", 2010, false)
	uncited := paper(q, "Unrelated paper", "10.1000/unrelated", 2012, true)
	_ = paper(p, "Old but with no extension", "10.1000/unextended", 1982, false)
	source := paper(p, "Core A", "10.1000/core-a", 2024, true, old.DOI, unlinked.DOI, unlinked.DOI, "10.1000/unextended", "10.1000/only-in-reference")
	second := paper(p, "Core B", "10.1000/core-b", 2024, true, unlinked.DOI)
	_ = paper(p, "Not core", "10.1000/not-core", 2024, false, uncited.DOI)

	before := workflowTestQuery(t, s, p, "stale-citations", nil)
	if before.Total != 0 {
		t.Fatalf("publication age alone flagged citations: %+v", before)
	}
	callResearch(t, s, "POST", "/projects/"+p.ID+"/graph/relations", map[string]string{
		"source": newer.ID, "target": old.ID, "kind": "extends",
	}, 201)
	after := workflowTestQuery(t, s, p, "stale-citations", nil)
	if after.Total != 1 || after.Findings[0].Severity != "warning" || !strings.Contains(after.Excerpt, "Newer extension") ||
		!strings.Contains(after.Findings[0].Links[0].URL, "citation=metadata&ordinal=1") {
		t.Fatalf("stale citation lost recorded extension or locator: %+v", after)
	}
	if long := workflowTestQuery(t, s, p, "stale-citations", url.Values{"thresholdDays": {"36500"}}); long.Total != 0 {
		t.Fatalf("age threshold ignored: %+v", long)
	}

	preview := workflowTestQuery(t, s, p, "missing-core", url.Values{"minCitations": {"2"}})
	if preview.Total != 1 || !strings.Contains(preview.Excerpt, "Unlinked paper") ||
		!strings.Contains(preview.Findings[0].Links[0].URL, "paper="+unlinked.ID) ||
		!strings.Contains(preview.Excerpt, source.ID) || !strings.Contains(preview.Excerpt, second.ID) {
		t.Fatalf("shared candidate was not deduplicated with source links: %+v", preview)
	}
	wider := workflowTestQuery(t, s, p, "missing-core", nil)
	if wider.Total != 2 || !strings.Contains(wider.Excerpt, "10.1000/only-in-reference") ||
		strings.Contains(wider.Excerpt, "Old baseline") || strings.Contains(wider.Excerpt, "Unrelated paper") {
		t.Fatalf("project association and provenance ignored: %+v", wider)
	}
	other := workflowTestQuery(t, s, q, "missing-core", nil)
	if other.Total != 0 {
		t.Fatalf("foreign core citations leaked: %+v", other)
	}
}

func TestGraphWorkflowChecksAcceptedArtifactsAndFeedsDashboard(t *testing.T) {
	dir := t.TempDir()
	s := newResearch(t, dir)
	p := createResearchProject(t, s, "Saved outcomes")
	other := createResearchProject(t, s, "Independent")
	base := "/projects/" + p.ID
	const sourceBody = "A source quotation recorded during the meeting."
	note := decodeResearch[Note](t, callResearch(t, s, "POST", base+"/notes", map[string]string{"title": "Real source", "body": sourceBody}, 201))
	evidence := Evidence{
		Source: &ProjectEvidenceLocation{ProjectID: p.ID, Kind: "note", ID: note.ID, End: len(sourceBody)},
		Quote:  sourceBody, SourceHash: fmt.Sprintf("%x", sha256.Sum256([]byte(sourceBody))), MeetingID: "recorded-meeting", TurnID: "round-1-seat",
	}
	useOrdinals := true
	resolve := func(string) (ReviewSource, error) {
		return ReviewSource{Text: "Recorded project outcome", SelectEvidence: func(body string) ([]Evidence, map[string]int, error) {
			if strings.Contains(body, "[S7]") {
				if useOrdinals {
					return []Evidence{evidence}, map[string]int{"S7": 1}, nil
				}
				return []Evidence{evidence}, nil, nil
			}
			return nil, nil, nil
		}}, nil
	}
	review := func(input ReviewRequest, status int) MeetingReview {
		t.Helper()
		w := httptest.NewRecorder()
		req := httptest.NewRequest("POST", "/meeting/research-reviews", nil)
		s.ServeMeetingReview(w, req, p.ID, "recorded-meeting", input, resolve)
		if w.Code != status {
			t.Fatalf("%s: %d (want %d): %s", input.Decision, w.Code, status, w.Body.String())
		}
		if status >= 400 {
			return MeetingReview{}
		}
		return decodeResearch[MeetingReview](t, w.Body.Bytes())
	}
	propose := func(title, body string) MeetingReview {
		t.Helper()
		return review(ReviewRequest{ProjectID: p.ID, OperationID: makeID(), Decision: "propose", Proposal: &ReviewProposal{
			ProjectRevision: p.Revision, TurnID: "round-1-seat", Action: "create-note", Title: title, Body: body,
		}}, 201)
	}
	decide := func(draft MeetingReview, decision string, status int) MeetingReview {
		t.Helper()
		return review(ReviewRequest{ProjectID: p.ID, OperationID: draft.ID, Revision: draft.Revision, Decision: decision}, status)
	}
	_ = propose("Pending", "## Conclusions\nA pending statement should be excluded.")
	rejected := propose("Rejected", "## Conclusions\nA rejected statement should be excluded.")
	decide(rejected, "reject", 200)
	missing := propose("Missing evidence", "## Conclusions\nA statement without recorded evidence.\nA second missing statement [S8] [S9].")
	decide(missing, "accept", 200)
	useOrdinals = false
	legacyDone := decide(propose("Historical accepted write", "## Conclusions\nAn earlier statement with a citation [S7]."), "accept", 200)
	legacyPending := propose("A draft saved before upgrade", "## Conclusions\nA statement with an explicit citation [S7].")
	if len(legacyPending.CitationOrdinals) != 0 || len(legacyDone.CitationOrdinals) != 0 {
		t.Fatal("legacy fixture unexpectedly has citation ordinals")
	}

	record := s.recordPath(p.ID)
	disk, err := os.ReadFile(record)
	if err != nil {
		t.Fatal(err)
	}
	var raw map[string]json.RawMessage
	if err = json.Unmarshal(disk, &raw); err != nil {
		t.Fatal(err)
	}
	raw["legacyFutureField"] = json.RawMessage(`{"keep":[1,2,3]}`)
	disk, err = json.Marshal(raw)
	if err != nil {
		t.Fatal(err)
	}
	if err = os.WriteFile(record, disk, 0600); err != nil {
		t.Fatal(err)
	}
	useOrdinals = true
	decide(legacyPending, "accept", 409)
	if saved := s.projects[p.ID].Reviews[legacyPending.ID]; saved.Status != "pending" || saved.ResultID != "" || saved.CitationOrdinals != nil {
		t.Fatalf("failed save released result or citation mappings: %+v", saved)
	}
	s = newResearch(t, dir)
	supported := decide(legacyPending, "accept", 200)
	if supported.CitationOrdinals["S7"] != 1 {
		t.Fatalf("legacy pending approval did not record exact mapping: %+v", supported)
	}
	disk, err = os.ReadFile(record)
	if err != nil || !bytes.Contains(disk, []byte("legacyFutureField")) {
		t.Fatalf("accept lost unknown project field: %v", err)
	}
	s = newResearch(t, dir)
	healthy := workflowTestQuery(t, s, p, "unsupported-claims", nil)
	if healthy.Total != 3 || !strings.Contains(healthy.Excerpt, "引用映射未保存在") || !strings.Contains(healthy.Excerpt, "缺少声明对应的原文") ||
		strings.Contains(healthy.Excerpt, supported.Title) || strings.Contains(healthy.Excerpt, "Pending") || strings.Contains(healthy.Excerpt, "Rejected") {
		t.Fatalf("incorrect claim coverage after restart: %+v", healthy)
	}
	facts := decodeResearch[map[string]dashboardProjectFacts](t, callResearch(t, s, "GET", "/dashboard/projects", nil, 200))
	if facts[p.ID].UnsupportedClaimCount != 2 || facts[other.ID].UnsupportedClaimCount != 0 {
		t.Fatalf("dashboard counted duplicate claims, warnings or other-project records: %+v", facts)
	}
	w := httptest.NewRecorder()
	req := httptest.NewRequest("GET", "/api/research/dashboard/projects?project="+p.ID, nil)
	s.ServeDashboardProjects(w, req, func(_ context.Context, projects map[string]struct{}) (map[string]DashboardPublishedResearch, error) {
		if _, ok := projects[p.ID]; len(projects) != 1 || !ok {
			t.Fatalf("published output reader was given a foreign project: %+v", projects)
		}
		claims, _ := WorkflowClaims(missing.Body)
		key := DashboardClaimKey{MeetingID: missing.MeetingID, OutputID: missing.TurnID, Digest: claims[0].Digest}
		return map[string]DashboardPublishedResearch{
			p.ID:     {Claims: map[DashboardClaimKey]struct{}{key: {}}},
			other.ID: {Claims: map[DashboardClaimKey]struct{}{key: {}}},
		}, nil
	})
	union := decodeResearch[map[string]dashboardProjectFacts](t, w.Body.Bytes())
	if w.Code != 200 || len(union) != 1 || union[p.ID].UnsupportedClaimCount != 2 {
		t.Fatalf("published and saved copies of a claim were double-counted: %+v", union)
	}

	callResearch(t, s, "PATCH", base+"/notes/"+note.ID, map[string]any{"revision": note.Revision, "body": sourceBody + " Changed."}, 200)
	warnings := workflowTestQuery(t, s, p, "unsupported-claims", url.Values{"severity": {"warning"}})
	if warnings.Total != 2 || !strings.Contains(warnings.Excerpt, "S7 原文已改变") ||
		!slices.ContainsFunc(warnings.Findings, func(row graphWorkflowFinding) bool {
			return len(row.Links) > 1 && strings.Contains(row.Links[1].URL, "note="+note.ID)
		}) {
		t.Fatalf("source change did not reach the claim with an original locator: %+v", warnings)
	}
	stale := workflowTestQuery(t, s, p, "stale-artifacts", nil)
	if stale.Total != 3 || !strings.Contains(stale.Excerpt, "原文已改变") || !strings.Contains(stale.Excerpt, "未登记可核对的原文证据") {
		t.Fatalf("stale status hid changed or missing source: %+v", stale)
	}
	if foreign := workflowTestQuery(t, s, other, "unsupported-claims", nil); foreign.Total != 0 {
		t.Fatalf("accepted statements leaked across projects: %+v", foreign)
	}
}
