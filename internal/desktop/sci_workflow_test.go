package desktop

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"scistation.local/desktop/internal/meeting"
	"scistation.local/desktop/internal/research"
)

// A searchable, single-page PDF with real cross-reference offsets.
func scienceWorkflowPDF(line string) []byte {
	text := "BT /F1 18 Tf 20 140 Td (" + line + ") Tj ET\n"
	objects := []string{
		"<< /Type /Catalog /Pages 2 0 R >>",
		"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
		"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 450 250] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
		"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
		fmt.Sprintf("<< /Length %d >>\nstream\n%sendstream", len(text), text),
	}
	var pdf bytes.Buffer
	pdf.WriteString("%PDF-1.4\n")
	offsets := []int{}
	for i, obj := range objects {
		offsets = append(offsets, pdf.Len())
		fmt.Fprintf(&pdf, "%d 0 obj\n%s\nendobj\n", i+1, obj)
	}
	xref := pdf.Len()
	fmt.Fprintf(&pdf, "xref\n0 %d\n0000000000 65535 f \n", len(objects)+1)
	for _, offset := range offsets {
		fmt.Fprintf(&pdf, "%010d 00000 n \n", offset)
	}
	fmt.Fprintf(&pdf, "trailer\n<< /Root 1 0 R /Size %d >>\nstartxref\n%d\n%%%%EOF\n", len(objects)+1, xref)
	return pdf.Bytes()
}

func scienceWorkflowDecode[T any](t *testing.T, b []byte) T {
	t.Helper()
	var result T
	if err := json.Unmarshal(b, &result); err != nil {
		t.Fatalf("decode %s: %v", b, err)
	}
	return result
}

