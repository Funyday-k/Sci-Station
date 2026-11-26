package research

import (
	"bytes"
	"encoding/json"
	"net/http/httptest"
	"os"
	"path/filepath"
	"slices"
	"sync"
	"testing"
)

func taskTestPaper(t *testing.T, s *Service, title string) Paper {
	t.Helper()
	paper, _, err := s.papers.create(PaperMetadata{Title: title}, "", "")
	if err != nil {
		t.Fatal(err)
	}
	return paper
}

func TestUnassignedTasksAcrossWorkspaceAndProjectRoutes(t *testing.T) {
	dir := t.TempDir()
	s := newResearch(t, dir)
	input := map[string]any{"title": "Review notebook", "projectIds": []string{}, "idempotencyKey": "workspace-task",
		"dueDate": "2026-11-25", "dueTime": "00:05"}
	global := decodeResearch[Task](t, callResearch(t, s, "POST", "/tasks", input, 201))
	path := "/tasks/" + global.ID
	if global.ProjectID != "" || global.ProjectIDs == nil || len(global.ProjectIDs) != 0 || global.DueTime != "00:05" {
		t.Fatalf("incorrect initial global task: %+v", global)
	}
	if projects := decodeResearch[[]Project](t, callResearch(t, s, "GET", "/projects", nil, 200)); len(projects) != 0 {
		t.Fatal("global task created a project")
	}
	project := createResearchProject(t, s, "Associated project")
	base := "/projects/" + project.ID + "/tasks"
	callResearch(t, s, "GET", base+"/"+global.ID, nil, 404)
	callResearch(t, s, "PATCH", path, map[string]any{"revision": 1, "projectIds": []string{makeID()}}, 400)
	callResearch(t, s, "PATCH", path, map[string]any{"revision": 1, "projectIds": []string{project.ID}}, 200)
	if task, ok := s.Task(project.ID, global.ID); !ok || task.ProjectID != "" || task.ID != global.ID {
		t.Fatal("assignment changed the original reminder identity", task)
	}
	callResearch(t, s, "PATCH", base+"/"+global.ID, map[string]any{"revision": 2, "status": "done", "projectIds": []string{}}, 200)
	callResearch(t, s, "GET", base+"/"+global.ID, nil, 404)
	callResearch(t, s, "PATCH", path, map[string]any{"revision": 2, "status": "open"}, 409)
	unassigned := decodeResearch[Task](t, callResearch(t, s, "GET", path, nil, 200))
	if unassigned.Revision != 3 || unassigned.ProjectID != "" || len(unassigned.ProjectIDs) != 0 || unassigned.Status != "done" || unassigned.CompletedAt == "" {
		t.Fatal(unassigned)
	}

	original := decodeResearch[Task](t, callResearch(t, s, "POST", base, map[string]any{"title": "Originally a project task"}, 201))
	callResearch(t, s, "PATCH", "/tasks/"+original.ID, map[string]any{"revision": 1, "projectIds": []string{}}, 200)
	s = newResearch(t, dir)
	if retry := decodeResearch[Task](t, callResearch(t, s, "POST", "/tasks", input, 200)); retry.ID != global.ID || retry.Revision != 3 {
		t.Fatal("global retry did not reuse original task", retry)
	}
	if task, ok := s.Task("", original.ID); !ok || task.ProjectID != project.ID || task.ID != original.ID {
		t.Fatal("unassignment changed the legacy reminder identity", task)
	}
	if _, ok := s.Task(project.ID, original.ID); ok {
		t.Fatal("unassigned task can still be resolved through its original project")
	}
	globalList := decodeResearch[[]Task](t, callResearch(t, s, "GET", "/tasks", nil, 200))
	if len(globalList) != 2 || globalList[0].ID != global.ID || globalList[1].ID != original.ID || globalList[1].ProjectID != "" || len(globalList[1].ProjectIDs) != 0 {
		t.Fatal(globalList)
	}
	if projectList := decodeResearch[[]Task](t, callResearch(t, s, "GET", base, nil, 200)); len(projectList) != 0 {
		t.Fatal(projectList)
	}
	callResearch(t, s, "DELETE", path+"?revision=3", nil, 204)
	callResearch(t, newResearch(t, dir), "POST", "/tasks", input, 410)
}

