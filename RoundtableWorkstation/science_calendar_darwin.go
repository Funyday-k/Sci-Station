//go:build darwin && cgo && !nogui

package main

/*
#cgo CFLAGS: -fobjc-arc
#cgo LDFLAGS: -framework Foundation -framework EventKit
#include <stdlib.h>
char *sciCalendarUpcoming(void);
char *sciCalendarPublish(const char *marker, const char *title, const char *detail, const char *due);
*/
import "C"

import (
	"crypto/sha256"
	"encoding/hex"
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

func publishReminder(id, title, detail, dueDate string) (string, error) {
	if !desktopCalendarActive.Load() {
		return "", errors.New("请在 Sci-Station 桌面应用中发布提醒事项")
	}
	title = strings.TrimSpace(title)
	if strings.TrimSpace(id) == "" || title == "" {
		return "", errors.New("提醒事项需要任务 ID 和标题")
	}
	if strings.ContainsRune(title+detail, 0) {
		return "", errors.New("提醒事项正文含有无效字符")
	}
	if dueDate != "" {
		if _, err := time.Parse("2006-01-02", dueDate); err != nil {
			return "", errors.New("截止日期应为有效的 YYYY-MM-DD 日期")
		}
	}
	hash := sha256.Sum256([]byte(id))
	marker := C.CString("sci-station://tasks/" + hex.EncodeToString(hash[:]))
	name := C.CString(title)
	body := C.CString(detail)
	due := C.CString(dueDate)
	defer C.free(unsafe.Pointer(marker))
	defer C.free(unsafe.Pointer(name))
	defer C.free(unsafe.Pointer(body))
	defer C.free(unsafe.Pointer(due))
	var identifier string
	err := decodeEventKitResult(C.sciCalendarPublish(marker, name, body, due), &identifier)
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
