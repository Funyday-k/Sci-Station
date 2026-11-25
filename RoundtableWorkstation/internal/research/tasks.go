package research

import (
	"encoding/json"
	"errors"
	"maps"
	"net/http"
	"slices"
	"strings"
	"time"
)

type taskInput struct {
	Title              *string   `json:"title"`
	Description        *string   `json:"description"`
	Status             *string   `json:"status"`
	Kind               *string   `json:"kind"`
	Priority           *string   `json:"priority"`
	Tags               *[]string `json:"tags"`
	StartDate          *string   `json:"startDate"`
	DueDate            *string   `json:"dueDate"`
	DueTime            *string   `json:"dueTime"`
	ProjectIDs         *[]string `json:"projectIds"`
	PaperID            *string   `json:"paperId"`
	RelatedPaperIDs    *[]string `json:"relatedPaperIds"`
	ExternalSource     *string   `json:"externalSource"`
	ExternalIdentifier *string   `json:"externalIdentifier"`
	IdempotencyKey     string    `json:"idempotencyKey"`
	Revision           int       `json:"revision"`
}

type taskRecord Task

// Files from the first desktop prototype have one project, one optional paper,
// and the status "doing". Decode the additions in memory without a bulk rewrite.
func (t *Task) UnmarshalJSON(data []byte) error {
	var record taskRecord
	if err := json.Unmarshal(data, &record); err != nil {
		return err
	}
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(data, &fields); err != nil {
		return err
	}
	for _, key := range strings.Fields("id revision createdAt updatedAt projectId projectIds title description status kind priority tags startDate dueDate dueTime completedAt paperId relatedPaperIds externalSource externalIdentifier evidence") {
		delete(fields, key)
	}
	*t = Task(record)
	t.extra = fields
	if t.ProjectIDs == nil && t.ProjectID != "" {
		t.ProjectIDs = []string{t.ProjectID}
	}
	if t.RelatedPaperIDs == nil {
		t.RelatedPaperIDs = []string{}
		if t.PaperID != "" {
			t.RelatedPaperIDs = append(t.RelatedPaperIDs, t.PaperID)
		}
	}
	if t.Tags == nil {
		t.Tags = []string{}
	}
	if t.Kind == "" {
		t.Kind = "general"
	}
	if t.Priority == "" {
		t.Priority = "medium"
	}
	if t.Status == "doing" {
		t.Status = "inProgress"
	}
	return nil
}

func (t Task) MarshalJSON() ([]byte, error) {
	data, err := json.Marshal(taskRecord(t))
	if err != nil || len(t.extra) == 0 {
		return data, err
	}
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(data, &fields); err != nil {
		return nil, err
	}
	maps.Copy(fields, t.extra)
	return json.Marshal(fields)
}

func (s *Service) registerTasks() {
	s.mux.HandleFunc("GET "+prefix+"/tasks", s.workspaceTasks)
	base := prefix + "/projects/{project}/tasks"
	for _, m := range []string{"GET", "POST"} {
		s.mux.HandleFunc(m+" "+base, s.tasks)
	}
	for _, m := range []string{"GET", "PATCH", "DELETE"} {
		s.mux.HandleFunc(m+" "+base+"/{task}", s.tasks)
	}
}

func newTask(projectID string) Task {
	return Task{
		Entity: fresh(), ProjectID: projectID, ProjectIDs: []string{projectID},
		Kind: "general", Status: "open", Priority: "medium", Tags: []string{}, RelatedPaperIDs: []string{},
	}
}

var taskPriorities = []string{"urgent", "high", "medium", "low"}

func taskBefore(a, b Task) bool {
	if a.DueDate != b.DueDate {
		return b.DueDate == "" || (a.DueDate != "" && a.DueDate < b.DueDate)
	}
	if a.Priority != b.Priority {
		return slices.Index(taskPriorities, a.Priority) < slices.Index(taskPriorities, b.Priority)
	}
	if a.CreatedAt != b.CreatedAt {
		return a.CreatedAt < b.CreatedAt
	}
	return a.ID < b.ID
}

// Each task is committed only in its original project's file, even when that
// project is archived. Membership controls visibility and the mutation route.
func (s *Service) visibleTasksLocked(pid string) map[string]Task {
	out := make(map[string]Task)
	for _, owner := range s.projects {
		for _, t := range owner.Tasks {
			for _, member := range t.ProjectIDs {
				project, ok := s.projects[member]
				if !ok || project.Archived || (pid != "" && member != pid) {
					continue
				}
				t.ProjectID = member
				out[t.ID] = t
				break
			}
		}
	}
	return out
}

