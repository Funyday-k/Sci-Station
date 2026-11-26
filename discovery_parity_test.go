package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"

	"scistation.local/desktop/internal/gateway"
	"scistation.local/desktop/internal/research"
)

func TestDailyDiscoveryReopensOfflineWithScopedDefaultsAndFeedback(t *testing.T) {
	dir := t.TempDir()
	root := filepath.Join(dir, "research")
	lab, err := research.New(root)
	if err != nil {
		t.Fatal(err)
	}
	deps := discoveryDependencies{search: func(context.Context, string, int) ([]research.DiscoveryCandidate, error) {
		t.Fatal("offline feed must not contact arXiv")
		return nil, nil
	}}
	call := func(method, route, query, body string, want int) []byte {
		t.Helper()
		r := httptest.NewRequest(method, "/api/research/tools/"+route+query, strings.NewReader(body))
		w := httptest.NewRecorder()
		serveDiscovery(lab, dir, w, r, route, deps)
		if w.Code != want {
			t.Fatalf("%s %s: %d %s", method, r.URL, w.Code, w.Body.String())
		}
		return w.Body.Bytes()
	}
	req := httptest.NewRequest("POST", "/api/research/projects", strings.NewReader(`{"name":"Fixture"}`))
	projectReply := httptest.NewRecorder()
	lab.ServeHTTP(projectReply, req)
	if projectReply.Code != 201 {
		t.Fatalf("fixture project: %d %s", projectReply.Code, projectReply.Body.String())
	}
	project := scienceWorkflowDecode[research.Project](t, projectReply.Body.Bytes())
	scope := "?project=" + project.ID
	defaults := `{"source":"daily","cross_list":false,"top_k":4,"max_daily_candidates":45,"library_recent_days":12,"categories":["ASTRO-PH.HE"]}`
	call("POST", "discovery-defaults", scope, defaults, 200)
	global := scienceWorkflowDecode[discoveryView](t, call("GET", "discover", "", "", 200))
	if global.Defaults.Source != "arxiv" {
		t.Fatalf("project preference leaked into global scope: %+v", global.Defaults)
	}
	feed := `{"source":"arxiv","id":"2404.00001v3","title":"Fixture matches primary","categories":["astro-ph.HE"],"published":"2026-05-01T08:00:00Z"}
{"source":"arxiv","id":"2404.00002v2","title":"Fixture matches crosslist","primary_category":"hep-ph","category":"astro-ph.HE","published_year":2026}`
	body, err := json.Marshal(map[string]any{"daily_feed": discoveryFeedInput{Name: "/private/fixture/papers.jsonl", Text: feed}})
	if err != nil {
		t.Fatal(err)
	}
	run := scienceWorkflowDecode[discoveryView](t, call("POST", "discover", scope, string(body), 200))
	if len(run.Items) != 1 || run.Items[0].Arxiv != "2404.00001v3" || !run.Items[0].FirstCategory || run.Feed == nil ||
		run.Feed.Name != "papers.jsonl" || len(run.Feed.SHA256) != 64 || run.Items[0].MetadataSource != "daily-feed" {
		t.Fatalf("candidate or provenance missing: %+v", run)
	}
	repeated := scienceWorkflowDecode[discoveryView](t, call("POST", "discover", scope, string(body), 200))
	if repeated.ID != run.ID || len(repeated.History) != 1 {
		t.Fatalf("unchanged source duplicated the run: %+v", repeated.History)
	}
	bad, _ := json.Marshal(map[string]any{"daily_feed": discoveryFeedInput{Name: "bad.jsonl", Text: feed + "\ninvalid"}})
	call("POST", "discover", scope, string(bad), 400)
	edit := func(state string) string {
		return fmt.Sprintf(`{"run":%q,"key":"2404.00001","state":%q}`, run.ID, state)
	}
	for _, state := range []string{"liked", "liked", "hidden", ""} {
		call("POST", "feedback", scope, edit(state), 200)
	}
	lab, err = research.New(root)
	if err != nil {
		t.Fatal(err)
	}
	reopened := scienceWorkflowDecode[discoveryView](t, call("GET", "discover", scope, "", 200))
	if reopened.ID != run.ID || len(reopened.Items) != 1 || reopened.Feedback["2404.00001"] != "" ||
		reopened.Defaults.LibraryDays != 12 || reopened.Feed.SHA256 != run.Feed.SHA256 {
		t.Fatalf("offline reopen lost the run: %+v", reopened)
	}
	stored, err := loadDiscovery(filepath.Join(dir, "discovery."+project.ID+".json"))
	if err != nil || len(stored.FeedbackEvents) != 3 || stored.FeedbackEvents[0].State != "liked" ||
		stored.FeedbackEvents[2].State != "" || stored.FeedbackEvents[2].Run != run.ID {
		t.Fatalf("feedback history lost or duplicated: %+v (%v)", stored.FeedbackEvents, err)
	}
}

type multiDiscoveryAI struct {
	t     *testing.T
	calls int
}

func (a *multiDiscoveryAI) Catalog(context.Context) (gateway.Catalog, error) {
	return gateway.Catalog{Models: []gateway.Model{{ID: "fixture"}}}, nil
}

