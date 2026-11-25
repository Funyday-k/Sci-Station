package research

import (
	"maps"
	"net/http"
	"sort"
	"strings"
	"time"
)

type taskInput struct {
	Title          *string `json:"title"`
	Description    *string `json:"description"`
	Status         *string `json:"status"`
	DueDate        *string `json:"dueDate"`
	PaperID        *string `json:"paperId"`
	IdempotencyKey string  `json:"idempotencyKey"`
	Revision       int     `json:"revision"`
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
func taskBefore(a, b Task) bool {
	if a.DueDate != b.DueDate {
		return b.DueDate == "" || (a.DueDate != "" && a.DueDate < b.DueDate)
	}
	if a.CreatedAt != b.CreatedAt {
		return a.CreatedAt < b.CreatedAt
	}
	return a.ID < b.ID
}

// The global calendar projects active projects' tasks without duplicating their records.
func (s *Service) workspaceTasks(w http.ResponseWriter, _ *http.Request) {
	out := []Task{}
	s.mu.RLock()
	for _, project := range s.projects {
		if project.Archived {
			continue
		}
		for _, task := range project.Tasks {
			out = append(out, task)
		}
	}
	s.mu.RUnlock()
	sort.Slice(out, func(i, j int) bool { return taskBefore(out[i], out[j]) })
	jsonReply(w, http.StatusOK, out)
}

func updateTask(t *Task, in taskInput) bool {
	if in.Title != nil {
		t.Title = strings.TrimSpace(*in.Title)
	}
	if in.Description != nil {
		t.Description = *in.Description
	}
	if in.Status != nil {
		t.Status = *in.Status
	}
	if in.DueDate != nil {
		t.DueDate = *in.DueDate
	}
	if in.PaperID != nil {
		t.PaperID = *in.PaperID
	}
	if !label(t.Title, 240) || len(t.Description) > 128<<10 || (t.Status != "open" && t.Status != "doing" && t.Status != "done") {
		return false
	}
	if t.DueDate != "" {
		if _, err := time.Parse(time.DateOnly, t.DueDate); err != nil {
			return false
		}
	}
	return true
}
func (s *Service) tasks(w http.ResponseWriter, r *http.Request) {
	pid, id := r.PathValue("project"), r.PathValue("task")
	if r.Method == "GET" || r.Method == "HEAD" {
		s.mu.RLock()
		defer s.mu.RUnlock()
		d, ok := s.loadProject(w, pid)
		if !ok {
			return
		}
		if id == "" {
			jsonReply(w, 200, valuesBy(d.Tasks, taskBefore))
			return
		}
		item, ok := d.Tasks[id]
		if found(w, ok) {
			jsonReply(w, 200, item)
		}
		return
	}
	var in taskInput
	if r.Method != "DELETE" {
		if !payload(w, r, &in) {
			return
		}
		if !validKey(in.IdempotencyKey) {
			jsonFail(w, 400, "请求标识无效")
			return
		}
		if in.PaperID != nil && *in.PaperID != "" {
			if _, ok := s.papers.Snapshot(*in.PaperID); !ok {
				jsonFail(w, 400, "关联论文不存在")
				return
			}
		}
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	d, ok := s.loadProject(w, pid)
	if !ok {
		return
	}
	if in.IdempotencyKey != "" && r.Method == "POST" {
		if existing, ok := d.TaskKeys[in.IdempotencyKey]; ok {
			t, exists := d.Tasks[existing]
			if !exists {
				jsonFail(w, 410, "该任务后来已被移除")
				return
			}
			jsonReply(w, 200, t)
			return
		}
	}
	d.Tasks = maps.Clone(d.Tasks)
	if r.Method == "POST" {
		t := Task{Entity: fresh(), ProjectID: pid, Status: "open"}
		if !updateTask(&t, in) {
			jsonFail(w, 400, "任务标题、状态或日期无效")
			return
		}
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
	t, ok := d.Tasks[id]
	if !found(w, ok) {
		return
	}
	if r.Method == "DELETE" {
		if !revisionOK(w, t.Revision, queryRevision(r.URL.Query())) {
			return
		}
		delete(d.Tasks, id)
		if s.save(w, d) {
			w.WriteHeader(204)
		}
		return
	}
	if !revisionOK(w, t.Revision, in.Revision) {
		return
	}
	if !updateTask(&t, in) {
		jsonFail(w, 400, "任务标题、状态或日期无效")
		return
	}
	t.bump()
	d.Tasks[id] = t
	if s.save(w, d) {
		jsonReply(w, 200, t)
	}
}
