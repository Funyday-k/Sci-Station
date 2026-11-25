package research

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"net/netip"
	"net/url"
	"os"
	"strconv"
	"strings"
	"testing"
)

func testPaperLib(t *testing.T) *PaperLibrary {
	t.Helper()
	s, e := NewPaperLibrary(t.TempDir())
	if e != nil {
		t.Fatal(e)
	}
	return s
}
func testPaperRequest(t *testing.T, s *PaperLibrary, method, path, body string) *httptest.ResponseRecorder {
	t.Helper()
	r := httptest.NewRequest(method, "/api/research/papers"+path, strings.NewReader(body))
	r.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	s.ServeHTTP(w, r)
	return w
}
func uploadTestPDF(t *testing.T, s *PaperLibrary, paper string, metadata string) Paper {
	t.Helper()
	b := new(bytes.Buffer)
	form := multipart.NewWriter(b)
	f, err := form.CreateFormFile("file", "sample.pdf")
	if err != nil {
		t.Fatal(err)
	}
	io.WriteString(f, paper)
	if err = form.WriteField("metadata", metadata); err != nil {
		t.Fatal(err)
	}
	form.Close()
	r := httptest.NewRequest("POST", "/api/research/papers", b)
	r.Header.Set("Content-Type", form.FormDataContentType())
	w := httptest.NewRecorder()
	s.ServeHTTP(w, r)
	if w.Code != 201 && w.Code != 200 {
		t.Fatalf("import %d: %s", w.Code, w.Body.String())
	}
	var rec Paper
	if e := json.Unmarshal(w.Body.Bytes(), &rec); e != nil {
		t.Fatal(e)
	}
	return rec
}
func TestPaperLibraryDurableSharedPDFNotesAndAnnotations(t *testing.T) {
	s := testPaperLib(t)
	s.SetProjectValidator(func(id string) bool { return id == "one" || id == "two" })
	const pdf = "%PDF-1.7\noriginal paper fixture\n%%EOF\n"
	p := uploadTestPDF(t, s, pdf, `{"title":"Solar Capture","authors":["Ada Jones"],"year":2026,"project_ids":["one"]}`)
	if !p.HasPDF || len(p.FileSHA256) != 64 || p.Revision != 1 || p.Citekey != "Jones2026Solar" {
		t.Fatalf("unexpected paper %+v", p)
	}
	again := uploadTestPDF(t, s, pdf, `{"title":"another name","core_project_ids":["two"]}`)
	if again.ID != p.ID || again.Revision != 2 || len(again.ProjectIDs) != 2 || !paperContains(again.CoreProjectIDs, "two") {
		t.Fatalf("unexpected duplicate %+v", again)
	}
	rangeRequest := httptest.NewRequest("GET", "/api/research/papers/"+p.ID+"/pdf", nil)
	rangeRequest.Header.Set("Range", "bytes=0-4")
	w := httptest.NewRecorder()
	s.ServeHTTP(w, rangeRequest)
	if w.Code != 206 || w.Body.String() != "%PDF-" {
		t.Fatalf("range=%d: %s", w.Code, w.Body.String())
	}
	a := testPaperRequest(t, s, "POST", "/"+p.ID+"/annotations", `{"kind":"highlight","page":1,"selected_text":"sample","rects":[{"x":0.1,"y":0.2,"width":0.4,"height":0.1}]}`)
	if a.Code != 201 {
		t.Fatalf("annotation: %d %s", a.Code, a.Body.String())
	}
	stale := testPaperRequest(t, s, "PUT", "/"+p.ID, `{"notes":"stale","revision":2}`)
	if stale.Code != 409 {
		t.Fatal(stale.Code)
	}
	good := testPaperRequest(t, s, "PUT", "/"+p.ID, `{"notes":"local note","revision":3}`)
	if good.Code != 200 {
		t.Fatal(good.Code, good.Body.String())
	}
	fresh, e := NewPaperLibrary(s.dir)
	if e != nil {
		t.Fatal(e)
	}
	stored, ok := fresh.Snapshot(p.ID)
	if !ok || stored.Notes != "local note" || len(stored.Annotations) != 1 || stored.FileSHA256 != p.FileSHA256 || len(stored.ProjectIDs) != 2 {
		t.Fatalf("reopen=%+v", stored)
	}
	path, e := fresh.PDFPath(p.ID)
	if e != nil {
		t.Fatal(e)
	}
	actual, e := os.ReadFile(path)
	if e != nil || string(actual) != pdf {
		t.Fatalf("pdf changed %v", e)
	}
	export := testPaperRequest(t, s, "GET", "/bibtex?project=two", "")
	if export.Code != 200 || !strings.Contains(export.Body.String(), "@misc{Jones2026Solar,") {
		t.Fatal(export.Body.String())
	}
	annotationURL := "/" + p.ID + "/annotations/" + stored.Annotations[0].ID
	for _, query := range []string{"", "?revision=no", "?revision=0", "?revision=1"} {
		for _, method := range []string{"PUT", "DELETE"} {
			payload := ""
			if method == "PUT" {
				payload = `{"page":1,"note":"competing edit"}`
			}
			if got := testPaperRequest(t, s, method, annotationURL+query, payload); got.Code != 409 {
				t.Fatalf("unguarded %s %s: %d", method, query, got.Code)
			}
		}
	}
	del := testPaperRequest(t, s, "DELETE", annotationURL+"?revision="+strconv.Itoa(stored.Revision), "")
	if del.Code != 204 {
		t.Fatal(del.Code)
	}
}
func TestPaperCitationGraphAndConflictPreservation(t *testing.T) {
	s := testPaperLib(t)
	one, _, e := s.create(PaperMetadata{Title: "Paper One", DOI: "10.1000/first", References: []string{"10.1000/next", "doi:10.1000/MISSING"}}, "", "")
	if e != nil {
		t.Fatal(e)
	}
	two, _, e := s.create(PaperMetadata{Title: "Paper Two", DOI: "10.1000/next"}, "", "")
	if e != nil {
		t.Fatal(e)
	}
	g := paperGraph(s.all())
	if len(g.Nodes) != 3 || len(g.Edges) != 2 {
		t.Fatal(g)
	}
	found := false
	for _, edge := range g.Edges {
		if edge.Source == one.ID && edge.Target == two.ID {
			found = true
		}
	}
	if !found {
		t.Fatal("citation not resolved", g)
	}
	paper2 := two.PaperMetadata
	paper2.Citekey = one.Citekey
	if _, e = s.update(two.ID, two.Revision, paper2); !errors.Is(e, errPaperExists) {
		t.Fatal(e)
	}
	if got, _ := s.Snapshot(two.ID); got.Citekey != two.Citekey {
		t.Fatal("state overwritten")
	}
	bad := testPaperRequest(t, s, "GET", "/../not-a-paper", "")
	if bad.Code != 404 {
		t.Fatal(bad.Code)
	}
}
func TestPaperUnsafeDownloadRejectedAndPredictableMetadata(t *testing.T) {
	for _, addr := range []string{"127.0.0.1", "::ffff:127.0.0.1", "10.0.0.2", "169.254.2.17", "64:ff9b::7f00:1", "fd00::1"} {
		if safePaperAddress(netip.MustParseAddr(addr)) {
			t.Fatal(addr)
		}
	}
	u, _ := url.Parse("https://a.example:22/paper.pdf")
	if validPaperFetchURL(u) {
		t.Fatal("accepted non-web port")
	}
	r := httptest.NewRequest(http.MethodPost, "/", nil)
	if _, err := fetchPaperURL(r.Context(), "file:///tmp/doc", "application/pdf"); err == nil {
		t.Fatal("accepted file URL")
	}
	s := testPaperLib(t)
	if _, _, e := s.stagePDF(strings.NewReader("not a PDF")); !errors.Is(e, errInvalidPaper) {
		t.Fatal(e)
	}
	q := testPaperRequest(t, s, "POST", "", `{"title":"Plain link","url":"https://example.org/paper","status":"reading"}`)
	if q.Code != 201 {
		t.Fatal(q.Body.String())
	}
}