func (s *Service) findTaskLocked(pid, id string) (projectData, Task, bool) {
	for _, owner := range s.projects {
		if t, ok := owner.Tasks[id]; ok && slices.Contains(t.ProjectIDs, pid) {
			return owner, t, true
		}
	}
	return projectData{}, Task{}, false
}

func (s *Service) workspaceTasks(w http.ResponseWriter, _ *http.Request) {
	s.mu.RLock()
	out := s.visibleTasksLocked("")
	s.mu.RUnlock()
	jsonReply(w, 200, valuesBy(out, taskBefore))
}

func uniqueTaskValues(raw []string, limit int, valid func(string) bool) ([]string, bool) {
	if len(raw) > limit {
		return nil, false
	}
	out := []string{}
	seen := map[string]bool{}
	for _, v := range raw {
		v = strings.TrimSpace(v)
		if !valid(v) {
			return nil, false
		}
		if !seen[v] {
			out = append(out, v)
			seen[v] = true
		}
	}
	return out, true
}

func (s *Service) updateTaskLocked(t *Task, in taskInput) error {
	oldStatus := t.Status
	for _, pair := range []struct {
		input  *string
		target *string
	}{
		{in.Title, &t.Title}, {in.Description, &t.Description}, {in.Status, &t.Status}, {in.Kind, &t.Kind},
		{in.Priority, &t.Priority}, {in.StartDate, &t.StartDate}, {in.DueDate, &t.DueDate}, {in.DueTime, &t.DueTime},
		{in.ExternalSource, &t.ExternalSource}, {in.ExternalIdentifier, &t.ExternalIdentifier},
	} {
		if pair.input != nil {
			*pair.target = *pair.input
		}
	}
	t.Title = strings.TrimSpace(t.Title)
	if t.Status == "doing" {
		t.Status = "inProgress"
	}
	if !label(t.Title, 240) || len(t.Description) > 128<<10 {
		return errors.New("任务标题或说明无效")
	}
	if (t.ExternalSource != "" && !label(t.ExternalSource, 80)) ||
		(t.ExternalIdentifier != "" && !label(t.ExternalIdentifier, 256)) {
		return errors.New("任务来源无效")
	}
	if !slices.Contains([]string{"open", "inProgress", "done", "cancelled"}, t.Status) || !slices.Contains([]string{"general", "reading"}, t.Kind) || !slices.Contains(taskPriorities, t.Priority) {
		return errors.New("任务类型、状态或优先级无效")
	}
	for _, date := range []string{t.StartDate, t.DueDate} {
		if date != "" {
			if parsed, err := time.Parse(time.DateOnly, date); err != nil || parsed.Format(time.DateOnly) != date {
				return errors.New("日期无效")
			}
		}
	}
	if t.StartDate != "" && t.DueDate != "" && t.StartDate > t.DueDate {
		return errors.New("截止日期早于开始日期")
	}
	if t.DueTime != "" {
		parsed, err := time.Parse("15:04", t.DueTime)
		if t.DueDate == "" || err != nil || parsed.Format("15:04") != t.DueTime {
			return errors.New("截止时间需要有效的截止日期及时间")
		}
	}
	if in.Tags != nil {
		tags, ok := uniqueTaskValues(*in.Tags, 128, func(v string) bool { return label(v, 80) })
		if !ok {
			return errors.New("任务标签无效")
		}
		t.Tags = tags
	}
	if in.ProjectIDs != nil {
		ids, ok := uniqueTaskValues(*in.ProjectIDs, 256, validID)
		if !ok || len(ids) == 0 {
			return errors.New("至少需要一个有效项目")
		}
		active := false
		for _, id := range ids {
			project, exists := s.projects[id]
			if !exists || (project.Archived && !slices.Contains(t.ProjectIDs, id)) {
				return errors.New("无法关联此项目")
			}
			active = active || !project.Archived
		}
		if !active {
			return errors.New("至少需要一个启用的项目")
		}
		t.ProjectIDs = ids
	}
	if in.RelatedPaperIDs != nil {
		t.RelatedPaperIDs = *in.RelatedPaperIDs
		t.PaperID = ""
		if len(t.RelatedPaperIDs) != 0 {
			t.PaperID = t.RelatedPaperIDs[0]
		}
	}
	if oldStatus != t.Status {
		if t.Status == "done" {
			t.CompletedAt = now()
		} else {
			t.CompletedAt = ""
		}
	}
	return nil
}

