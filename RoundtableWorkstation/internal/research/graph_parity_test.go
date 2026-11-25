package research

import (
	"bytes"
	"crypto/sha256"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestGraphDirectedPathsAndWorkflowReadingOrder(t *testing.T) {
	s := newResearch(t, t.TempDir())
	p := createResearchProject(t, s, "Directed")
	q := createResearchProject(t, s, "Independent")
	paper := func(title, doi string, references ...string) Paper {
		t.Helper()
		return decodeResearch[Paper](t, callResearch(t, s, "POST", "/papers", PaperMetadata{
			Title: title, DOI: doi, ProjectIDs: []string{p.ID}, References: references,
		}, 201))
	}
	foundation := paper("Foundation", "10.1000/foundation")
	method := paper("Method", "10.1000/method", "10.1000/foundation")
	followup := paper("Follow-up", "10.1000/followup", "10.1000/method")
	path := "/projects/" + p.ID + "/graph"
	pathBetween := func(a, b, direction string) graphResult {
		params := url.Values{"focus": {a}, "target": {b}, "direction": {direction}, "kind": {"cites"}}
		return decodeResearch[graphResult](t, callResearch(t, s, "GET", path+"?"+params.Encode(), nil, 200))
	}
	back := pathBetween(followup.ID, foundation.ID, "outgoing")
	if back.Path == nil || !back.Path.Found || len(back.Edges) != 2 {
		t.Fatalf("could not find cited ancestors: %+v", back)
	}
	forwards := pathBetween(foundation.ID, followup.ID, "incoming")
	if forwards.Path == nil || !forwards.Path.Found || forwards.Edges[0].Source != method.ID {
		t.Fatalf("could not find later citing works: %+v", forwards)
	}
	if wrong := pathBetween(foundation.ID, followup.ID, "outgoing"); wrong.Path == nil || wrong.Path.Found {
		t.Fatalf("direction was ignored: %+v", wrong)
	}
	callResearch(t, s, "GET", path+"?direction=invalid", nil, 400)
	params := url.Values{"operation": {"reading"}, "focus": {followup.ID}, "depth": {"3"}}
	previewURL := path + "/workflow?" + params.Encode()
	before, err := os.ReadFile(s.recordPath(p.ID))
	if err != nil {
		t.Fatal(err)
	}
	preview := decodeResearch[graphWorkflowPreview](t, callResearch(t, s, "GET", previewURL, nil, 200))
	if preview.Kind != "project-graph" || preview.ProjectID != p.ID || preview.URI != prefix+previewURL ||
		preview.SHA256 != fmt.Sprintf("%x", sha256.Sum256([]byte(preview.Excerpt))) ||
		!strings.Contains(preview.Excerpt, "1. Foundation") || !strings.Contains(preview.Excerpt, "2. Method") ||
		!strings.Contains(preview.Excerpt, "3. Follow-up") {
		t.Fatalf("unexpected grounded reading order: %+v", preview)
	}
	callResearch(t, s, "GET", "/projects/"+q.ID+"/graph/workflow?"+params.Encode(), nil, 404)
	after, err := os.ReadFile(s.recordPath(p.ID))
	if err != nil || !bytes.Equal(before, after) {
		t.Fatal("workflow read modified source records", err)
	}
}

func TestGraphTitleMatchesPreserveAmbiguityAndIdentifierPriority(t *testing.T) {
	s := newResearch(t, t.TempDir())
	p := createResearchProject(t, s, "Titles")
	paper := func(title, doi, author string, refs ...string) Paper {
		t.Helper()
		return decodeResearch[Paper](t, callResearch(t, s, "POST", "/papers", PaperMetadata{
			Title: title, DOI: doi, Authors: []string{author}, Year: 2024, ProjectIDs: []string{p.ID}, References: refs,
		}, 201))
	}
	a := paper("Dark Matter Capture: Solar Study A", "10.1000/exact", "Jane Smith")
	b := paper("Dark Matter Capture: Solar Study B", "", "Ada Jones")
	note := paper("Review", "", "C. Lee",
		"Smith, Jane. “Dark Matter Captur: Solar Study A”. 2024.",
		"Dark Matter Capture Solar Study C",
		"Jones, Ada. \"Dark Matter Capture Solar Study B\". 2024.",
		"\"Dark Matter Capture: Solar Study B\" doi:10.1000/exact")
	graph := "/projects/" + p.ID + "/graph"
	g := decodeResearch[graphResult](t, callResearch(t, s, "GET", graph, nil, 200))
	possible := findGraphEdge(t, g.Edges, note.ID, a.ID, "possible-cites")
	if len(possible.Occurrences) != 1 || possible.Occurrences[0].Matches[0].Distance != 1 {
		t.Fatalf("near match lost uncertainty: %+v", possible)
	}
	exact := findGraphEdge(t, g.Edges, note.ID, a.ID, "cites")
	if len(exact.Occurrences) != 1 || exact.Occurrences[0].Ordinal != 4 {
		t.Fatalf("DOI did not win over contradictory title: %+v", exact)
	}
	byTitle := findGraphEdge(t, g.Edges, note.ID, b.ID, "cites")
	if byTitle.Occurrences[0].Resolution != "normalized-title" {
		t.Fatalf("normalized exact title did not retain provenance: %+v", byTitle)
	}
	foundAmbiguous := false
	for _, edge := range g.Edges {
		for _, occ := range edge.Occurrences {
			if occ.Resolution == "ambiguous-title" && len(occ.Matches) == 2 && strings.HasPrefix(edge.Target, "reference:") {
				foundAmbiguous = true
			}
		}
	}
	if !foundAmbiguous {
		t.Fatalf("tied candidates were lost or silently resolved: %+v", g)
	}
}

func TestInspireGraphMultiSeedCacheAndLocalFallback(t *testing.T) {
	s := newResearch(t, t.TempDir())
	p := createResearchProject(t, s, "INSPIRE")
	q := createResearchProject(t, s, "Independent")
	paper := func(project Project, title, id string, refs ...string) Paper {
		t.Helper()
		return decodeResearch[Paper](t, callResearch(t, s, "POST", "/papers", PaperMetadata{
			Title: title, InspireID: id, ProjectIDs: []string{project.ID}, References: refs,
		}, 201))
	}
	seed := paper(p, "Local seed", "111", "Local method")
	method := paper(p, "Local method", "")
	other := paper(q, "Private other seed", "112")
	offline := false
	calls := 0
	providerFixture(t, func(req *http.Request) (*http.Response, error) {
		calls++
		if req.URL.Host != "inspirehep.net" {
			t.Fatalf("unexpected provider host: %s", req.URL)
		}
		if offline {
			return nil, errors.New("provider unavailable")
		}
		switch req.URL.Path {
		case "/api/literature/111":
			return providerResponse(req, `{"metadata":{"control_number":111,"titles":[{"title":"Online seed"}],"references":[{"record":{"$ref":"https://inspirehep.net/api/literature/333"},"reference":{"title":{"title":"A provider citation"}}},{"record":{"$ref":"https://inspirehep.net/api/literature/333"}}]}}`)
		case "/api/literature/222":
			return providerResponse(req, `{"metadata":{"control_number":222,"titles":[{"title":"Independent seed"}]}}`)
		case "/api/literature":
			switch req.URL.Query().Get("q") {
			case "recid:333":
				return providerResponse(req, `{"hits":{"hits":[{"metadata":{"control_number":333,"titles":[{"title":"Reference paper"}],"citation_count":23}}]}}`)
			case "refersto:recid:111":
				return providerResponse(req, `{"hits":{"hits":[{"metadata":{"control_number":444,"titles":[{"title":"Later citing work"}]}}]}}`)
			case "refersto:recid:222":
				return providerResponse(req, `{"hits":{"hits":[]}}`)
			}
		}
		t.Fatalf("unexpected provider request: %s", req.URL)
		return nil, nil
	})
	path := "/projects/" + p.ID + "/graph/citations?"
	query := url.Values{"seed": {seed.ID, "inspire:222"}}
	read := func(online bool) []inspireSeedResult {
		t.Helper()
		if online {
			query.Set("online", "1")
		} else {
			query.Del("online")
		}
		return decodeResearch[[]inspireSeedResult](t, callResearch(t, s, "GET", path+query.Encode(), nil, 200))
	}
	fresh := read(true)
	if len(fresh) != 2 || fresh[0].Source != "inspire" || fresh[1].Source != "inspire" ||
		len(fresh[0].Inspire.References) != 2 || fresh[0].Inspire.References[1].Ordinal != 2 ||
		fresh[0].Inspire.References[1].Paper.Title != "Reference paper" || fresh[0].Inspire.CitedBy[0].Paper.ID != "444" ||
		fresh[1].Inspire.Paper.ID != "222" || calls != 5 {
		t.Fatalf("unexpected provider graph: %+v after %d calls", fresh, calls)
	}
	findGraphEdge(t, fresh[0].Local.Edges, seed.ID, method.ID, "cites")
	callResearch(t, s, "GET", path+"seed="+other.ID+"&online=1", nil, 404)
	if calls != 5 {
		t.Fatal("foreign scoped seed generated a provider call")
	}
	offline = true
	s = newResearch(t, s.dir)
	if cached := read(false); cached[0].Source != "cache" || cached[1].Inspire.Paper.ID != "222" || calls != 5 {
		t.Fatalf("offline restart did not recover cache: %+v after %d calls", cached, calls)
	}
	if fallback := read(true); fallback[0].Source != "cache" || fallback[0].Warning == "" {
		t.Fatalf("provider failure did not retain a useful cache: %+v", fallback)
	}
	cache := filepath.Join(s.dir, inspireCacheName("inspire:111"))
	if err := os.WriteFile(cache, []byte(`{"version":99}`), 0600); err != nil {
		t.Fatal(err)
	}
	if fallback := read(false); fallback[0].Source != "local" || fallback[0].Inspire != nil || fallback[1].Source != "cache" {
		t.Fatalf("a damaged seed cache affected valid local or other seed records: %+v", fallback)
	}
	offline = false
	if repaired := read(true); repaired[0].Source != "inspire" || repaired[0].Inspire.Paper.ID != "111" {
		t.Fatalf("refresh could not reconstruct the cache: %+v", repaired)
	}
	if repaired := read(false); repaired[0].Source != "cache" {
		t.Fatalf("repaired cache was not saved: %+v", repaired)
	}
}
