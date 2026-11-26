package research

import (
	"encoding/json"
	"errors"
	"maps"
	"net/http"
	"path/filepath"
	"strings"
)

const reminderPreference = "syncNewAppleReminders"

var ErrReminderConflict = errors.New("任务或提醒关联已改变，请核对后重试")

func (s *Service) SetNewTaskReminder(publish func(Task) (string, error)) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.newTaskReminder = publish
}

func (s *Service) syncNewReminders() (bool, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	_, fields, err := s.readInterface()
	var enabled bool
	if err == nil && fields[reminderPreference] != nil {
		err = json.Unmarshal(fields[reminderPreference], &enabled)
	}
	return enabled, err
}

func (s *Service) ReminderSettings(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodGet {
		enabled, err := s.syncNewReminders()
		if err != nil {
			jsonFail(w, 500, "无法读取提醒事项偏好")
			return
		}
		jsonReply(w, 200, map[string]bool{reminderPreference: enabled})
		return
	}
	var input struct {
		Enabled *bool `json:"syncNewAppleReminders"`
	}
	if !payload(w, r, &input) {
		return
	}
	if input.Enabled == nil {
		jsonFail(w, 400, "请选择是否同步新任务")
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	language, fields, err := s.readInterface()
	if err != nil {
		jsonFail(w, 500, "无法读取提醒事项偏好")
		return
	}
	fields["language"], _ = json.Marshal(language)
	fields[reminderPreference], _ = json.Marshal(*input.Enabled)
	data, err := json.MarshalIndent(fields, "", "  ")
	if err != nil || atomicWrite(filepath.Join(s.dir, interfaceSettingsFile), append(data, '\n')) != nil {
		jsonFail(w, 500, "无法保存提醒事项偏好")
		return
	}
	jsonReply(w, 200, map[string]bool{reminderPreference: *input.Enabled})
}

func (s *Service) replyNewTask(w http.ResponseWriter, project string, task Task, publish func(Task) (string, error)) {
	var warning string
	if publish != nil && (task.Status == "open" || task.Status == "inProgress") {
		enabled, err := s.syncNewReminders()
		if enabled && err == nil {
			var id string
			if id, err = publish(task); err == nil {
				task, err = s.LinkAppleReminder(project, task, id)
			}
		}
		if err != nil {
			warning = err.Error()
		}
	}
	s.mu.RLock()
	view, visible := s.taskInScope(task, project)
	s.mu.RUnlock()
	if !visible {
		view = task
	}
	if warning != "" {
		view.extra = maps.Clone(view.extra)
		if view.extra == nil {
			view.extra = map[string]json.RawMessage{}
		}
		view.extra["reminderSyncWarning"], _ = json.Marshal(warning)
	}
	jsonReply(w, 201, view)
}

func (s *Service) LinkAppleReminder(project string, previous Task, identifier string) (Task, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	owner, task, ok := s.findTaskLocked(project, previous.ID)
	if !ok || previous.Revision != task.Revision || !label(identifier, 1024) ||
		(task.AppleReminderID != "" && task.AppleReminderID != identifier) {
		return previous, ErrReminderConflict
	}
	if task.AppleReminderID == identifier && task.ReminderRevision == task.Revision {
		return task, nil
	}
	task.AppleReminderID = identifier
	linked, err := s.commitReminderTask(owner, task)
	if err != nil {
		return previous, err
	}
	return linked, nil
}

func (s *Service) commitReminderTask(owner string, task Task) (Task, error) {
	task.bump()
	task.ReminderRevision = task.Revision
	collection := s.taskCollectionLocked(owner)
	collection.Tasks = maps.Clone(collection.Tasks)
	collection.Tasks[task.ID] = task
	return task, s.commitTasks(owner, collection)
}

func (s *Service) AppleReminderLinks(project string) []Task {
	s.mu.RLock()
	defer s.mu.RUnlock()
	var links []Task
	for _, item := range s.visibleTasksLocked(project) {
		if item.AppleReminderID != "" {
			_, task, _ := s.findTaskLocked(project, item.ID)
			links = append(links, task)
		}
	}
	return links
}

func (s *Service) PullAppleReminder(project string, snapshot Task, title, notes, date, clock string) (bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	owner, task, ok := s.findTaskLocked(project, snapshot.ID)
	if !ok || task.Revision != snapshot.Revision || task.AppleReminderID == "" ||
		task.AppleReminderID != snapshot.AppleReminderID || task.ReminderRevision != task.Revision {
		return false, ErrReminderConflict
	}
	if strings.TrimSpace(notes) == "" {
		notes = task.Description
	}
	if task.Title == title && task.Description == notes && task.DueDate == date && task.DueTime == clock {
		return false, nil
	}
	if err := s.updateTaskLocked(&task, taskInput{Title: &title, Description: &notes, DueDate: &date, DueTime: &clock}); err != nil {
		return false, err
	}
	_, err := s.commitReminderTask(owner, task)
	return err == nil, err
}
