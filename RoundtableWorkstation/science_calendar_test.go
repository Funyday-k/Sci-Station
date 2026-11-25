package main

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"scistation.local/desktop/internal/research"
)

func calendarRequest(t *testing.T, handler http.Handler, method, route, input string, status int) []byte {
	t.Helper()
	req := httptest.NewRequest(method, "http://localhost:18765/api/research/"+route, strings.NewReader(input))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Roundtable", "1")
	w := httptest.NewRecorder()
	handler.ServeHTTP(w, req)
	if w.Code != status {
		t.Fatalf("%s %s returned %d, expected %d: %s", method, route, w.Code, status, w.Body.String())
	}
	return w.Body.Bytes()
}

func TestCalendarScopeAndReminderConflictSafety(t *testing.T) {
	lab, err := research.New(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	var prompts []bool
	var reminderReads []bool
	var schedule systemSchedule
	var offline bool
	var publicationKeys []string
	host := &apiServer{research: lab, desktop: true, calendar: calendarBridge{
		read: func(start, end time.Time, prompt, remindersOnly bool) (systemSchedule, error) {
			prompts = append(prompts, prompt)
			reminderReads = append(reminderReads, remindersOnly)
			if start.Format(time.DateOnly) != "2026-10-25" || end.Format(time.DateOnly) != "2026-12-08" {
				t.Fatalf("incorrect Swift-compatible month range: %s, %s", start, end)
			}
			if offline {
				return systemSchedule{}, errors.New("account offline")
			}
			return schedule, nil
		},
		publish: func(key, title, notes, due, expected string, automatic bool) (string, error) {
			if automatic || expected != "" || due != "2026-11-25T14:30" {
				t.Fatalf("unexpected publication mode, link or time: %v %q %q", automatic, expected, due)
			}
			publicationKeys = append(publicationKeys, key)
			return "fixture/" + key, nil
		},
	}}
	api := host.serve(18765)
	request := func(method, route, input string, status int) []byte {
		return calendarRequest(t, api, method, route, input, status)
	}
	projectA := scienceWorkflowDecode[research.Project](t, request("POST", "projects", `{"name":"Project A"}`, 201))
	projectB := scienceWorkflowDecode[research.Project](t, request("POST", "projects", `{"name":"Project B"}`, 201))
	pathA, pathB := "projects/"+projectA.ID+"/tasks", "projects/"+projectB.ID+"/tasks"
	create := `{"title":"Same title","dueDate":"2026-11-25","dueTime":"14:30"}`
	a := scienceWorkflowDecode[research.Task](t, request("POST", pathA, create, 201))
	b := scienceWorkflowDecode[research.Task](t, request("POST", pathB, create, 201))
	request("POST", "tools/reminder", `{"project":"`+projectA.ID+`","task":"`+a.ID+`"}`, 200)
	request("POST", "tools/reminder", `{"project":"`+projectB.ID+`","task":"`+b.ID+`"}`, 200)
	if len(publicationKeys) != 2 || publicationKeys[0] == publicationKeys[1] {
		t.Fatal("tasks shared a reminder key", publicationKeys)
	}
	readA := func() research.Task {
		return scienceWorkflowDecode[research.Task](t, request("GET", pathA+"/"+a.ID, "", 200))
	}
	markerA := reminderMarker(publicationKeys[0])
	itemA := calendarItem{ID: "fixture/" + publicationKeys[0], Kind: "reminder", Title: "Remote A", Start: "2026-11-26T08:15:00Z", HasTime: true, Marker: markerA, Notes: "Remote notes\n\n" + markerA, CalendarID: "reminder-list"}
	itemB := calendarItem{ID: "fixture/" + publicationKeys[1], Kind: "reminder", Title: "Remote B", Start: "2026-11-26T00:00:00Z", Marker: reminderMarker(publicationKeys[1])}
	schedule = systemSchedule{Items: []calendarItem{itemA, itemB}, EventsError: "calendar denied"}
	visible := scienceWorkflowDecode[systemSchedule](t, request("POST", "tools/schedule", `{"reference":"2026-11-25","prompt":true}`, 200))
	if !prompts[0] || reminderReads[0] || len(visible.Items) != 2 || visible.EventsError == "" || visible.Items[0].Marker != "" || visible.Items[0].Notes != "" {
		t.Fatal("invalid calendar partial result", visible)
	}
	input := `{"reference":"2026-11-25","project":"` + projectA.ID + `","prompt":true}`
	result := scienceWorkflowDecode[map[string]int](t, request("POST", "tools/reminder-sync", input, 200))
	changed := readA()
	if prompts[1] || !reminderReads[1] || result["updated"] != 1 || changed.Title != "Remote A" || changed.DueTime != "08:15" || changed.Description != "Remote notes" {
		t.Fatal("linked sync or prompt scope is incorrect", result, changed)
	}
	if other := scienceWorkflowDecode[research.Task](t, request("GET", pathB+"/"+b.ID, "", 200)); other.Title != "Same title" {
		t.Fatal("sync rewrote another project", other)
	}
	if same := scienceWorkflowDecode[map[string]int](t, request("POST", "tools/reminder-sync", input, 200)); same["updated"] != 0 || readA().Revision != changed.Revision {
		t.Fatal("repeat sync mutated the record", same)
	}
	patch, _ := json.Marshal(map[string]any{"revision": changed.Revision, "title": "Local edit"})
	request("PATCH", pathA+"/"+a.ID, string(patch), 200)
	for _, invalid := range []systemSchedule{
		{Items: []calendarItem{itemA}},
		{Items: []calendarItem{itemA, itemA}},
		{Items: []calendarItem{{ID: "different", Kind: "reminder", Marker: markerA}}},
	} {
		schedule = invalid
		conflict := scienceWorkflowDecode[map[string]int](t, request("POST", "tools/reminder-sync", input, 200))
		if conflict["conflicts"] != 1 || readA().Title != "Local edit" {
			t.Fatal("unsafe reminder update", conflict)
		}
	}
	schedule = systemSchedule{RemindersError: "access denied"}
	request("POST", "tools/reminder-sync", input, 409)
	offline = true
	request("POST", "tools/reminder-sync", input, 409)
	if readA().Title != "Local edit" {
		t.Fatal("native failure altered the task")
	}
}

func TestNewReminderSyncRequiresExplicitWorkspacePreference(t *testing.T) {
	dir := t.TempDir()
	lab, err := research.New(dir)
	if err != nil {
		t.Fatal(err)
	}
	var calls []string
	setup := func(lab *research.Service) http.Handler {
		host := &apiServer{research: lab, desktop: true, calendar: calendarBridge{
			publish: func(key, title, notes, due, expected string, automatic bool) (string, error) {
				if !automatic || expected != "" {
					t.Fatalf("automatic creation may not update an existing reminder: %v %q", automatic, expected)
				}
				calls = append(calls, key)
				if title == "Offline task" {
					return "", errors.New("account offline")
				}
				return "fixture/" + key, nil
			},
		}}
		lab.SetNewTaskReminder(func(task research.Task) (string, error) { return host.sendReminder(task, true) })
		return host.serve(18765)
	}
	api := setup(lab)
	request := func(method, route, input string, status int) []byte {
		return calendarRequest(t, api, method, route, input, status)
	}
	pref := "tools/reminder-settings"
	request("GET", pref, "", 200)
	request("POST", "tasks", `{"title":"Not opted in"}`, 201)
	if len(calls) != 0 {
		t.Fatal("used native reminders before explicit opt-in")
	}
	request("PATCH", pref, `{"syncNewAppleReminders":true}`, 200)
	if len(calls) != 0 {
		t.Fatal("saving preferences used native reminders")
	}
	lab, err = research.New(dir)
	if err != nil {
		t.Fatal(err)
	}
	api = setup(lab)
	input := `{"title":"New todo","idempotencyKey":"native-reminder"}`
	task := scienceWorkflowDecode[research.Task](t, request("POST", "tasks", input, 201))
	retry := scienceWorkflowDecode[research.Task](t, request("POST", "tasks", input, 200))
	if len(calls) != 1 || retry.ID != task.ID || task.AppleReminderID == "" || task.ReminderRevision != task.Revision {
		t.Fatal("task retry created another link or lost it", calls, task, retry)
	}
	failed := scienceWorkflowDecode[map[string]any](t, request("POST", "tasks", `{"title":"Offline task"}`, 201))
	local := scienceWorkflowDecode[research.Task](t, request("GET", "tasks/"+failed["id"].(string), "", 200))
	if failed["reminderSyncWarning"] != "account offline" || local.Title != "Offline task" || local.AppleReminderID != "" || local.Revision != 1 || len(calls) != 2 {
		t.Fatal("automatic failure did not preserve the local task", failed, local, calls)
	}
	request("PATCH", pref, `{"syncNewAppleReminders":false}`, 200)
	request("POST", "tasks", `{"title":"Opted out"}`, 201)
	if len(calls) != 2 {
		t.Fatal("automatic sync continued after opt-out")
	}
}
