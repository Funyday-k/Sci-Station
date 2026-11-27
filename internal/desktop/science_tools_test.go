package desktop

import (
	"archive/zip"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"scistation.local/desktop/internal/gateway"
	"scistation.local/desktop/internal/research"
)

func TestDiscoveryFeedbackSurvivesRelaunch(t *testing.T) {
	dir := t.TempDir()
	prefs, err := openSettings(dir)
	if err != nil {
		t.Fatal(err)
	}
	lab, err := research.New(filepath.Join(dir, "research"))
	if err != nil {
		t.Fatal(err)
	}
	api := (&apiServer{prefs: prefs, research: lab}).serve(18765)
	for _, step := range []struct{ method, route, body string }{{"POST", "feedback", `{"arxiv":"2402.00001","state":"saved"}`}, {"GET", "discover", ""}} {
		req := httptest.NewRequest(step.method, "http://localhost:18765/api/research/tools/"+step.route, strings.NewReader(step.body))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("X-Roundtable", "1")
		res := httptest.NewRecorder()
		api.ServeHTTP(res, req)
		var result discoveryState
		if res.Code != 200 || json.Unmarshal(res.Body.Bytes(), &result) != nil || result.Feedback["2402.00001"] != "saved" {
			t.Fatalf("%s: %d %s", step.route, res.Code, res.Body.String())
		}
	}
}

type conversionTransport func(*http.Request) (*http.Response, error)

func (f conversionTransport) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }
func TestMinerUTransportUsesDirectConnectionsAndOperationDeadline(t *testing.T) {
	transport, ok := scientificHTTP.Transport.(*http.Transport)
	if !ok || transport.Proxy != nil || scientificHTTP.Timeout != 0 {
		t.Fatal("MinerU requires a direct transport bounded by its request context")
	}
	if scientificHTTP.CheckRedirect == nil || scientificHTTP.CheckRedirect(nil, nil) != http.ErrUseLastResponse {
		t.Fatal("MinerU redirects must be handled as responses")
	}
}

func TestMinerURequestAndMarkdownDecoding(t *testing.T) {
	orig := scientificHTTP
	t.Cleanup(func() { scientificHTTP = orig })
	scientificHTTP = &http.Client{Transport: conversionTransport(func(r *http.Request) (*http.Response, error) {
		if r.URL.String() != "https://mineru.net/api/v4/extract-results/batch/test" || r.Header.Get("Authorization") != "Bearer fixture" {
			t.Fatal("unexpected authenticated endpoint")
		}
		return &http.Response{StatusCode: 200, Header: http.Header{}, Body: io.NopCloser(strings.NewReader(`{"code":0,"data":{"batch_id":"test"}}`))}, nil
	})}
	resp, err := minerAPI(context.Background(), "fixture", "GET", "extract-results/batch/test", nil)
	if err != nil || resp.Data.Batch != "test" {
		t.Fatal(resp, err)
	}
	for _, s := range []string{"http://mineru.net/test", "https://mineru.net.example.org/f", "https://user@mineru.net/f", "https://127.0.0.1/a"} {
		if trustedMinerFile(s) {
			t.Fatal("accepted remote file URL", s)
		}
	}
	var buf bytes.Buffer
	z := zip.NewWriter(&buf)
	w, err := z.Create("paper/full.md")
	if err != nil {
		t.Fatal(err)
	}
	if _, err = io.WriteString(w, "# Converted paper"); err != nil {
		t.Fatal(err)
	}
	if err = z.Close(); err != nil {
		t.Fatal(err)
	}
	output, err := research.ReadMinerMarkdown(buf.Bytes())
	if err != nil || output.Markdown != "# Converted paper" {
		t.Fatal(output.Markdown, err)
	}
}

