package desktop

import (
	"crypto/sha256"
	"encoding/hex"
	"net/http"
	"sort"
	"strings"
	"time"

	"scistation.local/desktop/internal/research"
)

type systemSchedule struct {
	Items          []calendarItem `json:"items"`
	EventsError    string         `json:"eventsError,omitempty"`
	RemindersError string         `json:"remindersError,omitempty"`
}

type calendarBridge struct {
	read    func(start, end time.Time, prompt, remindersOnly bool) (systemSchedule, error)
	publish func(key, title, notes, due, expected string, automatic bool) (string, error)
}

func reminderKey(task research.Task) string { return task.ProjectID + "/" + task.ID }

func reminderMarker(id string) string {
	hash := sha256.Sum256([]byte(id))
	return "sci-station://tasks/" + hex.EncodeToString(hash[:])
}

func calendarRange(reference time.Time) (time.Time, time.Time) {
	month := time.Date(reference.Year(), reference.Month(), 1, 0, 0, 0, 0, reference.Location())
	return month.AddDate(0, 0, -7), month.AddDate(0, 1, 7)
}

func (a *apiServer) sendReminder(task research.Task, automatic bool) (string, error) {
	due := task.DueDate
	if task.DueTime != "" {
		due += "T" + task.DueTime
	}
	publish := a.calendar.publish
	if publish == nil {
		publish = publishReminder
	}
	return publish(reminderKey(task), task.Title, task.Description, due, task.AppleReminderID, automatic)
}

func (a *apiServer) serveCalendarTools(lab *research.Service, w http.ResponseWriter, r *http.Request, route string) {
	if route == "reminder-settings" {
		if r.Method != http.MethodGet && r.Method != http.MethodPatch {
			reject(w, 405, "请选择读取或保存提醒事项偏好")
			return
		}
		lab.ReminderSettings(w, r)
		return
	}
	if r.Method != http.MethodPost {
		reject(w, 405, "请从科研工具发起")
		return
	}
	if !a.desktop {
		reject(w, 409, "请在 Sci-Station 桌面应用连接系统日历或提醒事项")
		return
	}
	if route == "events" {
		events, err := systemCalendarEvents()
		if err != nil {
			reject(w, 409, err.Error())
			return
		}
		reply(w, 200, events)
		return
	}
	if route == "reminder" {
		a.publishCalendarTask(lab, w, r)
		return
	}
	var input struct {
		Reference string `json:"reference"`
		Project   string `json:"project"`
		Prompt    bool   `json:"prompt"`
	}
	if !jsonBody(w, r, &input) {
		return
	}
	reference, err := time.ParseInLocation(time.DateOnly, input.Reference, time.Local)
	if err != nil || reference.Year() < 1 {
		reject(w, 400, "请选择有效的日历日期")
		return
	}
	if input.Project != "" && !lab.HasActiveProject(input.Project) {
		reject(w, 404, "科研项目不可用")
		return
	}
	var links []research.Task
	if route == "reminder-sync" {
		links = lab.AppleReminderLinks(input.Project)
	}
	read := a.calendar.read
	if read == nil {
		read = systemCalendarSchedule
	}
	start, end := calendarRange(reference)
	schedule, err := read(start, end, input.Prompt && route == "schedule", route == "reminder-sync")
	if err != nil {
		reject(w, 409, err.Error())
		return
	}
	if route == "reminder-sync" {
		if schedule.RemindersError != "" {
			reject(w, 409, schedule.RemindersError)
			return
		}
		updated, conflicts := reconcileReminders(lab, input.Project, links, schedule.Items, start, end)
		reply(w, 200, map[string]int{"updated": updated, "conflicts": conflicts})
		return
	}
	items := make([]calendarItem, len(schedule.Items))
	for i, item := range schedule.Items {
		item.Marker, item.Notes = "", ""
		items[i] = item
	}
	schedule.Items = items
	sort.SliceStable(schedule.Items, func(i, j int) bool { return schedule.Items[i].Start < schedule.Items[j].Start })
	reply(w, 200, schedule)
}

func (a *apiServer) publishCalendarTask(lab *research.Service, w http.ResponseWriter, r *http.Request) {
	var input struct {
		Project string `json:"project"`
		Task    string `json:"task"`
	}
	if !jsonBody(w, r, &input) {
		return
	}
	task, exists := lab.Task(input.Project, input.Task)
	if !exists {
		reject(w, 404, "任务不存在")
		return
	}
	id, err := a.sendReminder(task, false)
	if err == nil {
		_, err = lab.LinkAppleReminder(input.Project, task, id)
	}
	if err != nil {
		reject(w, 409, err.Error())
		return
	}
	reply(w, 200, map[string]string{"id": id})
}

func reconcileReminders(lab *research.Service, project string, links []research.Task, items []calendarItem, start, end time.Time) (updated, conflicts int) {
	reminders := map[string][]calendarItem{}
	for _, item := range items {
		if item.Kind == "reminder" && item.Marker != "" {
			reminders[item.Marker] = append(reminders[item.Marker], item)
		}
	}
	for _, task := range links {
		marker := reminderMarker(reminderKey(task))
		matches := reminders[marker]
		if len(matches) == 0 {
			continue
		}
		if len(matches) != 1 || matches[0].ID != task.AppleReminderID {
			conflicts++
			continue
		}
		item := matches[0]
		due, err := time.Parse(time.RFC3339, item.Start)
		if err != nil || due.Before(start) || !due.Before(end) {
			conflicts++
			continue
		}
		var clock string
		if item.HasTime {
			clock = due.Format("15:04")
		}
		var notes []string
		for _, line := range strings.Split(item.Notes, "\n") {
			if strings.TrimSpace(line) != marker {
				notes = append(notes, line)
			}
		}
		changed, err := lab.PullAppleReminder(project, task, item.Title, strings.TrimSpace(strings.Join(notes, "\n")), due.Format(time.DateOnly), clock)
		if err != nil {
			conflicts++
		} else if changed {
			updated++
		}
	}
	return updated, conflicts
}
