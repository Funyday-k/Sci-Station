package research

import (
	"bytes"
	"os"
	"slices"
	"testing"
)

func readTaskTags(t *testing.T, s *Service) taskTagCatalog {
	t.Helper()
	return decodeResearch[taskTagCatalog](t, callResearch(t, s, "GET", "/task-tags", nil, 200))
}

func editTaskTag(t *testing.T, s *Service, revision, status int, operation, name, color, textColor string) {
	t.Helper()
	callResearch(t, s, "PATCH", "/task-tags", map[string]any{
		"revision": revision, "operation": operation, "name": name, "color": color, "textColor": textColor,
	}, status)
}

func TestTaskTagCatalogRoundTripsWithoutRewritingAssignments(t *testing.T) {
	dir := t.TempDir()
	s := newResearch(t, dir)
	if catalog := readTaskTags(t, s); catalog.Revision != 0 || len(catalog.Tags) != 0 {
		t.Fatalf("fresh workspace tag catalog: %+v", catalog)
	}
	first := createResearchProject(t, s, "Task owner")
	second := createResearchProject(t, s, "Task member")
	firstTasks, secondTasks := "/projects/"+first.ID+"/tasks", "/projects/"+second.ID+"/tasks"
	names := []string{"reading, methods", "old free tag"}
	shared := decodeResearch[Task](t, callResearch(t, s, "POST", firstTasks, map[string]any{
		"title": "Inspect shared results", "projectIds": []string{first.ID, second.ID}, "tags": names,
	}, 201))
	unassigned := decodeResearch[Task](t, callResearch(t, s, "POST", "/tasks", map[string]any{
		"title": "Read the paper", "tags": []string{names[0]}, "idempotencyKey": "fixture-task",
	}, 201))
	ownerBefore, err := os.ReadFile(s.recordPath(first.ID))
	if err != nil {
		t.Fatal(err)
	}
	s = newResearch(t, dir) // Existing version 1 files have only string assignments and no catalog.
	inferred := readTaskTags(t, s)
	if inferred.Revision != 0 || !slices.EqualFunc(inferred.Tags, []string{names[1], names[0]}, func(tag taskTag, name string) bool {
		return tag.Name == name && tag.Definition == nil && tag.InUse
	}) {
		t.Fatalf("existing task tags were lost: %+v", inferred)
	}
	editTaskTag(t, s, 0, 200, "set", "  "+names[0]+"  ", "#f4a259", "#ffffff")
	editTaskTag(t, s, 1, 200, "set", "Unused", "#556677", "")
	editTaskTag(t, s, 2, 200, "set", names[0], "#112233", "#FEDCBA")
	editTaskTag(t, s, 2, 409, "delete", names[0], "", "")
	editTaskTag(t, s, 3, 400, "set", names[0], "#XYZ000", "")
	editTaskTag(t, s, 3, 400, "set", names[0], "#123456", "#1")
	callResearch(t, s, "PATCH", "/task-tags", map[string]any{"operation": "set", "name": "stale", "color": "#112233"}, 428)

	s = newResearch(t, dir)
	catalog := readTaskTags(t, s)
	if catalog.Revision != 3 || len(catalog.Tags) != 3 || catalog.Tags[0].Name != "Unused" || catalog.Tags[0].InUse ||
		catalog.Tags[0].Definition == nil || catalog.Tags[0].Definition.TextColor != "" ||
		catalog.Tags[2].Name != names[0] || !catalog.Tags[2].InUse || catalog.Tags[2].Definition == nil ||
		*catalog.Tags[2].Definition != (taskTagDefinition{Color: "#112233", TextColor: "#FEDCBA"}) {
		t.Fatalf("task definitions did not round-trip in sorted, deduplicated form: %+v", catalog)
	}
	if independent := readTaskTags(t, newResearch(t, t.TempDir())); len(independent.Tags) != 0 {
		t.Fatalf("tags crossed workspace boundaries: %+v", independent)
	}
	editTaskTag(t, s, 3, 200, "delete", names[0], "", "")
	editTaskTag(t, s, 4, 200, "delete", "Unused", "", "")
	editTaskTag(t, s, 5, 404, "delete", names[0], "", "")
	s = newResearch(t, dir)
	catalog = readTaskTags(t, s)
	if catalog.Revision != 5 || !slices.EqualFunc(catalog.Tags, inferred.Tags, func(got, want taskTag) bool { return got == want }) {
		t.Fatalf("deleted definitions must leave inferred tags: %+v", catalog)
	}
	ownerAfter, err := os.ReadFile(s.recordPath(first.ID))
	if err != nil || !bytes.Equal(ownerAfter, ownerBefore) {
		t.Fatal("catalog updates changed the project-owned task record", err)
	}
	member := decodeResearch[Task](t, callResearch(t, s, "GET", secondTasks+"/"+shared.ID, nil, 200))
	if member.ProjectID != second.ID || member.Revision != shared.Revision || !slices.Equal(member.Tags, names) {
		t.Fatalf("shared assignment was changed: %+v", member)
	}
	retry := decodeResearch[Task](t, callResearch(t, s, "POST", "/tasks", map[string]any{
		"title": "Read the paper", "idempotencyKey": "fixture-task",
	}, 200))
	if retry.ID != unassigned.ID || retry.Revision != unassigned.Revision || !slices.Equal(retry.Tags, unassigned.Tags) {
		t.Fatalf("unassigned task was changed: %+v", retry)
	}
}

