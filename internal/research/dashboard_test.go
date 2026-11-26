package research

import (
	"reflect"
	"testing"
)

func TestDashboardFactsFollowActiveProjectRecords(t *testing.T) {
	dir := t.TempDir()
	s := newResearch(t, dir)
	alpha := createResearchProject(t, s, "Alpha")
	beta := createResearchProject(t, s, "Beta")
	path := "/projects/" + alpha.ID
	callResearch(t, s, "POST", path+"/notes", map[string]any{
		"title": "Review gaps", "body": "Verified open question.", "tags": []string{"gap", "Research_Plan"},
	}, 201)
	callResearch(t, s, "POST", path+"/notes", map[string]any{
		"title": "Plan", "tags": []string{"research_plan", "related_work"},
	}, 201)
	callResearch(t, s, "DELETE", "/projects/"+beta.ID+"?revision=1", nil, 204)
	const dashboard = "/dashboard/projects"
	got := decodeResearch[map[string]dashboardProjectFacts](t, callResearch(t, newResearch(t, dir), "GET", dashboard, nil, 200))
	want := map[string]dashboardProjectFacts{alpha.ID: {NoteCount: 2, GapCount: 1, ArtifactKinds: []string{"related_work", "research_plan"}}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("dashboard facts = %+v, want %+v", got, want)
	}
}
