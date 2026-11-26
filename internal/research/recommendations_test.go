package research

import (
	"bytes"
	"context"
	"io"
	"net/http"
	"os"
	"testing"
)

func TestDiscoveryGraphUsesRecordedCoreRelationships(t *testing.T) {
	s, err := New(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	project := decodeResearch[Project](t, callResearch(t, s, "POST", "/projects", map[string]string{"name": "Solar physics"}, 201))
	other := decodeResearch[Project](t, callResearch(t, s, "POST", "/projects", map[string]string{"name": "Detector calibration"}, 201))
	create := func(metadata PaperMetadata) Paper {
		t.Helper()
		paper, _, err := s.papers.create(metadata, "", "")
		if err != nil {
			t.Fatal(err)
		}
		return paper
	}
	cited := create(PaperMetadata{Title: "Cited paper", Arxiv: "2404.01000v2", ProjectIDs: []string{other.ID}})
	related := create(PaperMetadata{Title: "Recorded relation", ProjectIDs: []string{project.ID}, Notes: "Keep these notes"})
	core := create(PaperMetadata{
		Title: "Core study", ProjectIDs: []string{project.ID}, CoreProjectIDs: []string{project.ID},
		References: []string{"arXiv:2404.01000v1", "10.1234/NON-LIBRARY", "unresolved label"},
	})
	_ = create(PaperMetadata{Title: "Other project core", ProjectIDs: []string{other.ID}, CoreProjectIDs: []string{other.ID}, References: []string{"10.1234/OTHER"}})
	_ = create(PaperMetadata{Title: "Non-core", ProjectIDs: []string{project.ID}, References: []string{"10.1234/NON-CORE"}})
	c := callResearch(t, s, "POST", "/projects/"+project.ID+"/graph/relations",
		map[string]string{"source": related.ID, "target": core.ID, "kind": "related"}, http.StatusCreated)
	relation := decodeResearch[GraphRelation](t, c)
	input, err := s.DiscoveryContext(project.ID, []string{core.ID})
	if err != nil || len(input.Graph) != 3 || len(input.Refs) != 1 {
		t.Fatalf("unexpected scoped graph: %+v, %v", input, err)
	}
	byKey := map[string]DiscoveryCandidate{}
	for _, candidate := range input.Graph {
		byKey[candidate.Key()] = candidate
	}
	found := byKey["2404.01000"]
	if found.PaperID != cited.ID || len(found.GraphEvidence) != 1 || found.GraphEvidence[0].Reference != "arXiv:2404.01000v1" {
		t.Fatalf("citation lost its real locator: %+v", found)
	}
	manual := byKey["paper:"+related.ID]
	if len(manual.GraphEvidence) != 1 || manual.GraphEvidence[0].RelationID != relation.ID {
		t.Fatalf("relation lost its stable ID: %+v", manual)
	}
	external := byKey["doi:10.1234/non-library"]
	if external.Provider != "graph" || external.PaperID != "" || external.DOI == "" {
		t.Fatalf("unresolved DOI should carry only its citation metadata: %+v", external)
	}
	selected, err := s.ImportDiscoveryCandidate(context.Background(), project.ID, found, true)
	if err != nil || selected.ID != cited.ID || len(selected.ProjectIDs) != 2 {
		t.Fatalf("cited local registration duplicated paper: %+v %v", selected, err)
	}
	selected, err = s.ImportDiscoveryCandidate(context.Background(), project.ID, manual, false)
	if err != nil || selected.ID != related.ID || selected.Notes != related.Notes {
		t.Fatalf("existing local registration modified metadata: %+v %v", selected, err)
	}
	if _, err := s.DiscoveryContext(project.ID, []string{"outside-this-scope"}); err == nil {
		t.Fatal("accepted a reference outside the project's library")
	}
}

func TestDiscoveryDownloadPreservesIdentifierAndRetriesLinkOnly(t *testing.T) {
	s := newResearch(t, t.TempDir())
	project := createResearchProject(t, s, "Fixture")
	pdf, err := os.ReadFile(readerFixture(t))
	if err != nil {
		t.Fatal(err)
	}
	candidate := DiscoveryCandidate{PaperMetadata: PaperMetadata{
		Title: "arXiv entry", Arxiv: "2404.09724v3", URL: "https://arxiv.org/abs/2404.09724v3",
	}}
	var calls int
	prior := paperHTTPClient
	t.Cleanup(func() { paperHTTPClient = prior })
	paperHTTPClient = &http.Client{Transport: paperTestRoundTrip(func(req *http.Request) (*http.Response, error) {
		calls++
		if req.URL.String() != "https://arxiv.org/pdf/2404.09724v3" {
			t.Fatalf("download changed the arXiv version: %s", req.URL)
		}
		response := &http.Response{StatusCode: http.StatusOK, Body: io.NopCloser(bytes.NewReader(pdf)), Header: http.Header{}}
		response.Header.Set("Content-Type", "application/pdf")
		if calls == 1 {
			response.StatusCode = http.StatusServiceUnavailable
		}
		return response, nil
	})}
	first, err := s.ImportDiscoveryCandidate(context.Background(), project.ID, candidate, true)
	if err != nil || first.ID == "" || first.HasPDF || first.Warning == "" || first.URL != candidate.URL {
		t.Fatalf("failed source should retain its link and report warning: %+v %v", first, err)
	}
	retried, err := s.ImportDiscoveryCandidate(context.Background(), project.ID, candidate, true)
	if err != nil || retried.ID != first.ID || !retried.HasPDF || retried.FileSHA256 == "" || retried.Warning != "" {
		t.Fatalf("retry should attach to the same paper: %+v %v", retried, err)
	}
	reused, err := s.ImportDiscoveryCandidate(context.Background(), project.ID, candidate, true)
	if err != nil || reused.ID != first.ID || calls != 2 || reused.Revision != retried.Revision {
		t.Fatalf("existing PDF should avoid another download: %+v calls=%d %v", reused, calls, err)
	}
}
