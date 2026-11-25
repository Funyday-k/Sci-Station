package research

import (
	"encoding/json"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
)

// These transaction tests use recorded, non-paper meeting outputs. The
// cross-service workflow independently exercises a real PDF and meeting.
func TestReviewDecisionTransactions(t *testing.T) {
	root := t.TempDir()
	s := newResearch(t, root)
	p := createResearchProject(t, s, "Study")
	other := createResearchProject(t, s, "Other study")
	pid := p.ID
	text := "Published meeting agenda"
	resolve := func(id string) (ReviewSource, error) { return ReviewSource{Text: text, Evidence: []Evidence{}}, nil }
	proposal := func(id, action string, target Note) ReviewRequest {
		var req ReviewRequest
		data, err := json.Marshal(map[string]any{"operationId": id, "decision": "propose", "projectId": pid, "proposal": map[string]any{
			"turnId": "agenda-one", "action": action, "title": "Finding", "body": "Discuss this result.", "destinationId": target.ID, "destinationRevision": target.Revision, "projectRevision": p.Revision,
		}})
		if err != nil {
			t.Fatal(err)
		}
		if err = json.Unmarshal(data, &req); err != nil {
			t.Fatal(err)
		}
		return req
	}
	exec := func(q ReviewRequest) *httptest.ResponseRecorder {
		r := httptest.NewRequest("POST", "/meeting/research-reviews", nil)
		w := httptest.NewRecorder()
		s.ServeMeetingReview(w, r, pid, "meeting-1", q, resolve)
		return w
	}
	expect := func(q ReviewRequest, status int) MeetingReview {
		t.Helper()
		w := exec(q)
		if w.Code != status {
			t.Fatalf("%s got %d want %d: %s", q.Decision, w.Code, status, w.Body.String())
		}
		var result MeetingReview
		if status < 300 {
			if err := json.Unmarshal(w.Body.Bytes(), &result); err != nil {
				t.Fatal(err)
			}
		}
		return result
	}
	decision := func(v MeetingReview, verb string) ReviewRequest {
		return ReviewRequest{ProjectID: pid, OperationID: v.ID, Decision: verb, Revision: v.Revision}
	}
	req := proposal(makeID(), "create-task", Note{})
	draft := expect(req, 201)
	expect(req, 200)
	req.Proposal.Body = "Changed replay"
	expect(req, 409)
	bad := decision(draft, "accept")
	bad.ProjectID = other.ID
	expect(bad, 403)
	text = "Changed meeting agenda"
	expect(decision(draft, "accept"), 409)
	if len(s.projects[pid].Tasks) != 0 || s.projects[pid].Reviews[draft.ID].Status != "pending" {
		t.Fatal("conflict mutated task or review")
	}
	expect(decision(draft, "reject"), 200)
	expect(decision(draft, "reject"), 200)
	expect(decision(draft, "accept"), 409)

	// A new reviewed operation can proceed. A failed replacement must leave
	// the pending review and destination as they were, including in memory.
	draft = expect(proposal(makeID(), "create-task", Note{}), 201)
	backup := filepath.Join(root, "saved-project.json")
	path := s.recordPath(pid)
	if err := os.Rename(path, backup); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(path, 0700); err != nil {
		t.Fatal(err)
	}
	failed := exec(decision(draft, "accept"))
	if failed.Code < 400 || len(s.projects[pid].Tasks) != 0 || s.projects[pid].Reviews[draft.ID].Status != "pending" {
		t.Fatal("failed write changed state", failed.Code)
	}
	if err := os.Remove(path); err != nil {
		t.Fatal(err)
	}
	if err := os.Rename(backup, path); err != nil {
		t.Fatal(err)
	}
	s = newResearch(t, root)
	var wg sync.WaitGroup
	responses := make(chan *httptest.ResponseRecorder, 8)
	for range 8 {
		wg.Add(1)
		go func() { defer wg.Done(); responses <- exec(decision(draft, "accept")) }()
	}
	wg.Wait()
	close(responses)
	for w := range responses {
		if w.Code != 200 {
			t.Fatal(w.Code, w.Body.String())
		}
	}
	s = newResearch(t, root)
	if len(s.projects[pid].Tasks) != 1 || len(s.projects[other.ID].Tasks) != 0 {
		t.Fatal("duplicate or redirected task")
	}
	committed := expect(decision(draft, "accept"), 200)
	if _, ok := s.projects[pid].Tasks[committed.ResultID]; !ok || committed.Revision != 2 {
		t.Fatal("lost receipt")
	}

	route := "/projects/" + pid + "/notes"
	n := decodeResearch[Note](t, callResearch(t, s, "POST", route, map[string]string{"title": "Finding", "body": "Existing text"}, 201))
	stale := expect(proposal(makeID(), "append-note", n), 201)
	n = decodeResearch[Note](t, callResearch(t, s, "PATCH", route+"/"+n.ID, map[string]any{"revision": n.Revision, "body": "Concurrent edit"}, 200))
	expect(decision(stale, "accept"), 409)
	if s.projects[pid].Notes[n.ID].Body != "Concurrent edit" {
		t.Fatal("stale action overwrote note")
	}
	fresh := expect(proposal(makeID(), "append-note", n), 201)
	expect(decision(fresh, "accept"), 200)
	expect(decision(fresh, "accept"), 200)
	s = newResearch(t, root)
	if got := s.projects[pid].Notes[n.ID]; got.Revision != 3 || !strings.HasPrefix(got.Body, "Concurrent edit\n\nDiscuss this result.") || strings.Count(got.Body, "Discuss this result.") != 1 {
		t.Fatal("append lost original or replayed", got)
	}

	draft = expect(proposal(makeID(), "create-task", Note{}), 201)
	callResearch(t, s, "PATCH", "/projects/"+pid, map[string]any{"name": "New name", "revision": p.Revision}, 200)
	expect(decision(draft, "accept"), 409)
	if got := s.projects[pid].Reviews[draft.ID]; got.Status != "pending" {
		t.Fatal("stale project committed", got)
	}
}