func TestDiscoveryFeedbackIsProjectScopedAndVersionIndependent(t *testing.T) {
	dir := t.TempDir()
	prefs, err := openSettings(dir)
	if err != nil {
		t.Fatal(err)
	}
	lab, err := research.New(filepath.Join(dir, "research"))
	if err != nil {
		t.Fatal(err)
	}
	api := (&apiServer{prefs: prefs, research: lab}).serve(18765)
	request := func(method, path, body string, want int) []byte {
		t.Helper()
		req := httptest.NewRequest(method, "http://localhost:18765/api/research/"+path, strings.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("X-Roundtable", "1")
		w := httptest.NewRecorder()
		api.ServeHTTP(w, req)
		if w.Code != want {
			t.Fatalf("%s %s: %d %s", method, path, w.Code, w.Body.String())
		}
		return w.Body.Bytes()
	}
	project := scienceWorkflowDecode[research.Project](t, request("POST", "projects", `{"name":"Study"}`, 201))
	scope := "?project=" + project.ID
	request("POST", "tools/feedback"+scope, `{"arxiv":"2402.00001v1","state":"saved"}`, 200)
	got := scienceWorkflowDecode[discoveryState](t, request("GET", "tools/discover"+scope, "", 200))
	if got.Feedback["2402.00001"] != "saved" {
		t.Fatal(got)
	}
	global := scienceWorkflowDecode[discoveryState](t, request("GET", "tools/discover", "", 200))
	if len(global.Feedback) != 0 {
		t.Fatal(global)
	}
	removed := scienceWorkflowDecode[discoveryState](t, request("POST", "tools/feedback"+scope, `{"arxiv":"2402.00001v2","state":""}`, 200))
	if len(removed.Feedback) != 0 {
		t.Fatal(removed)
	}
	request("POST", "tools/feedback?project=unknown", `{"arxiv":"2402.00001","state":"saved"}`, 404)
}

func TestDiscoveryHistoryCategoryBoundaryAndRecoverableSelection(t *testing.T) {
	dir := t.TempDir()
	lab, err := research.New(filepath.Join(dir, "research"))
	if err != nil {
		t.Fatal(err)
	}
	arxiv := func(id, title, primary string, tags ...string) research.DiscoveryCandidate {
		return research.DiscoveryCandidate{Provider: "arXiv", PrimaryCategory: primary, PaperMetadata: research.PaperMetadata{
			Arxiv: id, Title: title, URL: "https://arxiv.org/abs/" + id, Tags: tags,
		}}
	}
	primary := arxiv("2404.00010v3", "Solar evaporation", "astro-ph.HE", "astro-ph.HE")
	cross := arxiv("2404.00020v1", "Secondary", "hep-ph", "hep-ph", "astro-ph.HE")
	duplicate := arxiv("2404.00010v1", "Earlier version", "astro-ph.HE", "astro-ph.HE")
	missingPrimary := arxiv("2404.00030v2", "Unknown primary field", "", "astro-ph.HE")
	deps := discoveryDependencies{search: func(_ context.Context, query string, limit int) ([]research.DiscoveryCandidate, error) {
		switch query {
		case `(all:"solar") AND (cat:astro-ph.HE)`:
			if limit != 24 {
				t.Fatalf("limit = %d", limit)
			}
			return []research.DiscoveryCandidate{primary, cross, duplicate, missingPrimary}, nil
		case `all:"graphs"`:
			return []research.DiscoveryCandidate{cross}, nil
		default:
			return nil, fmt.Errorf("provider unavailable")
		}
	}}
	call := func(method, route, params, body string, status int) *httptest.ResponseRecorder {
		t.Helper()
		r := httptest.NewRequest(method, "/api/research/tools/"+route+params, strings.NewReader(body))
		w := httptest.NewRecorder()
		serveDiscovery(lab, dir, w, r, route, deps)
		if w.Code != status {
			t.Fatalf("%s %s: %d %s", method, r.URL, w.Code, w.Body.String())
		}
		return w
	}
	projectReq := httptest.NewRequest("POST", "/api/research/projects", strings.NewReader(`{"name":"Sun"}`))
	projectReq.Header.Set("Content-Type", "application/json")
	projectResp := httptest.NewRecorder()
	lab.ServeHTTP(projectResp, projectReq)
	if projectResp.Code != 201 {
		t.Fatal(projectResp.Body.String())
	}
	project := scienceWorkflowDecode[research.Project](t, projectResp.Body.Bytes())
	scope := "?project=" + project.ID
	firstBody := `{"query":"solar","categories":["ASTRO-PH.HE"],"cross_list":false,"top_k":4}`
	first := scienceWorkflowDecode[discoveryView](t, call("POST", "discover", scope, firstBody, 200).Body.Bytes())
	if len(first.Items) != 1 || first.Items[0].Arxiv != primary.Arxiv || first.Items[0].URL != primary.URL || len(first.AtomQueries) != 1 {
		t.Fatalf("unexpected classification and source: %+v", first)
	}
	again := scienceWorkflowDecode[discoveryView](t, call("POST", "discover", scope, firstBody, 200).Body.Bytes())
	if again.ID != first.ID || len(again.History) != 1 {
		t.Fatalf("unchanged run repeated: %+v", again.History)
	}
	call("POST", "feedback", scope, fmt.Sprintf(`{"run":%q,"key":"2404.00010","state":"liked"}`, first.ID), 200)
	second := scienceWorkflowDecode[discoveryView](t, call("POST", "discover", scope, `{"query":"graphs"}`, 200).Body.Bytes())
	if second.ID == first.ID || len(second.History) != 2 || second.Feedback["2404.00010"] != "liked" {
		t.Fatalf("history or feedback lost: %+v", second)
	}
	call("POST", "discover", scope, `{"query":"offline"}`, 502)
	lab, err = research.New(filepath.Join(dir, "research"))
	if err != nil {
		t.Fatal(err)
	}
	latest := scienceWorkflowDecode[discoveryView](t, call("GET", "discover", scope, "", 200).Body.Bytes())
	history := scienceWorkflowDecode[discoveryView](t, call("GET", "discover", scope+"&run="+first.ID, "", 200).Body.Bytes())
	if latest.ID != second.ID || len(latest.History) != 2 || history.ID != first.ID || history.CrossList || history.Feedback["2404.00010"] != "liked" {
		t.Fatalf("failed request or relaunch changed state: latest=%+v history=%+v", latest, history)
	}
	call("GET", "discover", "?run="+first.ID, "", 404)
	selection := fmt.Sprintf(`{"run":%q,"key":"2404.00010"}`, first.ID)
	one := scienceWorkflowDecode[research.Paper](t, call("POST", "select-discovery", scope, selection, 200).Body.Bytes())
	two := scienceWorkflowDecode[research.Paper](t, call("POST", "select-discovery", scope, selection, 200).Body.Bytes())
	if one.ID == "" || two.ID != one.ID || two.Revision != one.Revision || two.Arxiv != primary.Arxiv || len(two.ProjectIDs) != 1 || two.ProjectIDs[0] != project.ID {
		t.Fatalf("selection did not preserve source and scope: %+v %+v", one, two)
	}
	call("POST", "select-discovery", "", selection, 404)
	call("POST", "archive-discovery", scope, fmt.Sprintf(`{"run":%q}`, first.ID), 200)
	call("GET", "discover", scope+"&run="+first.ID, "", 404)
	state, err := loadDiscovery(filepath.Join(dir, "discovery."+project.ID+".json"))
	if err != nil || len(state.Runs) != 2 || !state.Runs[1].Archived || state.FeedbackPapers["2404.00010"].Run != first.ID {
		t.Fatalf("archive discarded source or feedback: %+v %v", state, err)
	}
}

func TestDiscoveryLegacyAndRejectsUnreadableState(t *testing.T) {
	dir := t.TempDir()
	file := filepath.Join(dir, "discovery.json")
	write := func(raw string) {
		t.Helper()
		if err := os.WriteFile(file, []byte(raw), 0600); err != nil {
			t.Fatal(err)
		}
	}
	write(`{"query":"legacy","updated":"2026-05-01T08:00:00Z","items":[{"arxiv":"2404.00001v1","title":"Example"}],"feedback":{"2404.00001v1":"saved"},"custom":{"keep":true}}`)
	state, err := loadDiscovery(file)
	if err != nil {
		t.Fatal(err)
	}
	view, _ := state.view("")
	if view.ID != "legacy" || view.Feedback["2404.00001v1"] != "saved" || len(view.Items) != 1 {
		t.Fatalf("legacy state lost: %+v", view)
	}
	if err := state.save(file); err != nil {
		t.Fatal(err)
	}
	state, err = loadDiscovery(file)
	if err != nil || state.Runs[0].Items[0].Arxiv != "2404.00001v1" || string(state.unknown["custom"]) != `{"keep":true}` {
		t.Fatalf("rewritten state lost fields: %+v %v", state, err)
	}
	for _, invalid := range []string{`{"schema_version":2,"runs":[]}`, `{"schema_version":null,"runs":[]}`, `{"schema_version":1}`, `{"runs":[`} {
		write(invalid)
		lab, err := research.New(filepath.Join(dir, "research"))
		if err != nil {
			t.Fatal(err)
		}
		r := httptest.NewRequest("POST", "/api/research/tools/feedback", strings.NewReader(`{"arxiv":"2404.00001v1","state":"hidden"}`))
		w := httptest.NewRecorder()
		serveDiscovery(lab, dir, w, r, "feedback", discoveryDependencies{})
		saved, err := os.ReadFile(file)
		if w.Code != 500 || err != nil || string(saved) != invalid {
			t.Fatalf("damaged or newer state overwritten: code %d: %s (%v)", w.Code, saved, err)
		}
	}
}

type discoveryAIStub struct {
	prompts []string
	fail    bool
}

func (a *discoveryAIStub) Catalog(context.Context) (gateway.Catalog, error) {
	return gateway.Catalog{Models: []gateway.Model{{ID: "fixture-model"}}}, nil
}

func (a *discoveryAIStub) Generate(_ context.Context, id, effort, rules, prompt, session string) (string, error) {
	a.prompts = append(a.prompts, prompt)
	if a.fail {
		return "", fmt.Errorf("provider unavailable")
	}
	if len(a.prompts) == 1 {
		return `{"query":"ti:evaporation"}`, nil
	}
	return `{"2404.00001":"Reads from the supplied arXiv metadata","2404.00002":"Not in the feed"}`, nil
}

func TestDiscoveryAIUsesConfiguredModelAndActualCandidates(t *testing.T) {
	paper := research.DiscoveryCandidate{PaperMetadata: research.PaperMetadata{Arxiv: "2404.00001v2", Title: "An arXiv result"}}
	ai := &discoveryAIStub{}
	var requests []string
	deps := discoveryDependencies{ai: ai, search: func(_ context.Context, q string, _ int) ([]research.DiscoveryCandidate, error) {
		requests = append(requests, q)
		return []research.DiscoveryCandidate{paper}, nil
	}}
	options := discoveryOptions{Query: "solar", Source: "arxiv", TopK: 3, AIModel: "fixture-model"}
	sources := research.DiscoveryContext{Project: research.Project{Name: "Research project", Path: "/private/path"}}
	run, err := buildDiscoveryRun(context.Background(), options, sources, discoveryState{}, deps)
	if err != nil || len(run.Items) != 1 || len(run.AIReview) != 1 || run.AIReview["2404.00001"] == "" || len(requests) != 2 || requests[0] != `all:"solar"` || requests[1] != "ti:evaporation" {
		t.Fatalf("AI response did not preserve arXiv evidence: %+v, %v", run, err)
	}
	if len(ai.prompts) != 2 || strings.Contains(ai.prompts[0], "/private/path") || !strings.Contains(ai.prompts[1], "An arXiv result") {
		t.Fatalf("unexpected prompts: %v", ai.prompts)
	}
	ai.fail = true
	run, err = buildDiscoveryRun(context.Background(), options, sources, discoveryState{}, deps)
	if err != nil || len(run.Items) != 1 || len(run.AIReview) != 0 || run.Notice == "" || len(requests) != 3 || requests[2] != `all:"solar"` {
		t.Fatalf("AI failure lost direct search: %+v, %v", run, err)
	}
}

func TestDiscoveryRankingUsesRealReferenceSignalsAndDiversifies(t *testing.T) {
	paper := func(arxiv, title, abstract string) research.DiscoveryCandidate {
		return research.DiscoveryCandidate{PaperMetadata: research.PaperMetadata{
			Arxiv: arxiv, Title: title, Abstract: abstract,
		}}
	}
	first := paper("2404.00001", "Solar dark matter evaporation", "Solar dark matter evaporation and capture")
	repeat := paper("2404.00002", "Solar dark matter evaporation", "Solar dark matter evaporation and capture")
	distinct := paper("2404.00003", "Dark matter detector calibration", "Neutrino flux and detector calibration")
	distinct.GraphEvidence = []research.DiscoveryCitation{{PaperID: "fixture-core", Kind: "cites"}}
	sources := research.DiscoveryContext{
		Project: research.Project{Name: "Solar dark matter"},
		Refs:    []research.Paper{{PaperMetadata: first.PaperMetadata}},
	}
	now := time.Now().UTC()
	run := discoveryRun{discoveryOptions: discoveryOptions{Query: "dark matter evaporation", Source: "arxiv", TopK: 3}}
	ranked := rankDiscovery([]research.DiscoveryCandidate{distinct, first, repeat}, sources, run, discoveryState{}, now)
	if len(ranked) != 3 || ranked[0].Arxiv != first.Arxiv || ranked[1].Arxiv != distinct.Arxiv ||
		!slices.Contains(ranked[0].Reasons, "与所选参考论文相关") {
		t.Fatalf("expected reference-first diversified ranking, got %+v", ranked)
	}
}
