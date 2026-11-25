package main

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"mime/multipart"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"

	"scistation.local/desktop/internal/meeting"
	"scistation.local/desktop/internal/research"
)

// Verify the bridge over the real app router, including the normal upload and
// meeting store. A local scholarly workflow must not require a live model.
func TestScientificMeetingEvidenceToReviewedNote(t *testing.T) {
	dir, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	lab, err := research.New(filepath.Join(dir, "research"))
	if err != nil {
		t.Fatal(err)
	}
	settings, err := openSettings(dir)
	if err != nil {
		t.Fatal(err)
	}
	meetings, err := meeting.New(filepath.Join(dir, "meetings"), func(context.Context, string, string, string, string) (string, error) {
		t.Error("recording evidence called a model")
		return "", nil
	}, func() meeting.Settings { return settings.get().Settings })
	if err != nil {
		t.Fatal(err)
	}
	api := (&apiServer{prefs: settings, meetings: meetings, research: lab}).serve(8765)
	do := func(method, path, contentType string, data io.Reader, dest any) {
		t.Helper()
		r := httptest.NewRequest(method, "http://127.0.0.1:8765"+path, data)
		r.Header.Set("X-Roundtable", "1")
		r.Header.Set("Content-Type", contentType)
		w := httptest.NewRecorder()
		api.ServeHTTP(w, r)
		if w.Code < 200 || w.Code >= 300 {
			t.Fatalf("%s %s = %d: %s", method, path, w.Code, w.Body.String())
		}
		if err := json.Unmarshal(w.Body.Bytes(), dest); err != nil {
			t.Fatal(err)
		}
	}
	js := func(method, path string, data, dest any) {
		t.Helper()
		p, e := json.Marshal(data)
		if e != nil {
			t.Fatal(e)
		}
		do(method, path, "application/json", bytes.NewReader(p), dest)
	}
	upload := func(path, name, data string, metadata any, dest any) {
		t.Helper()
		var b bytes.Buffer
		form := multipart.NewWriter(&b)
		if metadata != nil {
			p, e := json.Marshal(metadata)
			if e != nil {
				t.Fatal(e)
			}
			if e = form.WriteField("metadata", string(p)); e != nil {
				t.Fatal(e)
			}
		}
		part, e := form.CreateFormFile("file", name)
		if e != nil {
			t.Fatal(e)
		}
		if _, e = io.WriteString(part, data); e != nil {
			t.Fatal(e)
		}
		if e = form.Close(); e != nil {
			t.Fatal(e)
		}
		do("POST", path, form.FormDataContentType(), &b, dest)
	}
	var project research.Project
	js("POST", "/api/research/projects", map[string]any{"name": "Reference test"}, &project)
	var paper research.Paper
	upload("/api/research/papers", "one.pdf", string(scienceWorkflowPDF("An observed line.")), map[string]any{"title": "Source", "project_ids": []string{project.ID}}, &paper)
	if paper.FileSHA256 == "" {
		t.Fatal("missing PDF fingerprint")
	}
	locator := map[string]any{"projectId": project.ID, "paperId": paper.ID, "page": 1, "title": paper.Title, "fingerprint": paper.FileSHA256, "annotationId": ""}
	loc, _ := json.Marshal(locator)
	const quote = "An observed line."
	frozen := "Sci-Station · 论文原文摘录 v1\n" + string(loc) + "\n\n" + quote
	var mat meeting.Material
	upload("/api/studio/materials", "source.txt", frozen, nil, &mat)
	var s meeting.Session
	js("POST", "/api/studio/sessions", map[string]any{"project_id": project.ID, "topic": "Compare sources", "seats": []string{"codex"}, "material_ids": []string{mat.ID}}, &s)
	if len(s.Materials) != 1 || s.Materials[0].Excerpt != frozen || s.Project != project.Path {
		t.Fatalf("bad frozen evidence: %#v", s.Materials)
	}
	var notes []research.Note
	route := "/api/research/projects/" + project.ID + "/notes"
	js("GET", route, nil, &notes)
	if len(notes) != 0 {
		t.Fatal("opening meeting modified notes")
	}
	// A selected passage alone cannot impersonate an approved report. No
	// meeting output exists yet, and direct notes cannot mint its provenance.
	data, _ := json.Marshal(map[string]any{"title": "Unreviewed", "body": quote, "sourceMeetingId": s.ID, "sourceTurnId": "report"})
	req := httptest.NewRequest("POST", "http://127.0.0.1:8765"+route, bytes.NewReader(data))
	req.Header.Set("X-Roundtable", "1")
	req.Header.Set("Content-Type", "application/json")
	res := httptest.NewRecorder()
	api.ServeHTTP(res, req)
	if res.Code != 403 || !strings.Contains(res.Body.String(), "审核") {
		t.Fatalf("unreviewed write: %d %s", res.Code, res.Body.String())
	}
	js("GET", route, nil, &notes)
	if len(notes) != 0 {
		t.Fatal("review bypass created a record")
	}
}
