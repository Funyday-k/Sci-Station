//go:build darwin && !nogui

package desktop

/*
#cgo CFLAGS: -x objective-c
#cgo LDFLAGS: -framework Foundation
#import <Foundation/Foundation.h>
#include <stdlib.h>
#include <string.h>

static char *sciStationPreferredSystemLanguage(void) {
	@autoreleasepool {
		NSString *language = NSLocale.preferredLanguages.firstObject;
		return language == nil ? NULL : strdup(language.UTF8String);
	}
}
*/
import "C"

import (
	"encoding/json"
	"net/http"
	"net/url"
	"time"
	"unsafe"

	"github.com/wailsapp/wails/v3/pkg/application"
)

func preferredSystemLanguage() string {
	value := C.sciStationPreferredSystemLanguage()
	if value == nil {
		return "en"
	}
	defer C.free(unsafe.Pointer(value))
	return C.GoString(value)
}

var desktopLanguageClient = &http.Client{
	Timeout:       400 * time.Millisecond,
	Transport:     &http.Transport{Proxy: nil},
	CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
}

func (instance *workspaceInstance) interfaceChoice() string {
	if instance == nil {
		return "system"
	}
	if instance.api != nil {
		if service := instance.api.research; service != nil {
			if value, err := service.InterfaceLanguage(); err == nil {
				return value
			}
		}
		return "system"
	}
	response, err := desktopLanguageClient.Get(instance.address + "/api/research/interface")
	if err != nil {
		return "system"
	}
	defer response.Body.Close()
	var value struct {
		Language string `json:"language"`
	}
	if response.StatusCode == http.StatusOK && json.NewDecoder(response.Body).Decode(&value) == nil {
		return value.Language
	}
	return "system"
}

func (instance *workspaceInstance) globalAIEnabled() bool {
	if instance == nil || instance.dir == "" {
		return false
	}
	if instance.api != nil {
		route, err := instance.api.resolveWorkspaceRoute(&url.URL{Path: "/lab"})
		return err == nil && route == "/lab"
	}
	// A window attached to an existing service uses its ordinary route
	// decision, with redirects disabled on this bounded local client.
	response, err := desktopLanguageClient.Head(instance.address + "/lab")
	if err != nil {
		return false
	}
	defer response.Body.Close()
	return response.StatusCode == http.StatusOK
}

func (h *desktopHost) refreshMenu() {
	ticket := h.languageUpdate.Add(1)
	h.session.mu.Lock()
	current := h.session.active
	h.session.mu.Unlock()
	language := resolveInterfaceLanguage(current.interfaceChoice(), preferredSystemLanguage())
	aiEnabled := current.globalAIEnabled()
	application.InvokeAsync(func() {
		h.session.mu.Lock()
		active := h.session.active == current
		h.session.mu.Unlock()
		if !h.closing.Load() && active && h.languageUpdate.Load() == ticket {
			h.menu(language, aiEnabled)
		}
	})
}

func (h *desktopHost) currentLanguage() string {
	if value := h.menuLanguage.Load(); value != nil {
		return value.(string)
	}
	return resolveInterfaceLanguage("system", preferredSystemLanguage())
}