func (a *multiDiscoveryAI) Generate(_ context.Context, id, effort, rules, prompt, session string) (string, error) {
	a.calls++
	if id != "fixture" || !strings.Contains(prompt, "Reference fixture") {
		a.t.Fatalf("unexpected AI input %q", prompt)
	}
	if a.calls == 1 {
		return `{"strategies":[{"query":"ti:method","categories":["astro-ph.HE"]},{"query":"abs:survey","categories":["hep-ex"]}]}`, nil
	}
	return `{"reviews":[{"id":"2404.00101","relevance":0.9,"usefulness":0.8,"risk":1.4,"summary":"Fixture summary","recommendation_comment":"Read this fixture"},{"id":"9999.99999","relevance":1,"recommendation_comment":"invented"}]}`, nil
}

func TestDiscoveryCombinesManualAndScopedStrategiesWithVersionProvenance(t *testing.T) {
	var requested []string
	fixture := &multiDiscoveryAI{t: t}
	search := func(_ context.Context, query string, _ int) ([]research.DiscoveryCandidate, error) {
		requested = append(requested, query)
		version := "2404.00101v1"
		switch query {
		case `(all:"solar") AND (cat:astro-ph.HE)`:
		case "(ti:method) AND (cat:astro-ph.HE)":
			version = "2404.00101v3"
		case "(abs:survey) AND (cat:astro-ph.HE)":
			return nil, fmt.Errorf("fixture unavailable")
		case "cat:astro-ph.HE":
			version = "2404.00102v2"
		default:
			t.Fatalf("query escaped selected classification: %q", query)
		}
		p := research.DiscoveryCandidate{PrimaryCategory: "astro-ph.HE", PaperMetadata: research.PaperMetadata{Title: "Fixture", Arxiv: version}}
		return []research.DiscoveryCandidate{p}, nil
	}
	options := discoveryOptions{Query: "solar", Source: "arxiv", TopK: 3, AIModel: "fixture", Categories: []string{"astro-ph.he"}}
	sources := research.DiscoveryContext{Refs: []research.Paper{{PaperMetadata: research.PaperMetadata{Title: "Reference fixture"}}}}
	result, err := buildDiscoveryRun(context.Background(), options, sources, discoveryState{}, discoveryDependencies{search: search, ai: fixture})
	if err != nil || len(requested) != 4 || len(result.Items) != 2 || len(result.AtomQueries) != 3 || result.Notice == "" {
		t.Fatalf("expected partial success across strategies and fallback: %+v; requests %v (%v)", result, requested, err)
	}
	for _, p := range result.Items {
		if p.Key() == "2404.00101" && (p.Arxiv != "2404.00101v3" || len(p.SearchQueries) != 1 || p.SearchQueries[0] != requested[1]) {
			t.Fatalf("retained arXiv version points to wrong expression: %+v", p)
		}
	}
	review := result.AIReviewDetails["2404.00101"]
	if len(result.AIReviewDetails) != 1 || review.Relevance == nil || review.Risk != nil || review.Comment == "" {
		t.Fatalf("AI structured review lost constraints: %+v", result.AIReviewDetails)
	}
}

func TestGlobalReadingTodoDeduplicatesExistingUnassignedReadingTask(t *testing.T) {
	root := t.TempDir()
	lab, err := research.New(root)
	if err != nil {
		t.Fatal(err)
	}
	call := func(method, path, body string, allowed ...int) []byte {
		t.Helper()
		req := httptest.NewRequest(method, "/api/research/"+path, strings.NewReader(body))
		res := httptest.NewRecorder()
		lab.ServeHTTP(res, req)
		for _, want := range allowed {
			if res.Code == want {
				return res.Body.Bytes()
			}
		}
		t.Fatalf("%s %s: %d %s", method, path, res.Code, res.Body.String())
		return nil
	}
	paper := scienceWorkflowDecode[research.Paper](t, call("POST", "papers", `{"title":"Local fixture"}`, http.StatusCreated))
	project := scienceWorkflowDecode[research.Project](t, call("POST", "projects", `{"name":"Fixture"}`, 201))
	plain := fmt.Sprintf(`{"title":"Read fixture","kind":"reading","relatedPaperIds":[%q]}`, paper.ID)
	projectTask := scienceWorkflowDecode[research.Task](t, call("POST", "projects/"+project.ID+"/tasks", plain, 201))
	unassigned := scienceWorkflowDecode[research.Task](t, call("POST", "tasks", plain, 201))
	input := fmt.Sprintf(`{"title":"From recommendations","kind":"reading","relatedPaperIds":[%q],"idempotencyKey":%q}`, paper.ID, "reading:"+paper.ID)
	for range 2 {
		reused := scienceWorkflowDecode[research.Task](t, call("POST", "tasks", input, 200))
		if reused.ID != unassigned.ID || reused.ID == projectTask.ID || len(reused.ProjectIDs) != 0 {
			t.Fatalf("global request reused the wrong task: %+v", reused)
		}
	}
	lab, err = research.New(root)
	if err != nil {
		t.Fatal(err)
	}
	tasks := scienceWorkflowDecode[[]research.Task](t, call("GET", "tasks", "", 200))
	if len(tasks) != 2 {
		t.Fatalf("retry created duplicate tasks: %+v", tasks)
	}
}