func TestWorkspaceTaskFilePreservesExtensionsAndRejectsUnreadableState(t *testing.T) {
	dir := t.TempDir()
	s := newResearch(t, dir)
	task := decodeResearch[Task](t, callResearch(t, s, "POST", "/tasks", map[string]any{"title": "Task with extension"}, 201))
	path := s.workspaceTaskPath()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var record map[string]any
	if err := json.Unmarshal(data, &record); err != nil {
		t.Fatal(err)
	}
	record["futureSetting"] = map[string]any{"flags": []string{"keep workspace extension"}}
	record["tasks"].(map[string]any)[task.ID].(map[string]any)["futureField"] = map[string]any{"items": []string{"keep task extension"}}
	data, err = json.Marshal(record)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, data, 0600); err != nil {
		t.Fatal(err)
	}
	s = newResearch(t, dir)
	route := "/tasks/" + task.ID
	if err := os.Rename(path, path+".saved"); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(path, 0700); err != nil {
		t.Fatal(err)
	}
	callResearch(t, s, "PATCH", route, map[string]any{"revision": 1, "status": "done"}, 500)
	if unchanged := decodeResearch[Task](t, callResearch(t, s, "GET", route, nil, 200)); unchanged.Status != "open" || unchanged.Revision != 1 {
		t.Fatal("failed write changed the published task", unchanged)
	}
	if err := os.Remove(path); err != nil {
		t.Fatal(err)
	}
	if err := os.Rename(path+".saved", path); err != nil {
		t.Fatal(err)
	}
	callResearch(t, s, "PATCH", route, map[string]any{"revision": 1, "status": "done"}, 200)
	data, err = os.ReadFile(path)
	if err != nil || !bytes.Contains(data, []byte(`"keep workspace extension"`)) || !bytes.Contains(data, []byte(`"keep task extension"`)) {
		t.Fatalf("unknown fields did not round-trip: %s %v", data, err)
	}
	bad := bytes.Replace(data, []byte(`"version":1`), []byte(`"version":2`), 1)
	for _, fixture := range [][]byte{bad, []byte(`{"version":1`)} {
		if err := os.WriteFile(path, fixture, 0600); err != nil {
			t.Fatal(err)
		}
		if _, err := New(dir); err == nil {
			t.Fatal("opened an unsupported or malformed task file")
		}
		stored, err := os.ReadFile(path)
		if err != nil || !bytes.Equal(stored, fixture) {
			t.Fatal("invalid file was overwritten", err)
		}
	}
}

