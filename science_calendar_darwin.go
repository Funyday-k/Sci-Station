//go:build darwin && cgo && !nogui

package main

/*
#cgo CFLAGS: -fobjc-arc
#cgo LDFLAGS: -framework Foundation -framework EventKit
#include <stdlib.h>
char *sciCalendarUpcoming(void);
char *sciCalendarSchedule(double start, double end, int prompt, int remindersOnly);
char *sciCalendarPublish(const char *marker, const char *title, const char *detail, const char *due, const char *expected, int automatic);
*/
import "C"

import (
	"encoding/json"
	"errors"
	"strings"
	"sync/atomic"
	"time"
	"unsafe"
)

var desktopCalendarActive atomic.Bool

func systemCalendarEvents() ([]calendarItem, error) {
	if !desktopCalendarActive.Load() {
		return nil, errors.New("请在 Sci-Station 桌面应用中打开系统日历")
	}
	var events []calendarItem
	err := decodeEventKitResult(C.sciCalendarUpcoming(), &events)
	return events, err
}

func systemCalendarSchedule(start, end time.Time, prompt, remindersOnly bool) (systemSchedule, error) {
	var items systemSchedule
	if !desktopCalendarActive.Load() {
		return items, errors.New("请在 Sci-Station 桌面应用中打开系统日历")
	}
	var request, reminders C.int
	if prompt {
		request = 1
	}
	if remindersOnly {
		reminders = 1
	}
	err := decodeEventKitResult(C.sciCalendarSchedule(C.double(start.Unix()), C.double(end.Unix()), request, reminders), &items)
	return items, err
}

func publishReminder(id, title, detail, dueDate, expected string, automatic bool) (string, error) {
	if !desktopCalendarActive.Load() {
		return "", errors.New("请在 Sci-Station 桌面应用中发布提醒事项")
	}
	title = strings.TrimSpace(title)
	if strings.TrimSpace(id) == "" || title == "" {
		return "", errors.New("提醒事项需要任务 ID 和标题")
	}
	if strings.ContainsRune(title+detail+expected, 0) {
		return "", errors.New("提醒事项正文含有无效字符")
	}
	if dueDate != "" {
		layout := time.DateOnly
		if strings.Contains(dueDate, "T") {
			layout += "T15:04"
		}
		if _, err := time.Parse(layout, dueDate); err != nil {
			return "", errors.New("截止日期或时间无效")
		}
	}
	marker := C.CString(reminderMarker(id))
	name := C.CString(title)
	body := C.CString(detail)
	due := C.CString(dueDate)
	existing := C.CString(expected)
	defer C.free(unsafe.Pointer(marker))
	defer C.free(unsafe.Pointer(name))
	defer C.free(unsafe.Pointer(body))
	defer C.free(unsafe.Pointer(due))
	defer C.free(unsafe.Pointer(existing))
	var identifier string
	var createOnly C.int
	if automatic {
		createOnly = 1
	}
	err := decodeEventKitResult(C.sciCalendarPublish(marker, name, body, due, existing, createOnly), &identifier)
	return identifier, err
}

func decodeEventKitResult(payload *C.char, target any) error {
	if payload == nil {
		return errors.New("系统日历没有返回结果")
	}
	defer C.free(unsafe.Pointer(payload))
	var envelope struct {
		Error string          `json:"error"`
		Value json.RawMessage `json:"value"`
	}
	if err := json.Unmarshal([]byte(C.GoString(payload)), &envelope); err != nil {
		return err
	}
	if envelope.Error != "" {
		return errors.New(envelope.Error)
	}
	return json.Unmarshal(envelope.Value, target)
}