// Check paper IDs before acquiring the service lock; the paper library can
// call into the project registry when it validates a paper's memberships.
func (s *Service) resolveTaskPapers(in *taskInput) bool {
	if in.RelatedPaperIDs == nil && in.PaperID == nil {
		return true
	}
	if in.RelatedPaperIDs == nil {
		ids := []string{}
		if *in.PaperID != "" {
			ids = append(ids, *in.PaperID)
		}
		in.RelatedPaperIDs = &ids
	}
	ids, ok := uniqueTaskValues(*in.RelatedPaperIDs, 256, validID)
	if !ok {
		return false
	}
	if in.PaperID != nil && *in.PaperID != "" && (len(ids) == 0 || ids[0] != *in.PaperID) {
		return false
	}
	for _, id := range ids {
		if _, ok := s.papers.Snapshot(id); !ok {
			return false
		}
	}
	in.RelatedPaperIDs = &ids
	return true
}

// Reading-queue retries reuse an existing reading task in the destination
// project, including a task already completed by the researcher.
func (s *Service) existingReadingTaskLocked(pid string, candidate Task, key string) (Task, bool) {
	if candidate.Kind != "reading" || candidate.PaperID == "" || key != "reading:"+candidate.PaperID {
		return Task{}, false
	}
	var oldest Task
	for _, task := range s.visibleTasksLocked(pid) {
		if task.Kind == "reading" && slices.Contains(task.RelatedPaperIDs, candidate.PaperID) &&
			(oldest.ID == "" || task.CreatedAt < oldest.CreatedAt || task.CreatedAt == oldest.CreatedAt && task.ID < oldest.ID) {
			oldest = task
		}
	}
	return oldest, oldest.ID != ""
}

func (s *Service) tasks(w http.ResponseWriter, r *http.Request) {
	pid, id := r.PathValue("project"), r.PathValue("task")
	if r.Method == "GET" || r.Method == "HEAD" {
		s.mu.RLock()
		defer s.mu.RUnlock()
		if _, ok := s.loadProject(w, pid); !ok {
			return
		}
		if id == "" {
			jsonReply(w, 200, valuesBy(s.visibleTasksLocked(pid), taskBefore))
			return
		}
		_, t, ok := s.findTaskLocked(pid, id)
		if found(w, ok) {
			t.ProjectID = pid
			jsonReply(w, 200, t)
		}
		return
	}
	var in taskInput
	if r.Method != "DELETE" {
		if !payload(w, r, &in) {
			return
		}
		if !validKey(in.IdempotencyKey) || !s.resolveTaskPapers(&in) {
			jsonFail(w, 400, "关联论文或请求标识无效")
			return
		}
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	d, ok := s.loadProject(w, pid)
	if !ok {
		return
	}
	if r.Method == "POST" {
		if existing, seen := d.TaskKeys[in.IdempotencyKey]; seen && in.IdempotencyKey != "" {
			_, t, ok := s.findTaskLocked(pid, existing)
			if !ok {
				jsonFail(w, 410, "该任务已移除")
				return
			}
			t.ProjectID = pid
			jsonReply(w, 200, t)
			return
		}
		t := newTask(pid)
		if err := s.updateTaskLocked(&t, in); err != nil {
			jsonFail(w, 400, err.Error())
			return
		}
		if !slices.Contains(t.ProjectIDs, pid) {
			jsonFail(w, 400, "新任务必须关联当前项目")
			return
		}
		if existing, ok := s.existingReadingTaskLocked(pid, t, in.IdempotencyKey); ok {
			d.TaskKeys = maps.Clone(d.TaskKeys)
			d.TaskKeys[in.IdempotencyKey] = existing.ID
			if s.save(w, d) {
				jsonReply(w, 200, existing)
			}
			return
		}
		d.Tasks = maps.Clone(d.Tasks)
		d.Tasks[t.ID] = t
		if in.IdempotencyKey != "" {
			d.TaskKeys = maps.Clone(d.TaskKeys)
			d.TaskKeys[in.IdempotencyKey] = t.ID
		}
		if s.save(w, d) {
			jsonReply(w, 201, t)
		}
		return
	}
	owner, t, ok := s.findTaskLocked(pid, id)
	if !found(w, ok) {
		return
	}
	if r.Method == "DELETE" {
		if !revisionOK(w, t.Revision, queryRevision(r.URL.Query())) {
			return
		}
		owner.Tasks = maps.Clone(owner.Tasks)
		delete(owner.Tasks, id)
		if s.save(w, owner) {
			w.WriteHeader(204)
		}
		return
	}
	if !revisionOK(w, t.Revision, in.Revision) {
		return
	}
	if err := s.updateTaskLocked(&t, in); err != nil {
		jsonFail(w, 400, err.Error())
		return
	}
	t.bump()
	owner.Tasks = maps.Clone(owner.Tasks)
	owner.Tasks[id] = t
	if s.save(w, owner) {
		for _, member := range t.ProjectIDs {
			if !s.projects[member].Archived {
				t.ProjectID = member
				break
			}
		}
		if slices.Contains(t.ProjectIDs, pid) {
			t.ProjectID = pid
		}
		jsonReply(w, 200, t)
	}
}