func TestSharedReadingTaskAndArchivedOwner(t *testing.T) {
	dir := t.TempDir()
	s := newResearch(t, dir)
	a := createResearchProject(t, s, "Owner")
	b := createResearchProject(t, s, "Member")
	c := createResearchProject(t, s, "Other")
	pa, pb, pc := "/projects/"+a.ID, "/projects/"+b.ID, "/projects/"+c.ID
	p1 := taskTestPaper(t, s, "Paper A")
	p2 := taskTestPaper(t, s, "Paper B")
	input := map[string]any{"title": "Compare two papers", "kind": "reading", "projectIds": []string{a.ID, b.ID},
		"relatedPaperIds": []string{p1.ID, p2.ID}, "priority": "urgent", "tags": []string{"lens", "lens", "curves"},
		"startDate": "2026-11-29", "dueDate": "2026-12-02", "dueTime": "16:30", "idempotencyKey": "reading/one"}
	task := decodeResearch[Task](t, callResearch(t, s, "POST", pa+"/tasks", input, 201))
	retry := decodeResearch[Task](t, callResearch(t, s, "POST", pa+"/tasks", input, 200))
	if task.ID != retry.ID || task.PaperID != p1.ID || task.Kind != "reading" || len(task.Tags) != 2 {
		t.Fatal(task, retry)
	}
	callResearch(t, s, "GET", pc+"/tasks/"+task.ID, nil, 404)
	callResearch(t, s, "PATCH", pc+"/tasks/"+task.ID, map[string]any{"revision": 1, "title": "Wrong project"}, 404)
	graph := decodeResearch[struct{ Edges []graphEdge }](t, callResearch(t, s, "GET", pb+"/graph", nil, 200))
	if len(graph.Edges) != 2 {
		t.Fatalf("missing reading edges: %+v", graph)
	}
	for _, project := range []string{a.ID, b.ID} {
		list := decodeResearch[[]Task](t, callResearch(t, s, "GET", "/projects/"+project+"/tasks", nil, 200))
		if len(list) != 1 || list[0].ID != task.ID || list[0].ProjectID != project {
			t.Fatal(list)
		}
	}
	callResearch(t, s, "DELETE", pa+"?revision=1", nil, 204)
	s = newResearch(t, dir)
	list := decodeResearch[[]Task](t, callResearch(t, s, "GET", "/tasks", nil, 200))
	if len(list) != 1 || list[0].ProjectID != b.ID || list[0].ID != task.ID {
		t.Fatal(list)
	}
	for _, patch := range []map[string]any{{"startDate": "2026-12-03"}, {"dueTime": "25:00"}, {"dueDate": ""}, {"priority": "unknown"}, {"projectIds": []string{a.ID}}, {"relatedPaperIds": []string{makeID()}}} {
		patch["revision"] = 1
		callResearch(t, s, "PATCH", pb+"/tasks/"+task.ID, patch, 400)
	}
	changed := decodeResearch[Task](t, callResearch(t, s, "PATCH", pb+"/tasks/"+task.ID, map[string]any{"revision": 1, "status": "cancelled"}, 200))
	if changed.Status != "cancelled" || changed.Revision != 2 || !slices.Equal(changed.ProjectIDs, []string{a.ID, b.ID}) || changed.DueTime != "16:30" || changed.Priority != "urgent" {
		t.Fatal(changed)
	}
	callResearch(t, s, "PATCH", pb+"/tasks/"+task.ID, map[string]any{"revision": 1, "status": "done"}, 409)
	callResearch(t, s, "POST", pa+"/restore", map[string]int{"revision": 2}, 200)
	callResearch(t, s, "PATCH", pb+"/tasks/"+task.ID, map[string]any{"revision": 2, "projectIds": []string{b.ID}}, 200)
	callResearch(t, s, "GET", pa+"/tasks/"+task.ID, nil, 404)
	callResearch(t, s, "POST", pa+"/tasks", input, 410)
	s = newResearch(t, dir)
	if _, ok := s.Task(a.ID, task.ID); ok {
		t.Fatal("removed membership remained accessible")
	}
	task, ok := s.Task(b.ID, task.ID)
	if !ok || task.ProjectID != a.ID {
		t.Fatal("lost stable reminder identity", task)
	}
	callResearch(t, s, "DELETE", pb+"/tasks/"+task.ID+"?revision=3", nil, 204)
	if list := decodeResearch[[]Task](t, callResearch(t, s, "GET", "/tasks", nil, 200)); len(list) != 0 {
		t.Fatal(list)
	}
}

