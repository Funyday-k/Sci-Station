package research

import (
	"fmt"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestProjectPaperImportAndLinkedWikiSaveComplete(t *testing.T) {
	dir := t.TempDir()
	s := newResearch(t, dir)
	project := createResearchProject(t, s, "Concurrent library and Wiki fixture")
	source := decodeResearch[Paper](t, callResearch(t, s, "POST", "/papers", map[string]any{
		"title": "Wiki source", "project_ids": []string{project.ID},
	}, 201))
	base := "/projects/" + project.ID + "/notes"
	const pairs = 12
	start := make(chan struct{})
	results := make(chan *httptest.ResponseRecorder, 2*pairs)
	send := func(path, body string) {
		r := httptest.NewRequest("POST", prefix+path, strings.NewReader(body))
		res := httptest.NewRecorder()
		<-start
		s.ServeHTTP(res, r)
		results <- res
	}
	for i := range pairs {
		go send("/papers", fmt.Sprintf(`{"title":"Imported fixture %d","project_ids":[%q]}`, i, project.ID))
		go send(base, fmt.Sprintf(`{"title":"Linked Wiki fixture %d","paperId":%q}`, i, source.ID))
	}
	close(start)
	deadline := time.After(4 * time.Second)
	for i := range 2 * pairs {
		select {
		case res := <-results:
			if res.Code != 201 {
				t.Fatalf("request failed: %d %s", res.Code, res.Body)
			}
		case <-deadline:
			t.Fatalf("only %d of %d imports and saves completed", i, 2*pairs)
		}
	}
	reopened := newResearch(t, dir)
	papers := reopened.papers.all()
	notes := decodeResearch[[]Note](t, callResearch(t, reopened, "GET", base, nil, 200))
	if len(papers) != pairs+1 || len(notes) != pairs {
		t.Fatalf("reopened with %d papers and %d notes", len(papers), len(notes))
	}
	for _, p := range papers {
		if len(p.ProjectIDs) != 1 || p.ProjectIDs[0] != project.ID {
			t.Fatalf("missing paper membership: %+v", p)
		}
	}
	for _, n := range notes {
		if n.PaperID != source.ID || n.ProjectID != project.ID {
			t.Fatalf("missing Wiki link: %+v", n)
		}
	}
}

func TestProjectArchiveSerializesWithPaperMembershipCommit(t *testing.T) {
	dir := t.TempDir()
	s := newResearch(t, dir)
	project := createResearchProject(t, s, "Archive during paper import fixture")
	base := "/projects/" + project.ID
	// Delay the actual paper record replacement, after membership validation.
	records, err := s.papers.lockRecords()
	if err != nil {
		t.Fatal(err)
	}
	release := sync.OnceFunc(func() { records.Close() })
	defer release()

	send := func(method, path, body string) <-chan *httptest.ResponseRecorder {
		result := make(chan *httptest.ResponseRecorder, 1)
		go func() {
			r := httptest.NewRequest(method, prefix+path, strings.NewReader(body))
			res := httptest.NewRecorder()
			s.ServeHTTP(res, r)
			result <- res
		}()
		return result
	}
	waitWriter := func(mu *sync.RWMutex) {
		t.Helper()
		for deadline := time.Now().Add(3 * time.Second); mu.TryRLock(); {
			mu.RUnlock()
			if time.Now().After(deadline) {
				t.Fatal("writer did not reach its commit")
			}
			time.Sleep(time.Millisecond)
		}
	}
	waitResult := func(result <-chan *httptest.ResponseRecorder, want int) []byte {
		t.Helper()
		select {
		case res := <-result:
			if res.Code != want {
				t.Fatalf("got status %d, want %d: %s", res.Code, want, res.Body)
			}
			return res.Body.Bytes()
		case <-time.After(3 * time.Second):
			t.Fatal("request did not finish")
			return nil
		}
	}
	imported := send("POST", "/papers", fmt.Sprintf(`{"title":"Before archive","url":"https://example.org/fixture","core_project_ids":[%q]}`, project.ID))
	waitWriter(&s.papers.mu)
	if s.mu.TryLock() {
		s.mu.Unlock()
		t.Fatal("project could change before validated membership was committed")
	}
	archive := send("DELETE", base+"?revision=1", "")
	waitWriter(&s.mu)
	release()
	paper := decodeResearch[Paper](t, waitResult(imported, 201))
	waitResult(archive, 204)

	s = newResearch(t, dir)
	updated := decodeResearch[Paper](t, callResearch(t, s, "PUT", "/papers/"+paper.ID, map[string]any{
		"revision": paper.Revision, "notes": "Existing memberships survive archival",
	}, 200))
	if !paperContains(updated.ProjectIDs, project.ID) || !paperContains(updated.CoreProjectIDs, project.ID) {
		t.Fatalf("archive lost existing memberships: %+v", updated)
	}
	retained := map[string]any{"title": updated.Title, "url": updated.URL, "project_ids": []string{project.ID}}
	preview := decodeResearch[paperImportPreview](t, callResearch(t, s, "POST", "/papers/preview", retained, 200))
	reimport := decodeResearch[Paper](t, callResearch(t, s, "POST", "/papers", retained, 200))
	if preview.ExistingPaperID != updated.ID || reimport.ID != updated.ID || reimport.Revision != updated.Revision {
		t.Fatalf("reimport failed to reuse archived membership: %+v, %+v", preview, reimport)
	}
	callResearch(t, s, "POST", "/papers", map[string]any{"title": "After archive", "project_ids": []string{project.ID}}, 400)
	if len(s.papers.all()) != 1 {
		t.Fatal("failed import left a paper record")
	}
}
