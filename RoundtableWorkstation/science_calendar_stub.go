//go:build !darwin || !cgo || nogui

package main

import "errors"

func systemCalendarEvents() ([]calendarItem, error) {
	return nil, errors.New("系统日历需要 macOS 桌面应用")
}

func publishReminder(id, title, detail, dueDate string) (string, error) {
	return "", errors.New("发布提醒事项需要 macOS 桌面应用")
}
