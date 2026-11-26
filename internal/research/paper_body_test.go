package research

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"mime/multipart"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

func uploadMarkdownFixture(t *testing.T, s *Service, p Paper, raw string, status int) []byte {
	t.Helper()
	var body bytes.Buffer
	form := multipart.NewWriter(&body)
	if err := form.WriteField("revision", strconv.Itoa(p.Revision)); err != nil {
		t.Fatal(err)
	}
	part, err := form.CreateFormFile("file", "original.md")
	if err != nil {
		t.Fatal(err)
	}
	if _, err = part.Write([]byte(raw)); err != nil {
		t.Fatal(err)
	}
	if err = form.Close(); err != nil {
		t.Fatal(err)
	}
	r := httptest.NewRequest("POST", prefix+"/papers/"+p.ID+"/body", &body)
	r.Header.Set("Content-Type", form.FormDataContentType())
	w := httptest.NewRecorder()
	s.ServeHTTP(w, r)
	if w.Code != status {
		t.Fatalf("%d want %d: %s", w.Code, status, w.Body.String())
	}
	return w.Body.Bytes()
}

func TestPaperMarkdownBodyRevisionSectionsAndSafeRecovery(t *testing.T) {
	root := t.TempDir()
	s := newResearch(t, root)
	proj, other := createResearchProject(t, s, "Markdown Project"), createResearchProject(t, s, "Foreign project")
	p, _, err := s.papers.create(PaperMetadata{Title: "Text-only paper", Abstract: "An abstract alone.", Notes: "Personal notes only.", ProjectIDs: []string{proj.ID}}, "", "")
	if err != nil {
		t.Fatal(err)
	}
	route := "/papers/" + p.ID + "/body"
	missing := callResearch(t, s, "GET", route, nil, 404)
	if !bytes.Contains(missing, []byte(`"state":"missing"`)) {
		t.Fatal(string(missing))
	}
	loc := SourceLocation{Kind: "paper-markdown", ID: p.ID}
	if _, err = s.WorkflowSource(context.Background(), proj.ID, loc); err == nil {
		t.Fatal("metadata counted as research evidence")
	}
	for _, bad := range []string{"", "---\ntitle: Paper\n---\n# Methods", "## Abstract\nstatus: not_extracted\nPDF text has not been extracted yet.", "Title: Example\nAuthors: Someone", "# Paper Note\n- p1 is ready for an evidence-backed structured note."} {
		uploadMarkdownFixture(t, s, p, bad, 400)
	}
	original := "# Scope\r\n😀 Limitation.\r\n## Methods\r\nThe particles diffuse at fixed temperature.\r\n"
	updated := decodeResearch[Paper](t, uploadMarkdownFixture(t, s, p, original, 200))
	if updated.HasPDF || updated.Markdown == nil || updated.Markdown.Revision != 1 || updated.Markdown.Origin != "import" || updated.Markdown.Hash != fmt.Sprintf("%x", sha256.Sum256([]byte(original))) {
		t.Fatal(updated)
	}
	if got := callResearch(t, s, "GET", route, nil, 200); string(got) != original {
		t.Fatal("original bytes changed")
	}
	r := newResearch(t, root)
	page, err := r.WorkflowSourceAtLine(context.Background(), proj.ID, loc, 4)
	if err != nil || len(page.Sections) != 2 || page.Heading != "Methods" || page.Line != 4 || !strings.HasPrefix(page.Text, "The particles") || page.Revision != 1 {
		t.Fatal(page, err)
	}
	if _, err = r.WorkflowSource(context.Background(), other.ID, loc); err == nil {
		t.Fatal("foreign project access")
	}
	hits, err := r.FindWorkflowSource(context.Background(), proj.ID, loc, "FIXED")
	if err != nil || len(hits.Items) != 1 {
		t.Fatal(hits, err)
	}
	retry := decodeResearch[Paper](t, uploadMarkdownFixture(t, r, p, original, 200))
	if retry.Revision != updated.Revision {
		t.Fatal("retry duplicated body")
	}
	uploadMarkdownFixture(t, r, p, "A conflicting body.", 409)
	newBody := decodeResearch[Paper](t, uploadMarkdownFixture(t, r, updated, "## Updated\nA corrected source body.", 200))
	if newBody.Markdown.Revision != 2 {
		t.Fatal(newBody)
	}
	if err = os.WriteFile(r.papers.bodyPath(p.ID, newBody.Markdown.BlobID), []byte("Wrong bytes."), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err = r.WorkflowSource(context.Background(), proj.ID, loc); err == nil {
		t.Fatal("accepted changed bytes")
	}
	record := filepath.Join(r.papers.dir, "records", p.ID+".json")
	raw, err := os.ReadFile(record)
	if err != nil {
		t.Fatal(err)
	}
	var fields map[string]any
	if err = json.Unmarshal(raw, &fields); err != nil {
		t.Fatal(err)
	}
	fields["markdown_source"].(map[string]any)["version"] = 2
	raw, err = json.Marshal(fields)
	if err != nil {
		t.Fatal(err)
	}
	if err = os.WriteFile(record, raw, 0600); err != nil {
		t.Fatal(err)
	}
	future := newResearch(t, root)
	uploadMarkdownFixture(t, future, newBody, "Replacing a newer format.", 400)
}
