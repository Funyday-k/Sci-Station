package research

import (
	"bytes"
	"encoding/json"
	"fmt"
	"mime/multipart"
	"net/http/httptest"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"sync"
	"testing"
)

func callResearch(t *testing.T, s *Service, method, path string, body any, status int) []byte {
	t.Helper()
	data, err := json.Marshal(body)
	if err != nil {
		t.Fatal(err)
	}
	r := httptest.NewRequest(method, prefix+path, bytes.NewReader(data))
	w := httptest.NewRecorder()
	s.ServeHTTP(w, r)
	if w.Code != status {
		t.Fatalf("%s %s: status %d want %d: %s", method, path, w.Code, status, w.Body.String())
	}
	return w.Body.Bytes()
}
func decodeResearch[T any](t *testing.T, data []byte) T {
	t.Helper()
	var v T
	if err := json.Unmarshal(data, &v); err != nil {
		t.Fatal(err)
	}
	return v
}
func newResearch(t *testing.T, dir string) *Service {
	t.Helper()
	s, err := New(dir)
	if err != nil {
		t.Fatal(err)
	}
	return s
}
func createResearchProject(t *testing.T, s *Service, name string) Project {
	t.Helper()
	return decodeResearch[Project](t, callResearch(t, s, "POST", "/projects", map[string]string{"name": name}, 201))
}

func TestWorkspaceRoundtrip(t *testing.T) {
	dir := t.TempDir()
	s := newResearch(t, dir)
	a, b := createResearchProject(t, s, "A"), createResearchProject(t, s, "B")
	if info, err := os.Stat(a.Path); err != nil || !info.IsDir() {
		t.Fatal("managed path unavailable")
	}
	pa, pb := "/projects/"+a.ID, "/projects/"+b.ID
	n := decodeResearch[Note](t, callResearch(t, s, "POST", pa+"/notes", map[string]string{"title": "A claim", "body": "Read [[Methods#Scaling|method section]]."}, 201))
	m := decodeResearch[Note](t, callResearch(t, s, "POST", pa+"/notes", map[string]string{"title": "Methods", "body": "## Scaling"}, 201))
	back := decodeResearch[[]Note](t, callResearch(t, s, "GET", pa+"/notes/"+m.ID+"/backlinks", nil, 200))
	if len(back) != 1 || back[0].ID != n.ID {
		t.Fatalf("backlinks %#v", back)
	}
	changed := decodeResearch[Note](t, callResearch(t, s, "PATCH", pa+"/notes/"+n.ID, map[string]any{"body": "Reviewed", "revision": 1}, 200))
	if changed.Revision != 2 {
		t.Fatal(changed)
	}
	callResearch(t, s, "PATCH", pa+"/notes/"+n.ID, map[string]any{"body": "stale", "revision": 1}, 409)
	callResearch(t, s, "GET", pb+"/notes/"+n.ID, nil, 404)
	task := decodeResearch[Task](t, callResearch(t, s, "POST", pa+"/tasks", map[string]string{"title": "Verify", "dueDate": "2026-11-25"}, 201))
	callResearch(t, s, "PATCH", pa+"/tasks/"+task.ID, map[string]any{"revision": 1, "status": "done"}, 200)
	callResearch(t, s, "POST", pa+"/tasks", map[string]string{"title": "Bad", "dueDate": "2026-02-31"}, 400)
	callResearch(t, s, "PATCH", pa+"/files", map[string]string{"path": "brief.md", "text": "A result", "version": "missing"}, 200)
	callResearch(t, s, "PATCH", pa+"/files", map[string]string{"path": "brief.md", "text": "Stale", "version": "missing"}, 409)
	s = newResearch(t, dir)
	reopened := decodeResearch[Note](t, callResearch(t, s, "GET", pa+"/notes/"+n.ID, nil, 200))
	if reopened.Body != "Reviewed" {
		t.Fatal(reopened)
	}
	current, ok := s.Task(a.ID, task.ID)
	if !ok || current.Status != "done" {
		t.Fatalf("task lost: %+v", current)
	}
	callResearch(t, s, "DELETE", pa+"?revision=1", nil, 204)
	callResearch(t, s, "GET", pa+"/tasks", nil, 404)
	if _, err := os.Stat(filepath.Join(a.Path, "brief.md")); err != nil {
		t.Fatal("archiving project removed working file", err)
	}
}
func TestReviewedWritesIdempotentAndIsolated(t *testing.T) {
	s := newResearch(t, t.TempDir())
	project := createResearchProject(t, s, "Review")
	base := "/projects/" + project.ID + "/notes"
	body := []byte(`{"title":"Discussion","body":"Reviewed result","idempotencyKey":"meeting/one/report","sourceMeetingId":"one"}`)
	codes := make(chan int, 12)
	var wg sync.WaitGroup
	for range 12 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			r := httptest.NewRequest("POST", prefix+base, bytes.NewReader(body))
			w := httptest.NewRecorder()
			s.ServeHTTP(w, r)
			codes <- w.Code
		}()
	}
	wg.Wait()
	close(codes)
	created := 0
	for status := range codes {
		if status == 201 {
			created++
		} else if status != 200 {
			t.Fatalf("retry status %d", status)
		}
	}
	if created != 1 {
		t.Fatalf("created %d", created)
	}
	list := decodeResearch[[]Note](t, callResearch(t, s, "GET", base, nil, 200))
	if len(list) != 1 {
		t.Fatal(list)
	}
	callResearch(t, s, "DELETE", fmt.Sprintf("%s/%s?revision=1", base, list[0].ID), nil, 204)
	callResearch(t, s, "POST", base, map[string]string{"title": "Again", "idempotencyKey": "meeting/one/report"}, 410)
}
func TestResearchMaterialRange(t *testing.T) {
	s := newResearch(t, t.TempDir())
	p := createResearchProject(t, s, "Materials")
	base := "/projects/" + p.ID + "/materials"
	var b bytes.Buffer
	form := multipart.NewWriter(&b)
	part, err := form.CreateFormFile("file", "figure.txt")
	if err != nil {
		t.Fatal(err)
	}
	_, _ = part.Write([]byte("0123456789"))
	_ = form.Close()
	r := httptest.NewRequest("POST", prefix+base, &b)
	r.Header.Set("Content-Type", form.FormDataContentType())
	w := httptest.NewRecorder()
	s.ServeHTTP(w, r)
	if w.Code != 201 {
		t.Fatalf("upload %d %s", w.Code, w.Body.String())
	}
	m := decodeResearch[Material](t, w.Body.Bytes())
	r = httptest.NewRequest("GET", prefix+base+"/"+m.ID+"/content", nil)
	r.Header.Set("Range", "bytes=2-4")
	w = httptest.NewRecorder()
	s.ServeHTTP(w, r)
	if w.Code != 206 || w.Body.String() != "234" || !strings.Contains(w.Header().Get("Content-Disposition"), "inline") {
		t.Fatal(w.Code, w.Body.String(), w.Header())
	}
	callResearch(t, s, "DELETE", base+"/"+m.ID+"?revision=1", nil, 204)
	callResearch(t, s, "GET", base+"/"+m.ID+"/content", nil, 404)
}