func TestLegacyTaskPreservesFieldsAcrossFailureAndCompetingEdits(t *testing.T) {
	dir := t.TempDir()
	s := newResearch(t, dir)
	project := createResearchProject(t, s, "Prior")
	base := "/projects/" + project.ID + "/tasks"
	p := taskTestPaper(t, s, "Legacy reading")
	task := decodeResearch[Task](t, callResearch(t, s, "POST", base, map[string]any{"title": "Old task", "paperId": p.ID}, 201))
	path := s.recordPath(project.ID)
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var record map[string]any
	if err = json.Unmarshal(data, &record); err != nil {
		t.Fatal(err)
	}
	raw := record["tasks"].(map[string]any)[task.ID].(map[string]any)
	for _, key := range []string{"projectIds", "kind", "priority", "tags", "relatedPaperIds"} {
		delete(raw, key)
	}
	raw["status"] = "doing"
	raw["futureField"] = map[string]any{"items": []string{"preserve me"}}
	record["project"].(map[string]any)["futureProjectField"] = map[string]any{"items": []string{"preserve project extension"}}
	record["futureRootField"] = []string{"preserve project record extension"}
	data, err = json.Marshal(record)
	if err != nil {
		t.Fatal(err)
	}
	if err = os.WriteFile(path, data, 0600); err != nil {
		t.Fatal(err)
	}
	s = newResearch(t, dir)
	item := decodeResearch[Task](t, callResearch(t, s, "GET", base+"/"+task.ID, nil, 200))
	if item.Status != "inProgress" || item.Kind != "general" || item.Priority != "medium" || !slices.Equal(item.RelatedPaperIDs, []string{p.ID}) || !slices.Equal(item.ProjectIDs, []string{project.ID}) {
		t.Fatal(item)
	}
	check, err := os.ReadFile(path)
	if err != nil || !bytes.Equal(data, check) {
		t.Fatal("opening older data rewrote it", err)
	}
	records := filepath.Dir(path)
	if err = os.Rename(records, records+"-offline"); err != nil {
		t.Fatal(err)
	}
	callResearch(t, s, "PATCH", base+"/"+task.ID, map[string]any{"revision": 1, "status": "done"}, 500)
	if got, _ := s.Task(project.ID, task.ID); got.Revision != 1 || got.Status != "inProgress" {
		t.Fatal("failed write published", got)
	}
	if err = os.Rename(records+"-offline", records); err != nil {
		t.Fatal(err)
	}
	results := make(chan int, 2)
	var wg sync.WaitGroup
	for range 2 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			req := httptest.NewRequest("PATCH", prefix+base+"/"+task.ID, bytes.NewBufferString(`{"revision":1,"status":"done"}`))
			w := httptest.NewRecorder()
			s.ServeHTTP(w, req)
			results <- w.Code
		}()
	}
	wg.Wait()
	close(results)
	codes := map[int]int{}
	for code := range results {
		codes[code]++
	}
	if codes[200] != 1 || codes[409] != 1 {
		t.Fatal(codes)
	}
	s = newResearch(t, dir)
	item, ok := s.Task(project.ID, task.ID)
	if !ok || item.Status != "done" || item.CompletedAt == "" || item.Revision != 2 || !bytes.Contains(item.extra["futureField"], []byte("preserve me")) {
		t.Fatal(item)
	}
	check, err = os.ReadFile(path)
	if err != nil || !bytes.Contains(check, []byte(`"preserve project extension"`)) || !bytes.Contains(check, []byte(`"preserve project record extension"`)) {
		t.Fatal("task edit dropped unrelated project record fields", err)
	}
}

func TestReadingQueueReusesExistingSharedTaskAndPreservesProvenance(t *testing.T) {
	dir := t.TempDir()
	s := newResearch(t, dir)
	a := createResearchProject(t, s, "First")
	b := createResearchProject(t, s, "Second")
	first, second := "/projects/"+a.ID+"/tasks", "/projects/"+b.ID+"/tasks"
	paper := taskTestPaper(t, s, "Queue paper")
	task := decodeResearch[Task](t, callResearch(t, s, "POST", first, map[string]any{
		"title": "Read this paper", "kind": "reading", "status": "done",
		"relatedPaperIds": []string{paper.ID}, "projectIds": []string{a.ID, b.ID},
	}, 201))
	input := map[string]any{
		"title": "Suggested reading", "kind": "reading", "relatedPaperIds": []string{paper.ID},
		"idempotencyKey": "reading:" + paper.ID, "externalSource": "sci_station_recommendation",
		"externalIdentifier": "2401.01234",
	}
	for range 2 {
		same := decodeResearch[Task](t, callResearch(t, s, "POST", second, input, 200))
		if same.ID != task.ID || same.ProjectID != b.ID || same.Status != "done" || same.Title != task.Title {
			t.Fatal(same)
		}
		s = newResearch(t, dir)
	}
	another := taskTestPaper(t, s, "Another queue paper")
	input["relatedPaperIds"] = []string{another.ID}
	input["idempotencyKey"] = "reading:" + another.ID
	created := decodeResearch[Task](t, callResearch(t, s, "POST", second, input, 201))
	s = newResearch(t, dir)
	actual, ok := s.Task(b.ID, created.ID)
	if !ok || actual.ExternalSource != "sci_station_recommendation" || actual.ExternalIdentifier != "2401.01234" {
		t.Fatal(actual)
	}
}
