package research

import (
	"bytes"
	"errors"
	"io"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func providerFixture(t *testing.T, lookup func(*http.Request) (*http.Response, error)) {
	t.Helper()
	original := paperHTTPClient
	t.Cleanup(func() { paperHTTPClient = original })
	paperHTTPClient = &http.Client{Transport: paperTestRoundTrip(lookup)}
}

func providerResponse(req *http.Request, contents string) (*http.Response, error) {
	return &http.Response{
		StatusCode: http.StatusOK,
		Body:       io.NopCloser(strings.NewReader(contents)),
		Header:     http.Header{},
		Request:    req,
	}, nil
}

func TestPaperImportPreviewAndOfflineFallback(t *testing.T) {
	calls := 0
	providerFixture(t, func(req *http.Request) (*http.Response, error) {
		calls++
		if req.URL.Host != "api.crossref.org" || req.URL.EscapedPath() != "/works/10.1000%2Fcase" {
			t.Fatalf("unexpected provider request %s", req.URL)
		}
		return nil, errors.New("fixture offline")
	})
	lib := testPaperLib(t)
	res := testPaperRequest(t, lib, "POST", "/preview", `{"identifier":"http://dx.doi.org/10.1000/Case","fetch_pdf":true}`)
	preview := decodeResearch[paperImportPreview](t, res.Body.Bytes())
	if res.Code != http.StatusOK || preview.DOI != "10.1000/case" || preview.MetadataWarning == "" || preview.URL != "https://doi.org/10.1000/case" ||
		preview.MetadataSource != "" || len(lib.all()) != 0 || calls != 1 {
		t.Fatalf("preview=%+v status=%d calls=%d", preview, res.Code, calls)
	}
	res = testPaperRequest(t, lib, "POST", "", `{"identifier":"DOI:10.1000/case","skip_metadata_lookup":true,"metadata_source":"Crossref"}`)
	record := decodeResearch[Paper](t, res.Body.Bytes())
	if res.Code != http.StatusCreated || record.HasPDF || record.MetadataSource != "" || calls != 1 || strings.Contains(res.Body.String(), "warning") {
		t.Fatalf("offline import %d after %d requests: %s", res.Code, calls, res.Body)
	}
	res = testPaperRequest(t, lib, "POST", "/preview", `{"identifier":"not a published identifier"}`)
	if res.Code != http.StatusBadRequest || len(lib.all()) != 1 || calls != 1 {
		t.Fatalf("unsupported input: %d %s", res.Code, res.Body)
	}
}

func TestInspireAndArxivImportShareAnOwnedRecord(t *testing.T) {
	var requests []string
	providerFixture(t, func(req *http.Request) (*http.Response, error) {
		requests = append(requests, req.URL.Host)
		if req.URL.Host == "inspirehep.net" && req.URL.Path == "/api/literature/2811054" {
			return providerResponse(req, `{"metadata":{"control_number":2811054,"titles":[{"title":"Sample Solar Paper"}],"abstracts":[{"value":"A sample &amp; a result."}],"authors":[{"full_name":"Jane Li"}],"arxiv_eprints":[{"value":"2404.12345v2","categories":["hep-ph"]}],"dois":[{"value":"10.1000/Solar"}],"publication_info":[{"year":2024,"journal_title":"Fixture Physics","journal_volume":"D12","journal_issue":3,"page_start":5,"page_end":19}],"inspire_categories":[{"term":"Phenomenology"}]}}`)
		}
		t.Fatalf("unexpected provider request %s", req.URL)
		return nil, nil
	})
	lib := testPaperLib(t)
	lib.SetProjectValidator(func(id string) bool { return id == "one" || id == "two" })
	payload := `{"identifier":"https://inspirehep.net/literature/2811054","project_ids":["one"],"project_links":{"one":{"is_pinned":true}}}`
	res := testPaperRequest(t, lib, "POST", "/preview", payload)
	metadata := decodeResearch[paperImportPreview](t, res.Body.Bytes())
	if res.Code != http.StatusOK || metadata.MetadataSource != "INSPIRE" || metadata.PDFURL != "https://arxiv.org/pdf/2404.12345v2" ||
		metadata.Arxiv != "2404.12345v2" || metadata.DOI != "10.1000/solar" || metadata.Abstract != "A sample & a result." ||
		strings.Join(metadata.Categories, ",") != "hep-ph,Phenomenology" || metadata.PublicationTitle != "Fixture Physics" ||
		metadata.Volume != "D12" || metadata.Issue != "3" || metadata.Pages != "5-19" || len(lib.all()) != 0 {
		t.Fatalf("preview=%+v response=%s", metadata, res.Body)
	}
	res = testPaperRequest(t, lib, "POST", "", payload)
	stored := decodeResearch[Paper](t, res.Body.Bytes())
	if res.Code != http.StatusCreated || stored.ID == "" || stored.InspireID != "2811054" {
		t.Fatalf("INSPIRE import: %d %s", res.Code, res.Body)
	}
	res = testPaperRequest(t, lib, "POST", "/preview", `{"identifier":"https://doi.org/10.48550/arXiv.2404.12345","skip_metadata_lookup":true}`)
	metadata = decodeResearch[paperImportPreview](t, res.Body.Bytes())
	if res.Code != http.StatusOK || metadata.ExistingPaperID != stored.ID || len(requests) != 2 {
		t.Fatalf("existing preview=%+v requests=%v", metadata, requests)
	}
	res = testPaperRequest(t, lib, "POST", "", `{"identifier":"http://arxiv.org/pdf/2404.12345v1.pdf","skip_metadata_lookup":true,"project_ids":["two"],"core_project_ids":["two"]}`)
	reused := decodeResearch[Paper](t, res.Body.Bytes())
	if res.Code != http.StatusOK || reused.ID != stored.ID || reused.Arxiv != stored.Arxiv || reused.Title != stored.Title ||
		len(reused.ProjectIDs) != 2 || len(reused.CoreProjectIDs) != 1 || !reused.ProjectLinks["one"].IsPinned || len(requests) != 2 {
		t.Fatalf("duplicate import: %d %+v", res.Code, reused)
	}
	reopened, err := NewPaperLibrary(lib.dir)
	if err != nil {
		t.Fatal(err)
	}
	paper, ok := reopened.Snapshot(stored.ID)
	if !ok || paper.InspireID != "2811054" || paper.PDFURL != metadata.PDFURL+"v2" || !paper.ProjectLinks["one"].IsPinned {
		t.Fatalf("reopened %+v", paper)
	}
}

func TestPaperImportArxivLookupRejectsWrongRevision(t *testing.T) {
	providerFixture(t, func(req *http.Request) (*http.Response, error) {
		if req.URL.Host != "export.arxiv.org" || req.URL.Query().Get("id_list") != "2404.12345v2" {
			t.Fatalf("unexpected provider request %s", req.URL)
		}
		return providerResponse(req, `<feed><entry><id>http://arxiv.org/abs/2404.12345v1</id><title>Wrong revision</title></entry></feed>`)
	})
	lib := testPaperLib(t)
	res := testPaperRequest(t, lib, "POST", "/preview", `{"identifier":"arxiv:2404.12345v2"}`)
	preview := decodeResearch[paperImportPreview](t, res.Body.Bytes())
	if res.Code != http.StatusOK || preview.Arxiv != "2404.12345v2" || preview.Title != "arXiv 2404.12345v2" ||
		preview.MetadataSource != "" || preview.MetadataWarning == "" || len(lib.all()) != 0 {
		t.Fatalf("mismatched preview %d: %+v", res.Code, preview)
	}
}

func paperPDFRequest(t *testing.T, lib *PaperLibrary, path, name string, pdf []byte) *httptest.ResponseRecorder {
	t.Helper()
	var reqBody bytes.Buffer
	form := multipart.NewWriter(&reqBody)
	f, err := form.CreateFormFile("file", name)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = f.Write(pdf); err != nil {
		t.Fatal(err)
	}
	if err := form.Close(); err != nil {
		t.Fatal(err)
	}
	req := httptest.NewRequest("POST", "/api/research/papers"+path, &reqBody)
	req.Header.Set("Content-Type", form.FormDataContentType())
	response := httptest.NewRecorder()
	lib.ServeHTTP(response, req)
	return response
}

func TestLocalPDFPreviewIsReadOnlyAndImportsOriginal(t *testing.T) {
	providerFixture(t, func(req *http.Request) (*http.Response, error) {
		t.Fatalf("unexpected request during local import %s", req.URL)
		return nil, nil
	})
	lib := testPaperLib(t)
	data, err := os.ReadFile(readerFixture(t))
	if err != nil {
		t.Fatal(err)
	}
	res := paperPDFRequest(t, lib, "/preview", "2404.12345v2.pdf", data)
	preview := decodeResearch[paperImportPreview](t, res.Body.Bytes())
	if res.Code != http.StatusOK || !preview.HasLocalPDF || preview.Arxiv != "2404.12345v2" || preview.Title != "2404.12345v2" || len(lib.all()) != 0 {
		t.Fatalf("read-only preview %d %+v", res.Code, preview)
	}
	pdfs, err := os.ReadDir(filepath.Join(lib.dir, "pdf"))
	if err != nil || len(pdfs) != 0 {
		t.Fatalf("staged PDFs after preview: %v %v", pdfs, err)
	}
	res = paperPDFRequest(t, lib, "", "2404.12345v2.pdf", data)
	stored := decodeResearch[Paper](t, res.Body.Bytes())
	if res.Code != http.StatusCreated || !stored.HasPDF || stored.MetadataSource != "PDF" {
		t.Fatalf("local import %d %+v", res.Code, stored)
	}
	path, err := lib.PDFPath(stored.ID)
	if err != nil {
		t.Fatal(err)
	}
	output, err := os.ReadFile(path)
	if err != nil || !bytes.Equal(data, output) {
		t.Fatalf("imported PDF changed: %v", err)
	}
}

func TestStalePDFAttachmentPreservesCommittedOriginal(t *testing.T) {
	lib := testPaperLib(t)
	p, _, err := lib.create(PaperMetadata{Title: "Original"}, "", "")
	if err != nil {
		t.Fatal(err)
	}
	stale, err := NewPaperLibrary(lib.dir)
	if err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(readerFixture(t))
	if err != nil {
		t.Fatal(err)
	}
	path := "/" + p.ID + "/pdf"
	if res := paperPDFRequest(t, lib, path, "original.pdf", data); res.Code != http.StatusOK {
		t.Fatalf("attach: %d %s", res.Code, res.Body)
	}
	changed := append(bytes.Clone(data), '\n')
	if res := paperPDFRequest(t, stale, path, "different.pdf", changed); res.Code != http.StatusConflict {
		t.Fatalf("stale attachment: %d %s", res.Code, res.Body)
	}
	committed := filepath.Join(lib.dir, "pdf", p.ID+".pdf")
	pdf, err := os.ReadFile(committed)
	if err != nil || !bytes.Equal(pdf, data) {
		t.Fatalf("committed PDF lost after conflict: %v", err)
	}
}

func TestPaperImportRetryFillsProviderDataWithoutOverwritingEdits(t *testing.T) {
	offline := true
	providerFixture(t, func(req *http.Request) (*http.Response, error) {
		if offline {
			return nil, errors.New("provider fixture unavailable")
		}
		return providerResponse(req, `{"message":{"DOI":"10.1000/example","title":["Catalogue Title"],"author":[{"family":"Zhang"}],"issued":{"date-parts":[[2025]]},"type":"journal-article","container-title":["Cosmology Journal"],"publisher":"Fixture Press","volume":"42","issue":"7","page":"13--18","subject":["Astronomy"]}}`)
	})
	lib := testPaperLib(t)
	const request = `{"identifier":"doi:10.1000/example"}`
	res := testPaperRequest(t, lib, "POST", "", request)
	p := decodeResearch[Paper](t, res.Body.Bytes())
	if res.Code != http.StatusCreated || p.Title != "10.1000/example" || !strings.Contains(res.Body.String(), "metadata_warning") {
		t.Fatalf("offline save: %d %s", res.Code, res.Body)
	}
	res = testPaperRequest(t, lib, "PATCH", "/"+p.ID, `{"revision":1,"title":"My title","notes":"Reading notes"}`)
	if res.Code != http.StatusOK {
		t.Fatalf("edit: %d %s", res.Code, res.Body)
	}
	offline = false
	res = testPaperRequest(t, lib, "POST", "", request)
	got := decodeResearch[Paper](t, res.Body.Bytes())
	if res.Code != http.StatusOK || got.ID != p.ID || got.MetadataSource != "Crossref" || got.Year != 2025 ||
		len(got.Authors) != 1 || len(got.Categories) != 1 || got.ItemType != "journal-article" ||
		got.PublicationTitle != "Cosmology Journal" || got.Publisher != "Fixture Press" || got.Volume != "42" ||
		got.Issue != "7" || got.Pages != "13--18" || got.Title != "My title" || got.Notes != "Reading notes" || got.Revision != 3 {
		t.Fatalf("recovered paper: %d %+v", res.Code, got)
	}
	res = testPaperRequest(t, lib, "GET", "/"+p.ID+"/bibtex", "")
	if res.Code != http.StatusOK || !strings.Contains(res.Body.String(), "journal = {Cosmology Journal}") ||
		!strings.Contains(res.Body.String(), "title = {My title}") {
		t.Fatalf("bibliography from recovered metadata: %d %s", res.Code, res.Body)
	}
}

func TestPDFImportKeepsExactArxivRevisionOnLinkRecord(t *testing.T) {
	lib := testPaperLib(t)
	res := testPaperRequest(t, lib, "POST", "", `{"identifier":"arXiv:2404.12345v1","skip_metadata_lookup":true}`)
	stored := decodeResearch[Paper](t, res.Body.Bytes())
	if res.Code != http.StatusCreated || stored.Arxiv != "2404.12345v1" || stored.HasPDF {
		t.Fatalf("link record %d %+v", res.Code, stored)
	}
	pdf, err := os.ReadFile(readerFixture(t))
	if err != nil {
		t.Fatal(err)
	}
	res = paperPDFRequest(t, lib, "", "2404.12345v2.pdf", pdf)
	if res.Code != http.StatusConflict {
		t.Fatalf("different arXiv version %d %s", res.Code, res.Body)
	}
	res = paperPDFRequest(t, lib, "", "2404.12345v1.pdf", pdf)
	record := decodeResearch[Paper](t, res.Body.Bytes())
	if res.Code != http.StatusOK || !record.HasPDF || record.ID != stored.ID || record.Arxiv != stored.Arxiv {
		t.Fatalf("matching revision %d %+v", res.Code, record)
	}
}

func TestPDFImportRollsBackAssetWhenRecordCannotPublish(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("fixture requires a non-root process to enforce directory permissions")
	}
	lib := testPaperLib(t)
	records := filepath.Join(lib.dir, "records")
	if err := os.Chmod(records, 0500); err != nil {
		t.Fatal(err)
	}
	defer os.Chmod(records, 0700)
	data, err := os.ReadFile(readerFixture(t))
	if err != nil {
		t.Fatal(err)
	}
	res := paperPDFRequest(t, lib, "", "sample.pdf", data)
	if res.Code != http.StatusInternalServerError || len(lib.all()) != 0 {
		t.Fatalf("failed commit status %d %s", res.Code, res.Body)
	}
	pdfs, err := os.ReadDir(filepath.Join(lib.dir, "pdf"))
	if err != nil || len(pdfs) != 0 {
		t.Fatalf("PDFs after failed record write: %v %v", pdfs, err)
	}
	if err := os.Chmod(records, 0700); err != nil {
		t.Fatal(err)
	}
	res = paperPDFRequest(t, lib, "", "sample.pdf", data)
	if res.Code != http.StatusCreated || len(lib.all()) != 1 || !lib.all()[0].HasPDF {
		t.Fatalf("retry after failed publish %d %s", res.Code, res.Body)
	}
}