type paperTestRoundTrip func(*http.Request) (*http.Response, error)

func (f paperTestRoundTrip) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }

func TestPaperOnlineProvidersPreserveSourceMetadata(t *testing.T) {
	original := paperHTTPClient
	defer func() { paperHTTPClient = original }()
	paperHTTPClient = &http.Client{Transport: paperTestRoundTrip(func(req *http.Request) (*http.Response, error) {
		var body string
		switch req.URL.Host {
		case "api.crossref.org":
			body = `{"message":{"title":["Solar Findings"],"author":[{"given":"A.","family":"Li"}],"issued":{"date-parts":[[2024,1,2]]},"link":[{"URL":"https://example.org/doc.pdf","content-type":"application/pdf"}],"reference":[{"DOI":"10.1234/source"}]}}`
		case "export.arxiv.org":
			if req.URL.Query().Get("sortBy") != "submittedDate" || req.URL.Query().Get("max_results") != "24" {
				t.Fatalf("unexpected search: %s", req.URL)
			}
			body = `<feed xmlns="http://www.w3.org/2005/Atom"><entry><id>http://arxiv.org/abs/2404.10066v1</id><published>2024-04-15T15:15:00Z</published><title>Additional results</title><summary>A summary</summary><author><name>A. Lee</name></author></entry></feed>`
		default:
			t.Fatalf("unexpected URL %s", req.URL)
		}
		return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(body)), Header: make(http.Header), Request: req}, nil
	})}
	p := paperImport{PaperMetadata: PaperMetadata{DOI: "doi:10.1234/abc"}}
	enrichPaper(context.Background(), &p)
	if p.Title != "Solar Findings" || p.DOI != "10.1234/abc" || p.Year != 2024 || p.PDFURL != "https://example.org/doc.pdf" || len(p.Authors) != 1 || len(p.References) != 1 {
		t.Fatalf("incomplete metadata %+v", p)
	}
	results, err := SearchArxiv(context.Background(), "cat:astro-ph.HE")
	if err != nil || len(results) != 1 || results[0].Arxiv != "2404.10066v1" || results[0].Year != 2024 || results[0].URL != "https://arxiv.org/abs/2404.10066v1" {
		t.Fatalf("%+v %v", results, err)
	}
}