func TestManualGraphAndArchiveRestore(t *testing.T) {
	dir := t.TempDir()
	s := newResearch(t, dir)
	p := createResearchProject(t, s, "Relations")
	base := "/projects/" + p.ID
	n := decodeResearch[Note](t, callResearch(t, s, "POST", base+"/notes", map[string]string{"title": "Claim", "body": "Reviewed"}, 201))
	task := decodeResearch[Task](t, callResearch(t, s, "POST", base+"/tasks", map[string]string{"title": "Experiment"}, 201))
	rels := base + "/graph/relations"
	input := map[string]string{"source": task.ID, "target": n.ID, "kind": "supports", "label": "Reproduction"}
	rel := decodeResearch[GraphRelation](t, callResearch(t, s, "POST", rels, input, 201))
	callResearch(t, s, "POST", rels, input, 200)
	callResearch(t, s, "POST", rels, map[string]string{"source": n.ID, "target": "other-project", "kind": "related"}, 400)
	callResearch(t, s, "DELETE", base+"?revision=1", nil, 204)
	s = newResearch(t, dir)
	archived := decodeResearch[[]Project](t, callResearch(t, s, "GET", "/projects?archived=1", nil, 200))
	if len(archived) != 1 || archived[0].Revision != 2 {
		t.Fatal(archived)
	}
	callResearch(t, s, "POST", base+"/restore", map[string]int{"revision": 1}, 409)
	callResearch(t, s, "POST", base+"/restore", map[string]int{"revision": 2}, 200)
	g := decodeResearch[struct{ Edges []graphEdge }](t, callResearch(t, s, "GET", base+"/graph", nil, 200))
	if len(g.Edges) != 1 || g.Edges[0].ID != rel.ID || g.Edges[0].Kind != "supports" || g.Edges[0].Revision != 1 {
		t.Fatal(g)
	}
	callResearch(t, s, "DELETE", rels+"/"+rel.ID+"?revision=1", nil, 204)
}

func TestGlobalCalendarFollowsProjectArchiveAndRestore(t *testing.T) {
	dir := t.TempDir()
	s := newResearch(t, dir)
	a, b := createResearchProject(t, s, "One"), createResearchProject(t, s, "Two")
	add := func(project Project, title, dueDate string) Task {
		return decodeResearch[Task](t, callResearch(t, s, "POST", "/projects/"+project.ID+"/tasks",
			map[string]string{"title": title, "dueDate": dueDate}, 201))
	}
	undated := add(a, "No date", "")
	later := add(a, "Later", "2027-02-01")
	early := add(b, "Early", "2027-01-01")
	check := func(want ...Task) {
		t.Helper()
		got := decodeResearch[[]Task](t, callResearch(t, s, "GET", "/tasks", nil, 200))
		if len(got) != len(want) {
			t.Fatalf("got %v, want %v", got, want)
		}
		for i, task := range want {
			if !reflect.DeepEqual(got[i], task) {
				t.Fatalf("item %d: got %v, want %v", i, got[i], task)
			}
		}
	}
	check(early, later, undated)
	callResearch(t, s, "DELETE", "/projects/"+b.ID+"?revision=1", nil, 204)
	s = newResearch(t, dir)
	check(later, undated)
	callResearch(t, s, "POST", "/projects/"+b.ID+"/restore", map[string]int{"revision": 2}, 200)
	check(early, later, undated)
}
