package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"scistation.local/desktop/internal/meeting"
	"scistation.local/desktop/internal/research"
)

func TestLabSourceReviewAndSingleSeatRun(t *testing.T) {
	dir := t.TempDir()
	prefs, err := openSettings(dir)
	if err != nil {
		t.Fatal(err)
	}
	lab, err := research.New(filepath.Join(dir, "research"))
	if err != nil {
		t.Fatal(err)
	}
	const quote = "diffusion under fixed temperature"
	const verdict = "Determine whether the fixed-temperature approximation holds."
	engineDir := filepath.Join(dir, "meetings")
	delivered := make(chan string, 2)
	cancelled := make(chan struct{})
	const followup = "Compare the boundary case from this session."
	engine, err := meeting.New(engineDir, func(ctx context.Context, _, _, prompt, _ string) (string, error) {
		delivered <- prompt
		if strings.Contains(prompt, followup) {
			<-ctx.Done()
			close(cancelled)
			return "", ctx.Err()
		}
		select {
		case <-ctx.Done():
			return "", ctx.Err()
		default:
		}
		return `{"action":"say","text":"` + verdict + `"}`, nil
	}, func() meeting.Settings { return prefs.get().Settings })
	if err != nil {
		t.Fatal(err)
	}
	defer engine.Shutdown(context.Background())
	api := &apiServer{prefs: prefs, meetings: engine, research: lab}
	h := api.serve(8765)
	call := func(method, path string, in any, want int) []byte {
		t.Helper()
		b, err := json.Marshal(in)
		if err != nil {
			t.Fatal(err)
		}
		r := httptest.NewRequest(method, "http://127.0.0.1:8765"+path, bytes.NewReader(b))
		r.Header.Set("X-Roundtable", "1")
		r.Header.Set("Content-Type", "application/json")
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		if w.Code != want {
			t.Fatalf("%s %s: %d want %d - %s", method, path, w.Code, want, w.Body.String())
		}
		return w.Body.Bytes()
	}
	mkProj := func(name string) research.Project {
		return scienceWorkflowDecode[research.Project](t, call("POST", "/api/research/projects", map[string]string{"name": name}, 201))
	}
	p, q := mkProj("Workflow fixture"), mkProj("Separate project")
	notes := "/api/research/projects/" + p.ID + "/notes"
	n := scienceWorkflowDecode[research.Note](t, call("POST", notes, map[string]string{"title": "Method", "body": "😀\r\n" + quote}, 201))
	base := "/api/research/lab/sources/"
	loc := research.SourceLocation{Kind: "note", ID: n.ID, Offset: 2}
	in := labSourcesRequest{ProjectID: p.ID, Workflow: "gap-planning", Location: loc}
	search := in
	search.Query = "DIFFUSION"
	matches := scienceWorkflowDecode[research.WorkflowMatches](t, call("POST", base+"search", search, 200))
	if len(matches.Items) != 1 || matches.Items[0].Offset != 2 || !strings.Contains(matches.Items[0].Text, quote) {
		t.Fatal(matches)
	}
	search.ProjectID = q.ID
	call("POST", base+"search", search, 422)
	indexed := labSourcesRequest{ProjectID: p.ID, Mode: "hybrid", Query: "fixed temperature"}
	hits := scienceWorkflowDecode[research.WorkflowRetrieval](t, call("POST", base+"search", indexed, 200))
	if len(hits.Items) != 1 || hits.Items[0].ID != n.ID || hits.Trace.Mode != "hybrid" || hits.Trace.Verified != 1 {
		t.Fatal(hits)
	}
	found := hits.Items[0]
	previewed := scienceWorkflowDecode[research.WorkflowSource](t, call("POST", base+"preview",
		labSourcesRequest{ProjectID: p.ID, Location: found.SourceLocation}, 200))
	if previewed.Hash != found.Hash || !strings.HasPrefix(previewed.Text, found.Text) {
		t.Fatal(previewed, found)
	}
	select {
	case <-delivered:
		t.Fatal("local search or original preview reached the model")
	default:
	}
	indexed.ProjectID, indexed.Scope = "", "global"
	call("POST", base+"search", indexed, 400)
	source := scienceWorkflowDecode[research.WorkflowSource](t, call("POST", base+"preview", in, 200))
	if source.Text != quote || len(source.Hash) != 64 {
		t.Fatal(source)
	}
	in.Citations = []labCitation{{SourceLocation: loc, Hash: source.Hash, Quote: quote}}
	in.ProjectID = q.ID
	call("POST", base+"prepare", in, 422)
	in.ProjectID = p.ID
	in.Workflow = "paper-reading"
	call("POST", base+"prepare", in, 422)
	in.Workflow = "gap-planning"
	in.Citations[0].Quote = "unrecorded text"
	call("POST", base+"prepare", in, 409)
	in.Citations[0].Quote = quote
	mats := scienceWorkflowDecode[[]meeting.Material](t, call("POST", base+"prepare", in, 200))
	if len(mats) != 1 || !strings.Contains(mats[0].Excerpt, quote) || !strings.Contains(mats[0].Excerpt, source.Hash) {
		t.Fatal(mats)
	}
	call("PATCH", notes+"/"+n.ID, map[string]any{"revision": n.Revision, "body": "edited later"}, 200)
	call("POST", base+"prepare", in, 409)
	engine.SetProjectAccess(func(id string, use func(string) error) error {
		if id != p.ID {
			return fmt.Errorf("unbound project")
		}
		return use(p.Path)
	})
	sess, err := engine.CreateScopedConfiguredWithMaterials("Plan next steps", meeting.ProjectScope{ID: p.ID, Directory: p.Path}, []meeting.Member{{Model: "fixture/research", Effort: "auto"}}, "prioritize", nil, []string{mats[0].ID})
	if err != nil {
		t.Fatal(err)
	}
	runURL := "/api/studio/sessions/" + sess.ID
	call("POST", runURL+"/run", map[string]any{"expected_round": 0, "allow_edits": false}, 202)
	select {
	case prompt := <-delivered:
		if !strings.Contains(prompt, quote) || !strings.Contains(prompt, source.Hash) {
			t.Fatal("missing cited source in model request")
		}
	case <-time.After(5 * time.Second):
		t.Fatal("model was not called")
	}
	for until := time.Now().Add(5 * time.Second); time.Now().Before(until); {
		sess = scienceWorkflowDecode[*meeting.Session](t, call("GET", runURL, nil, 200))
		if sess.Status != "running" {
			break
		}
		time.Sleep(5 * time.Millisecond)
	}
	if len(sess.Rounds) != 1 || len(sess.Rounds[0].Turns) != 1 || sess.Rounds[0].Turns[0].Text != verdict || sess.Rounds[0].Settings.AllowEdits || sess.ProjectID != p.ID {
		t.Fatalf("bad run: %+v", sess.Rounds)
	}
	call("POST", runURL+"/run", map[string]any{"expected_round": 1, "allow_edits": false, "note": followup}, 202)
	select {
	case prompt := <-delivered:
		if !strings.Contains(prompt, followup) || !strings.Contains(prompt, verdict) {
			t.Fatal("follow-up lost the prior turn")
		}
	case <-time.After(5 * time.Second):
		t.Fatal("follow-up did not reach the model")
	}
	call("POST", runURL+"/cancel", map[string]any{}, 202)
	select {
	case <-cancelled:
	case <-time.After(5 * time.Second):
		t.Fatal("cancel failed to reach the model")
	}
	if err := engine.Shutdown(context.Background()); err != nil {
		t.Fatal(err)
	}
	archived, err := meeting.New(engineDir, func(context.Context, string, string, string, string) (string, error) {
		t.Error("offline replay contacted provider")
		return "", nil
	}, func() meeting.Settings { return prefs.get().Settings })
	if err != nil {
		t.Fatal(err)
	}
	defer archived.Shutdown(context.Background())
	got, err := archived.Get(sess.ID)
	if err != nil || got.ProjectID != p.ID || got.Materials[0].Excerpt != mats[0].Excerpt || len(got.Events) == 0 || len(got.Rounds) != 2 || got.Status != "partial" || got.Rounds[1].Turns[0].Status != "error" {
		t.Fatal("incomplete offline replay", err)
	}
	remaining := scienceWorkflowDecode[[]research.Note](t, call(http.MethodGet, notes, nil, 200))
	if len(remaining) != 1 || remaining[0].Body != "edited later" {
		t.Fatal("model output wrote a note without human review")
	}
	moduleRoute := "/api/research/modules?project=" + p.ID
	state := scienceWorkflowDecode[struct{ Revision string }](t, call("GET", moduleRoute, nil, 200))
	call("PATCH", moduleRoute, map[string]any{"action": "set", "id": "wiki", "enabled": false, "revision": state.Revision}, 200)
	call("POST", base+"preview", in, 409)
}

func TestLabWorkflowEvidenceRequirements(t *testing.T) {
	for _, spec := range []struct {
		id           string
		papers, refs int
		allowed      bool
	}{
		{"paper-reading", 0, 2, false}, {"paper-reading", 1, 1, true}, {"related-work", 1, 4, false}, {"related-work", 2, 2, true}, {"gap-planning", 0, 0, false}, {"gap-planning", 0, 1, true},
	} {
		if (labRequiredEvidence(spec.id, spec.papers, spec.refs) == nil) != spec.allowed {
			t.Fatal(spec)
		}
	}
}