func TestArchivedProjectMembershipAndDeletePrecondition(t *testing.T) {
	lib := testPaperLib(t)
	open := map[string]bool{"a": true, "b": true}
	lib.SetProjectValidator(func(id string) bool { return open[id] })
	paper, _, err := lib.create(PaperMetadata{Title: "Shared Paper", ProjectIDs: []string{"a", "b"}, CoreProjectIDs: []string{"b"}}, "", "")
	if err != nil {
		t.Fatal(err)
	}
	open["b"] = false
	ok := testPaperRequest(t, lib, "PUT", "/"+paper.ID, `{"title":"Updated","revision":1}`)
	if ok.Code != 200 {
		t.Fatalf("archived membership blocked edit: %d %s", ok.Code, ok.Body)
	}
	stored, _ := lib.Snapshot(paper.ID)
	if !paperContains(stored.CoreProjectIDs, "b") || !paperContains(stored.ProjectIDs, "b") {
		t.Fatal("archived link lost")
	}
	bad := testPaperRequest(t, lib, "PUT", "/"+paper.ID, `{"revision":2,"project_ids":["a","b","inactive"]}`)
	if bad.Code != 400 {
		t.Fatal("accepted inactive new membership:", bad.Code)
	}
	if _, _, err := lib.create(PaperMetadata{Title: "New", ProjectIDs: []string{"b"}}, "", ""); !errors.Is(err, errInvalidPaper) {
		t.Fatal(err)
	}
	for _, suffix := range []string{"", "?revision=0", "?revision=-1", "?revision=fake", "?revision=1"} {
		r := testPaperRequest(t, lib, "DELETE", "/"+paper.ID+suffix, "")
		if r.Code != 409 {
			t.Fatal(suffix, r.Code)
		}
		if _, exists := lib.Snapshot(paper.ID); !exists {
			t.Fatal("stale delete removed paper")
		}
	}
	if r := testPaperRequest(t, lib, "DELETE", "/"+paper.ID+"?revision=2", ""); r.Code != 204 {
		t.Fatal(r.Code)
	}
}
