package research

import (
	"net/http"
	"testing"
)

func TestDiscoveryGraphUsesRecordedCoreRelationships(t *testing.T) {
	s, err := New(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	project := decodeResearch[Project](t, callResearch(t, s, "POST", prefix+"/projects", map[string]string{"name": "Solar physics"}, 201))
	other := decodeResearch[Project](t, callResearch(t, s, "POST", prefix+"/projects", map[string]string{"name": "Detector calibration"}, 201))
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
	c := callResearch(t, s, "POST", prefix+"/projects/"+project.ID+"/graph/relations",
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
	selected, err := s.ImportDiscoveryCandidate(project.ID, found)
	if err != nil || selected.ID != cited.ID || len(selected.ProjectIDs) != 2 {
		t.Fatalf("cited local registration duplicated paper: %+v %v", selected, err)
	}
	selected, err = s.ImportDiscoveryCandidate(project.ID, manual)
	if err != nil || selected.ID != related.ID || selected.Notes != related.Notes {
		t.Fatalf("existing local registration modified metadata: %+v %v", selected, err)
	}
	if _, err := s.DiscoveryContext(project.ID, []string{"outside-this-scope"}); err == nil {
		t.Fatal("accepted a reference outside the project's library")
	}
}
