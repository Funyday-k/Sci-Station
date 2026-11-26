package desktop

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"
	"unicode/utf8"

	"scistation.local/desktop/internal/meeting"
	"scistation.local/desktop/internal/research"
)

func TestReviewedProjectSourceWorkflow(t *testing.T) {
	const host = "http://127.0.0.1:8765"
	dir := t.TempDir()
	var api http.Handler
	var engine *meeting.Engine
	var service *research.Service
	start := func() {
		t.Helper()
		prefs, err := openSettings(dir)
		if err != nil {
			t.Fatal(err)
		}
		service, err = research.New(filepath.Join(dir, "research"))
		if err != nil {
			t.Fatal(err)
		}
		engine, err = meeting.New(filepath.Join(dir, "meetings"), func(context.Context, string, string, string, string) (string, error) {
			return `{"action":"say","text":"Published review fixture"}`, nil
		}, func() meeting.Settings { return prefs.get().Settings })
		if err != nil {
			t.Fatal(err)
		}
		service.SetPathValidator(func(string) bool { return true })
		engine.SetProjectAccess(service.WithProjectDirectory)
		api = (&apiServer{prefs: prefs, meetings: engine, research: service}).serve(8765)
	}
	start()
	defer func() { _ = engine.Shutdown(context.Background()) }()
	call := func(method, path, contentType string, data io.Reader, want int) []byte {
		t.Helper()
		req := httptest.NewRequest(method, host+path, data)
		req.Header.Set("X-Roundtable", "1")
		req.Header.Set("Origin", host)
		req.Header.Set("Content-Type", contentType)
		resp := httptest.NewRecorder()
		api.ServeHTTP(resp, req)
		if resp.Code != want {
			t.Fatalf("%s %s: %d want %d: %.500s", method, path, resp.Code, want, resp.Body.String())
		}
		return resp.Body.Bytes()
	}
	js := func(method, path string, input any, want int) []byte {
		t.Helper()
		data, err := json.Marshal(input)
		if err != nil {
			t.Fatal(err)
		}
		return call(method, path, "application/json", bytes.NewReader(data), want)
	}
	upload := func(path, name string, data []byte, meta any) []byte {
		t.Helper()
		var buf bytes.Buffer
		form := multipart.NewWriter(&buf)
		if meta != nil {
			encoded, err := json.Marshal(meta)
			if err != nil {
				t.Fatal(err)
			}
			if err := form.WriteField("metadata", string(encoded)); err != nil {
				t.Fatal(err)
			}
		}
		f, err := form.CreateFormFile("file", name)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := f.Write(data); err != nil {
			t.Fatal(err)
		}
		if err := form.Close(); err != nil {
			t.Fatal(err)
		}
		return call("POST", path, form.FormDataContentType(), &buf, 201)
	}
	project := scienceWorkflowDecode[research.Project](t, js("POST", "/api/research/projects", map[string]string{"name": "Review project"}, 201))
	path := func(p research.Project) string { return "/api/research/projects/" + p.ID }
	const wikiText = "😀\r\nPublished Wiki evidence   \r\nFurther analysis."
	const wikiQuote = "Published Wiki evidence   \n"
	note := scienceWorkflowDecode[research.Note](t, js("POST", path(project)+"/notes", map[string]string{"title": "Methods", "body": wikiText}, 201))
	const fileText = "a preliminary line\r\n😀 Text from the actual attached file.\r\nend"
	const fileQuote = "Text from the actual attached file."
	material := scienceWorkflowDecode[research.Material](t, upload(path(project)+"/materials", "observations.txt", []byte(fileText), nil))
	const sources = "/api/research/lab/sources/"
	cite := func(p research.Project, loc research.SourceLocation, quote string) labCitation {
		t.Helper()
		body := labSourcesRequest{ProjectID: p.ID, Workflow: "gap-planning", Location: loc}
		source := scienceWorkflowDecode[research.WorkflowSource](t, js("POST", sources+"preview", body, 200))
		if !strings.HasPrefix(source.Text, quote) {
			t.Fatalf("source text differs: %q", source.Text)
		}
		return labCitation{SourceLocation: loc, Hash: source.Hash, Quote: quote}
	}
	wikiRef := cite(project, research.SourceLocation{Kind: "note", ID: note.ID, Offset: 2}, wikiQuote)
	materialRef := cite(project, research.SourceLocation{Kind: "material", ID: material.ID, Offset: utf8.RuneCountInString("a preliminary line\n😀 ")}, fileQuote)
	createMeeting := func(p research.Project, refs ...labCitation) string {
		t.Helper()
		in := labSourcesRequest{ProjectID: p.ID, Workflow: "gap-planning", Citations: refs}
		attachments := scienceWorkflowDecode[[]meeting.Material](t, js("POST", sources+"prepare", in, 200))
		ids := make([]string, 0, len(attachments))
		for _, m := range attachments {
			ids = append(ids, m.ID)
		}
		if len(ids) != len(refs) {
			t.Fatalf("received %d materials for %d sources", len(ids), len(refs))
		}
		room, err := engine.CreateScopedConfiguredWithMaterials("Review project evidence", meeting.ProjectScope{ID: p.ID, Directory: p.Path},
			[]meeting.Member{{Model: "fixture/review", Effort: "auto"}}, "prioritize", nil, ids)
		if err != nil {
			t.Fatal(err)
		}
		root := "/api/studio/sessions/" + room.ID
		js("POST", root+"/run", map[string]any{"expected_round": 0, "allow_edits": false}, 202)
		for limit := time.Now().Add(5 * time.Second); time.Now().Before(limit); {
			room, err = engine.Get(room.ID)
			if err != nil {
				t.Fatal(err)
			}
			if room.Status == "ready" && len(room.Rounds) == 1 && len(room.Rounds[0].Turns) == 1 {
				return root + "/research-reviews"
			}
			time.Sleep(10 * time.Millisecond)
		}
		t.Fatalf("meeting output unavailable: %+v", room)
		return ""
	}
	draft := func(reviewPath string, p research.Project, id, action, title string, want int) research.MeetingReview {
		t.Helper()
		return scienceWorkflowDecode[research.MeetingReview](t, js("POST", reviewPath, research.ReviewRequest{
			ProjectID: p.ID, OperationID: strings.Repeat(id, 32), Decision: "propose",
			Proposal: &research.ReviewProposal{ProjectRevision: p.Revision, TurnID: "round-1-member-1", Action: action, Title: title, Body: "Review summary"},
		}, want))
	}
	decide := func(route string, review research.MeetingReview, decision string, want int) research.MeetingReview {
		t.Helper()
		data := js("POST", route, research.ReviewRequest{Decision: decision, ProjectID: review.ProjectID, OperationID: review.ID, Revision: review.Revision}, want)
		if want >= 400 {
			return research.MeetingReview{}
		}
		return scienceWorkflowDecode[research.MeetingReview](t, data)
	}
	locator := func(e research.Evidence) string {
		if e.Source == nil {
			t.Fatalf("missing original project source in %+v", e)
		}
		return fmt.Sprintf("/api/research/projects/%s/source-excerpts/%s/%s?", e.Source.ProjectID, e.Source.Kind, e.Source.ID) +
			(url.Values{"offset": {fmt.Sprint(e.Source.Offset)}, "end": {fmt.Sprint(e.Source.End)}, "fingerprint": {e.SourceHash}}).Encode()
	}
	evidence := func(row research.MeetingReview, ref labCitation, p research.Project) research.Evidence {
		t.Helper()
		if len(row.Evidence) != 1 {
			t.Fatalf("evidence lost: %+v", row.Evidence)
		}
		e := row.Evidence[0]
		if e.Source == nil || e.Source.ProjectID != p.ID || e.Source.ID != ref.ID || e.Source.Kind != ref.Kind ||
			e.Source.Offset != ref.Offset || e.Source.End != ref.Offset+utf8.RuneCountInString(ref.Quote) ||
			e.SourceHash != ref.Hash || e.Quote != ref.Quote || e.PaperID != "" || e.MeetingID == "" || e.TurnID == "" {
			t.Fatalf("wrong persisted locator: %+v %#v", e, e.Source)
		}
		return e
	}

	// A Wiki-only meeting has durable exact text, including trailing whitespace,
	// and keeps following its stable identity after a title or folder change.
	wikiReview := createMeeting(project, wikiRef)
	rejected := draft(wikiReview, project, "1", "create-note", "Rejected", 201)
	evidence(rejected, wikiRef, project)
	decide(wikiReview, rejected, "reject", 200)
	decide(wikiReview, rejected, "reject", 200)
	decide(wikiReview, rejected, "accept", 409)
	pendingWiki := draft(wikiReview, project, "2", "create-note", "Reviewed Wiki", 201)
	targetWiki := evidence(pendingWiki, wikiRef, project)
	// A body edit, unlike a move, invalidates the approved full source hash.
	oldPath := path(project) + "/notes/" + note.ID
	patched := scienceWorkflowDecode[research.Note](t, js("PATCH", oldPath, map[string]any{"revision": note.Revision, "body": wikiText + " EDIT"}, 200))
	decide(wikiReview, pendingWiki, "accept", 409)
	js("GET", locator(targetWiki), nil, 409)
	moved := scienceWorkflowDecode[research.Note](t, js("PATCH", oldPath,
		map[string]any{"revision": patched.Revision, "body": wikiText, "title": "Renamed methods", "namespace": "methods/capture"}, 200))
	wikiDone := decide(wikiReview, pendingWiki, "accept", 200)
	if retry := decide(wikiReview, pendingWiki, "accept", 200); retry.ResultID != wikiDone.ResultID {
		t.Fatal("Wiki write was repeated")
	}
	n := scienceWorkflowDecode[research.Note](t, js("GET", path(project)+"/notes/"+wikiDone.ResultID, nil, 200))
	if len(n.Evidence) != 1 || n.Evidence[0].Quote != wikiQuote || !strings.Contains(n.Body, "note="+note.ID) {
		t.Fatalf("saved note lacks its exact Wiki citation: %+v", n)
	}
	wikiHit := scienceWorkflowDecode[research.ProjectSourceExcerpt](t, js("GET", locator(targetWiki), nil, 200))
	if wikiHit.Title != "Renamed methods" || wikiHit.Quote != wikiQuote || wikiHit.Line != 2 || wikiHit.Column != 1 {
		t.Fatalf("Wiki target did not resolve the selected original: %+v", wikiHit)
	}

	// A material-only task never gets an empty paper ID. The review consults
	// the stored original bytes even when the replacement has the same size.
	materialReview := createMeeting(project, materialRef)
	pendingMaterial := draft(materialReview, project, "3", "create-task", "Reviewed material", 201)
	targetMaterial := evidence(pendingMaterial, materialRef, project)
	blob := filepath.Join(dir, "research", "blobs", material.ID)
	if err := os.WriteFile(blob, []byte(strings.Replace(fileText, "actual", "edited", 1)), 0600); err != nil {
		t.Fatal(err)
	}
	decide(materialReview, pendingMaterial, "accept", 409)
	js("GET", locator(targetMaterial), nil, 409)
	if err := os.Remove(blob); err != nil {
		t.Fatal(err)
	}
	decide(materialReview, pendingMaterial, "accept", 409)
	if err := os.WriteFile(blob, []byte(fileText), 0600); err != nil {
		t.Fatal(err)
	}
	materialPath := path(project) + "/materials/" + material.ID
	js("PATCH", materialPath, map[string]any{"revision": material.Revision, "name": "renamed-observations.txt"}, 200)
	if err := engine.Shutdown(context.Background()); err != nil {
		t.Fatal(err)
	}
	start()
	accepted := decide(materialReview, pendingMaterial, "accept", 200)
	task := scienceWorkflowDecode[research.Task](t, js("GET", path(project)+"/tasks/"+accepted.ResultID, nil, 200))
	if len(task.Evidence) != 1 || task.Evidence[0].Source == nil || task.Evidence[0].Source.ID != material.ID ||
		len(task.RelatedPaperIDs) != 0 || !strings.Contains(task.Description, "material="+material.ID) {
		t.Fatalf("task lost its material source: %+v", task)
	}
	materialHit := scienceWorkflowDecode[research.ProjectSourceExcerpt](t, js("GET", locator(targetMaterial), nil, 200))
	if materialHit.Title != "renamed-observations.txt" || materialHit.Quote != fileQuote || materialHit.Line != 2 || materialHit.Column != 3 {
		t.Fatalf("material target did not recover: %+v", materialHit)
	}

	t.Run("grant revocation", func(t *testing.T) {
		external, err := filepath.EvalSymlinks(t.TempDir())
		if err != nil {
			t.Fatal(err)
		}
		ext := scienceWorkflowDecode[research.Project](t, js("POST", "/api/research/projects",
			map[string]string{"name": "External", "path": external}, 201))
		row := scienceWorkflowDecode[research.Note](t, js("POST", path(ext)+"/notes", map[string]string{"title": "Source", "body": "External scope"}, 201))
		ref := cite(ext, research.SourceLocation{Kind: "note", ID: row.ID}, "External scope")
		endpoint := createMeeting(ext, ref)
		proposal := draft(endpoint, ext, "4", "create-note", "Revoked", 201)
		js("POST", path(ext)+"/directory", map[string]any{"revision": ext.Revision, "path": ""}, 200)
		decide(endpoint, proposal, "accept", 403)
		js("GET", locator(evidence(proposal, ref, ext)), nil, 403)
		decide(endpoint, proposal, "reject", 200)
	})

	t.Run("Markdown-only paper sections survive review and stale citations fail", func(t *testing.T) {
		const quote = "The measured loss rate decreases."
		p := scienceWorkflowDecode[research.Paper](t, js("POST", "/api/research/papers", map[string]any{"title": "Original text fixture", "project_ids": []string{project.ID}}, 201))
		route := "/api/research/papers/" + p.ID + "/body"
		save := func(p research.Paper, body string) research.Paper {
			var buf bytes.Buffer
			form := multipart.NewWriter(&buf)
			if err := form.WriteField("revision", fmt.Sprint(p.Revision)); err != nil {
				t.Fatal(err)
			}
			part, err := form.CreateFormFile("file", "source.md")
			if err != nil {
				t.Fatal(err)
			}
			if _, err = io.WriteString(part, body); err != nil {
				t.Fatal(err)
			}
			if err = form.Close(); err != nil {
				t.Fatal(err)
			}
			return scienceWorkflowDecode[research.Paper](t, call("POST", route, form.FormDataContentType(), &buf, 200))
		}
		p = save(p, "# Rate\r\n## Result\r\n"+quote+"\r\n")
		if p.HasPDF {
			t.Fatal("fixture must have Markdown only")
		}
		loc := research.SourceLocation{Kind: "paper-markdown", ID: p.ID}
		page := scienceWorkflowDecode[research.WorkflowSource](t, js("POST", sources+"preview", labSourcesRequest{ProjectID: project.ID, Location: loc, Line: 3}, 200))
		if page.Line != 3 || page.Heading != "Result" {
			t.Fatal(page)
		}
		ref := cite(project, page.SourceLocation, quote)
		prepared := scienceWorkflowDecode[[]meeting.Material](t, js("POST", sources+"prepare", labSourcesRequest{ProjectID: project.ID, Workflow: "paper-reading", Citations: []labCitation{ref}}, 200))
		if len(prepared) != 1 || !strings.Contains(prepared[0].Excerpt, `"lineStart":3`) {
			t.Fatal(prepared)
		}
		endpoint := createMeeting(project, ref)
		pending := draft(endpoint, project, "6", "create-task", "Check loss rate", 201)
		accepted := decide(endpoint, pending, "accept", 200)
		task := scienceWorkflowDecode[research.Task](t, js("GET", path(project)+"/tasks/"+accepted.ResultID, nil, 200))
		if !slices.Equal(task.RelatedPaperIDs, []string{p.ID}) || len(task.Evidence) != 1 || task.Evidence[0].Source.Kind != "paper-markdown" {
			t.Fatal(task)
		}
		link := locator(task.Evidence[0])
		source := scienceWorkflowDecode[research.ProjectSourceExcerpt](t, js("GET", link, nil, 200))
		if source.Line != 3 || source.Revision != 1 || source.Quote != quote {
			t.Fatal(source)
		}
		again := draft(endpoint, project, "7", "create-note", "Another review", 201)
		save(p, "# Changed\nCorrected observation.")
		js("GET", link, nil, 409)
		decide(endpoint, again, "accept", 409)
	})
	t.Run("mixed PDF and project sources", func(t *testing.T) {
		const pdfQuote = "Verbatim text from the original PDF"
		paper := scienceWorkflowDecode[research.Paper](t, upload("/api/research/papers", "source.pdf", scienceWorkflowPDF(pdfQuote),
			map[string]any{"title": "PDF source", "project_ids": []string{project.ID}}))
		preview := httptest.NewRecorder()
		api.ServeHTTP(preview, httptest.NewRequest("GET", host+"/api/research/papers/"+paper.ID+"/pages/1", nil))
		if preview.Code == 422 && strings.Contains(preview.Body.String(), "PDFKit") {
			t.Skip("verified PDF selection requires macOS PDFKit")
		}
		pdfRef := cite(project, research.SourceLocation{Kind: "paper", ID: paper.ID, Page: 1}, pdfQuote)
		endpoint := createMeeting(project, pdfRef, wikiRef, materialRef)
		row := draft(endpoint, project, "5", "create-task", "Mixed sources", 201)
		if len(row.Evidence) != 3 || row.Evidence[0].PaperID != paper.ID || row.Evidence[0].Source != nil ||
			row.Evidence[1].Source == nil || row.Evidence[2].Source == nil {
			t.Fatalf("mixed citation formats changed: %+v", row.Evidence)
		}
		commit := decide(endpoint, row, "accept", 200)
		task := scienceWorkflowDecode[research.Task](t, js("GET", path(project)+"/tasks/"+commit.ResultID, nil, 200))
		if len(task.Evidence) != 3 || !slices.Equal(task.RelatedPaperIDs, []string{paper.ID}) {
			t.Fatalf("mixed task evidence lost: %+v", task)
		}
	})
	// A deleted/archived source can no longer be followed. A duplicate
	// decision still returns the receipt for the already committed note.
	js("DELETE", oldPath+"?revision="+fmt.Sprint(moved.Revision), nil, 204)
	js("GET", locator(targetWiki), nil, 404)
	if retry := decide(wikiReview, pendingWiki, "accept", 200); retry.ResultID != wikiDone.ResultID {
		t.Fatal("a retry after archiving lost its committed receipt")
	}
}

func TestRecordedProjectEvidenceAcceptsPreviousMarkerWithNoEnd(t *testing.T) {
	const project = "11111111111111111111111111111111"
	const note = "22222222222222222222222222222222"
	meta := map[string]any{"projectId": project, "kind": "note", "id": note, "sha256": strings.Repeat("1", 64), "offset": 0}
	marker := func() string {
		data, err := json.Marshal(meta)
		if err != nil {
			t.Fatal(err)
		}
		return string(data) + "\n\n😀 quote"
	}
	result, err := recordedProjectEvidence(marker(), project)
	if err != nil || result.Source == nil || result.Source.Offset != 0 || result.Source.End != 7 {
		t.Fatalf("legacy source marker lost its Unicode range: %+v %v", result, err)
	}
	meta["end"] = 6
	if _, err := recordedProjectEvidence(marker(), project); err == nil {
		t.Fatal("a range inconsistent with its recorded quote was accepted")
	}
	meta["end"] = 7
	if _, err := recordedProjectEvidence(marker(), strings.Repeat("3", 32)); err == nil {
		t.Fatal("a source outside the meeting project was accepted")
	}
}
