package main

import (
	"archive/zip"
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"

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
	md, err := markdownFromZip(buf.Bytes())
	if err != nil || md != "# Converted paper" {
		t.Fatal(md, err)
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