func TestTaskTagWriteRecoveryAndUnknownFields(t *testing.T) {
	dir := t.TempDir()
	s := newResearch(t, dir)
	path := s.workspaceTaskPath()
	const fixture = `{"version":1,"tasks":{},"taskKeys":{},"future":["workspace"],"tagRevision":5,"tagDefinitions":{"review":{"color":"#ABCDEF","future":{"key":"keep"}}}}`
	if err := os.WriteFile(path, []byte(fixture), 0600); err != nil {
		t.Fatal(err)
	}
	editTaskTag(t, s, 0, 409, "set", "review", "#223344", "#CCDDEE")
	if catalog := readTaskTags(t, s); catalog.Revision != 0 || len(catalog.Tags) != 0 {
		t.Fatalf("external mutation changed the in-memory snapshot: %+v", catalog)
	}
	s = newResearch(t, dir)
	if err := os.Rename(path, path+".backup"); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(path, 0700); err != nil {
		t.Fatal(err)
	}
	editTaskTag(t, s, 5, 500, "set", "review", "#223344", "#CCDDEE")
	if catalog := readTaskTags(t, s); catalog.Revision != 5 || catalog.Tags[0].Definition.Color != "#ABCDEF" {
		t.Fatalf("failed write published a mutation: %+v", catalog)
	}
	if err := os.Remove(path); err != nil {
		t.Fatal(err)
	}
	if err := os.Rename(path+".backup", path); err != nil {
		t.Fatal(err)
	}
	editTaskTag(t, s, 5, 200, "set", "review", "#223344", "#CCDDEE")
	callResearch(t, s, "POST", "/tasks", map[string]any{"title": "Use review", "tags": []string{"review"}}, 201)
	data, err := os.ReadFile(path)
	if err != nil || !bytes.Contains(data, []byte(`"key":"keep"`)) || !bytes.Contains(data, []byte(`"future":["workspace"]`)) {
		t.Fatalf("saving tags and tasks lost unrelated data: %s %v", data, err)
	}
	bad := bytes.Replace(data, []byte(`#223344`), []byte(`#bad`), 1)
	if err := os.WriteFile(path, bad, 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := New(dir); err == nil {
		t.Fatal("accepted a malformed saved task tag definition")
	}
	if stored, err := os.ReadFile(path); err != nil || !bytes.Equal(stored, bad) {
		t.Fatal("malformed saved tag definition was changed on open", err)
	}
}