func TestSciStationPaperMeetingAndReviewedWriteback(t *testing.T) {
	const host = "http://127.0.0.1:8765"
	const quote = "Mass changes the evaporation rate"
	const verdict = "Check the stated mass range before applying this result."
	dir := t.TempDir()
	start := func() (http.Handler, *meeting.Engine) {
		t.Helper()
		prefs, err := openSettings(dir)
		if err != nil {
			t.Fatal(err)
		}
		lab, err := research.New(filepath.Join(dir, "research"))
		if err != nil {
			t.Fatal(err)
		}
		engine, err := meeting.New(filepath.Join(dir, "studio"), func(_ context.Context, _, _, prompt, _ string) (string, error) {
			if !strings.Contains(prompt, quote) {
				return "", fmt.Errorf("review seat did not receive selected paper text")
			}
			out, err := json.Marshal(map[string]string{"action": "say", "text": verdict})
			return string(out), err
		}, func() meeting.Settings { return prefs.get().Settings })
		if err != nil {
			t.Fatal(err)
		}
		return (&apiServer{prefs: prefs, research: lab, meetings: engine}).serve(8765), engine
	}
	api, engine := start()
	defer func() { _ = engine.Shutdown(context.Background()) }()
	do := func(req *http.Request, status int) []byte {
		t.Helper()
		out := httptest.NewRecorder()
		api.ServeHTTP(out, req)
		if out.Code != status {
			t.Fatalf("%s %s: got %d, want %d: %.360s", req.Method, req.URL.Path, out.Code, status, out.Body.String())
		}
		return out.Body.Bytes()
	}
	req := func(method, path string, obj any) *http.Request {
		t.Helper()
		body, err := json.Marshal(obj)
		if err != nil {
			t.Fatal(err)
		}
		r := httptest.NewRequest(method, host+path, bytes.NewReader(body))
		r.Header.Set("Content-Type", "application/json")
		r.Header.Set("Origin", host)
		r.Header.Set("X-Roundtable", "1")
		return r
	}
	upload := func(path, name string, body []byte, metadata any) []byte {
		t.Helper()
		var buf bytes.Buffer
		form := multipart.NewWriter(&buf)
		if metadata != nil {
			meta, err := json.Marshal(metadata)
			if err != nil {
				t.Fatal(err)
			}
			if err = form.WriteField("metadata", string(meta)); err != nil {
				t.Fatal(err)
			}
		}
		file, err := form.CreateFormFile("file", name)
		if err != nil {
			t.Fatal(err)
		}
		if _, err = file.Write(body); err != nil {
			t.Fatal(err)
		}
		if err = form.Close(); err != nil {
			t.Fatal(err)
		}
		r := httptest.NewRequest("POST", host+path, &buf)
		r.Header.Set("Content-Type", form.FormDataContentType())
		r.Header.Set("X-Roundtable", "1")
		r.Header.Set("Origin", host)
		return do(r, 201)
	}
	// Requests stay in process; neither web routing nor PDF capture launches a window.
	for _, path := range []string{"/", "/research", "/reader", "/studio", "/tools"} {
		if b := do(req("GET", path, nil), 200); !bytes.Contains(bytes.ToLower(b), []byte("<html")) {
			t.Fatalf("missing application page %s", path)
		}
	}
	untrusted := req("POST", "/api/research/projects", map[string]string{"name": "Rejected"})
	untrusted.Header.Del("X-Roundtable")
	do(untrusted, 403)
	createProject := func(name string) research.Project {
		return scienceWorkflowDecode[research.Project](t, do(req("POST", "/api/research/projects", map[string]string{"name": name}), 201))
	}
	a, b := createProject("Solar capture"), createProject("Literature review")
	pdf := scienceWorkflowPDF(quote)
	metadata := map[string]any{"title": "Evaporation reference", "project_ids": []string{a.ID, b.ID}, "core_project_ids": []string{a.ID}}
	paper := scienceWorkflowDecode[research.Paper](t, upload("/api/research/papers", "source.pdf", pdf, metadata))
	if paper.FileSHA256 != fmt.Sprintf("%x", sha256.Sum256(pdf)) {
		t.Fatal("paper digest differs from original")
	}
	paperURL := "/api/research/papers/" + paper.ID
	for _, proj := range []research.Project{a, b} {
		ps := scienceWorkflowDecode[[]research.Paper](t, do(req("GET", "/api/research/papers?project="+proj.ID, nil), 200))
		if len(ps) != 1 || ps[0].ID != paper.ID {
			t.Fatal("project association duplicated or lost", ps)
		}
	}
	if got := do(req("GET", paperURL+"/pdf", nil), 200); !bytes.Equal(got, pdf) {
		t.Fatal("library altered the PDF")
	}
	page := httptest.NewRecorder()
	api.ServeHTTP(page, req("GET", paperURL+"/pages/1", nil))
	if page.Code == 200 {
		var extracted struct{ Text string }
		if err := json.Unmarshal(page.Body.Bytes(), &extracted); err != nil || !strings.Contains(extracted.Text, quote) {
			t.Fatal("PDF source text mismatch", page.Body.String())
		}
	} else if page.Code != 422 || !strings.Contains(page.Body.String(), "PDFKit") {
		t.Fatal("unexpected renderer failure", page.Code, page.Body.String())
	}
	ref, _ := json.Marshal(map[string]any{"projectId": a.ID, "paperId": paper.ID, "page": 1, "title": paper.Title, "fingerprint": paper.FileSHA256, "annotationId": ""})
	excerpt := append([]byte("Sci-Station · 论文原文摘录 v1\n"), ref...)
	excerpt = append(excerpt, []byte("\n\n"+quote)...)
	material := scienceWorkflowDecode[meeting.Material](t, upload("/api/studio/materials", "paper-excerpt.txt", excerpt, nil))
	// The explicit test seat avoids a live Magpie account or catalog connection.
	created := scienceWorkflowDecode[meeting.Session](t, do(req("POST", "/api/studio/sessions", map[string]any{"topic": "Review the limitation", "project_id": a.ID, "seats": []string{"codex"}, "material_ids": []string{material.ID}}), 201))
	sessURL := "/api/studio/sessions/" + created.ID
	do(req("POST", sessURL+"/run", map[string]any{"target": "codex", "expected_round": 0, "allow_edits": false}), 202)
	var session meeting.Session
	for limit := time.Now().Add(4 * time.Second); time.Now().Before(limit); {
		session = scienceWorkflowDecode[meeting.Session](t, do(req("GET", sessURL, nil), 200))
		if session.Status == "ready" && len(session.Rounds) > 0 {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	if len(session.Rounds) != 1 || len(session.Rounds[0].Turns) != 1 || session.Rounds[0].Turns[0].Text != verdict || len(session.Materials) != 1 || !strings.Contains(session.Materials[0].Excerpt, quote) {
		t.Fatalf("review failed %+v", session)
	}
	base := "/api/research/projects/" + a.ID
	notes := base + "/notes"
	if pending := scienceWorkflowDecode[[]research.Note](t, do(req("GET", notes, nil), 200)); len(pending) != 0 {
		t.Fatal("session wrote an unreviewed note")
	}
	method := scienceWorkflowDecode[research.Note](t, do(req("POST", notes, map[string]string{"title": "Methods", "body": "Project assumptions."}), 201))
	reviewPath := sessURL + "/research-reviews"
	submit := func(operation, action, title, body string) research.MeetingReview {
		proposal := map[string]any{"projectRevision": a.Revision, "turnId": "round-1-codex", "action": action, "title": title, "body": body}
		return scienceWorkflowDecode[research.MeetingReview](t, do(req("POST", reviewPath, map[string]any{"decision": "propose", "operationId": operation, "projectId": a.ID, "proposal": proposal}), 201))
	}
	decide := func(v research.MeetingReview, decision string, status int) research.MeetingReview {
		return scienceWorkflowDecode[research.MeetingReview](t, do(req("POST", reviewPath, map[string]any{"decision": decision, "operationId": v.ID, "projectId": v.ProjectID, "revision": v.Revision}), status))
	}
	rejected := submit(strings.Repeat("1", 32), "create-note", "Discarded", "First draft")
	decide(rejected, "reject", 200)
	if len(scienceWorkflowDecode[[]research.Note](t, do(req("GET", notes, nil), 200))) != 1 {
		t.Fatal("rejection changed notes")
	}
	proposal := submit(strings.Repeat("2", 32), "create-note", "Reviewed result", verdict+" [[Methods]]")
	if err := engine.Shutdown(context.Background()); err != nil {
		t.Fatal(err)
	}
	api, engine = start()
	history := scienceWorkflowDecode[[]research.MeetingReview](t, do(req("GET", base+"/reviews", nil), 200))
	if len(history) != 2 || history[0].Status != "pending" || history[0].Body != proposal.Body || history[1].Status != "rejected" {
		t.Fatal("review queue was not restored", history)
	}
	pdfPath := filepath.Join(dir, "research", "library", "pdf", paper.ID+".pdf")
	if err := os.WriteFile(pdfPath, scienceWorkflowPDF("Changed original."), 0600); err != nil {
		t.Fatal(err)
	}
	decide(proposal, "accept", 409)
	if err := os.WriteFile(pdfPath, pdf, 0600); err != nil {
		t.Fatal(err)
	}
	// An external paper metadata edit can revoke the reviewed membership even
	// while this window is open. Recheck disk state before committing.
	paperFile := filepath.Join(dir, "research", "library", "records", paper.ID+".json")
	originalMeta, err := os.ReadFile(paperFile)
	if err != nil {
		t.Fatal(err)
	}
	var changed map[string]any
	if err = json.Unmarshal(originalMeta, &changed); err != nil {
		t.Fatal(err)
	}
	changed["project_ids"] = []string{b.ID}
	changed["core_project_ids"] = []string{}
	row, err := json.Marshal(changed)
	if err != nil {
		t.Fatal(err)
	}
	if err = os.WriteFile(paperFile, row, 0600); err != nil {
		t.Fatal(err)
	}
	decide(proposal, "accept", 409)
	decide(proposal, "accept", 409)
	if err = os.WriteFile(paperFile, originalMeta, 0600); err != nil {
		t.Fatal(err)
	}
	if err := engine.Shutdown(context.Background()); err != nil {
		t.Fatal(err)
	}
	api, engine = start()
	committed := decide(proposal, "accept", 200)
	retry := decide(proposal, "accept", 200)
	note := scienceWorkflowDecode[research.Note](t, do(req("GET", notes+"/"+committed.ResultID, nil), 200))
	if retry.ResultID != note.ID || len(note.Evidence) != 1 || note.Evidence[0].Quote != quote || !strings.Contains(note.Body, "fingerprint="+paper.FileSHA256) || !strings.Contains(note.Body, "#round-1-codex") {
		t.Fatal("duplicate writeback or missing source link", note)
	}
	taskProposal := submit(strings.Repeat("3", 32), "create-task", "Recheck the mass range", "Recheck conditions")
	taskDone := decide(taskProposal, "accept", 200)
	task := scienceWorkflowDecode[research.Task](t, do(req("GET", base+"/tasks/"+taskDone.ResultID, nil), 200))
	if len(task.Evidence) != 1 || task.Evidence[0].SourceHash != paper.FileSHA256 {
		t.Fatal("task source missing")
	}
	if err := engine.Shutdown(context.Background()); err != nil {
		t.Fatal(err)
	}
	api, engine = start()
	got := scienceWorkflowDecode[research.Note](t, do(req("GET", notes+"/"+note.ID, nil), 200))
	if !slices.Equal(got.Evidence, note.Evidence) || got.SourceMeetingID != session.ID {
		t.Fatal("lost provenance after restart", got)
	}
	type edge struct{ Source, Target, Kind string }
	graph := scienceWorkflowDecode[struct{ Edges []edge }](t, do(req("GET", base+"/graph", nil), 200))
	for _, target := range []edge{{note.ID, method.ID, "wikilink"}, {note.ID, paper.ID, "evidence"}, {task.ID, paper.ID, "reading"}} {
		if !slices.Contains(graph.Edges, target) {
			t.Fatalf("graph missing %+v", target)
		}
	}
	last := scienceWorkflowDecode[meeting.Session](t, do(req("GET", sessURL, nil), 200))
	if len(last.Rounds) != 1 || last.Materials[0].ID != material.ID {
		t.Fatal("meeting not retained")
	}
	do(req("GET", "/api/research/projects/"+b.ID+"/notes/"+note.ID, nil), 404)
	original := do(req("GET", paperURL+"/pdf", nil), 200)
	if !bytes.Equal(original, pdf) {
		t.Fatal("round trip changed original")
	}
}
