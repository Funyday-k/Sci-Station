//go:build !darwin || !cgo || nogui

package desktop

import (
	"errors"
	"time"
)

func systemCalendarEvents() ([]calendarItem, error) {
	return nil, errors.New("系统日历需要 macOS 桌面应用")
}

func systemCalendarSchedule(_, _ time.Time, _, _ bool) (systemSchedule, error) {
	return systemSchedule{}, errors.New("系统日历需要 macOS 桌面应用")
}

func publishReminder(id, title, detail, dueDate, expected string, automatic bool) (string, error) {
	return "", errors.New("发布提醒事项需要 macOS 桌面应用")
}
