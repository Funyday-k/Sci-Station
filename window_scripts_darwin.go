//go:build darwin && cgo && !nogui

package main

/*
#cgo CFLAGS: -fobjc-arc
#cgo LDFLAGS: -framework AppKit -framework WebKit
#include <stdlib.h>
void sciEvaluateWindowScript(void *window, const char *origin, const char *script);
*/
import "C"

import (
	"encoding/json"
	"maps"
	"net/url"
	"slices"
	"unsafe"

	"github.com/wailsapp/wails/v3/pkg/application"
)

// The workstation serves its own loopback documents, which don't initialize
// the Wails frontend runtime. Its queued ExecJS cannot deliver native window
// capabilities or menu commands to those pages.
func evaluateWorkstationScript(window *application.WebviewWindow, address, script string) {
	u, err := url.Parse(address)
	if err != nil || u.Scheme != "http" || u.Hostname() != "127.0.0.1" || u.Port() == "" || u.User != nil {
		return
	}
	origin := u.Scheme + "://" + u.Host
	encoded, _ := json.Marshal(origin)
	paths, _ := json.Marshal(append(slices.Sorted(maps.Keys(workspaceSurfaces)), "/", "/welcome"))
	// Recheck in the evaluated document in case it navigates between scheduling
	// and execution. Sensitive capability scripts also enforce their own route.
	guarded := `(()=>{if(window.top!==window||location.origin!==` + string(encoded) + `||!` + string(paths) + `.includes(location.pathname))return;` + script + `})()`
	application.InvokeAsync(func() {
		native := window.NativeWindow()
		if native == nil {
			return
		}
		uiOrigin, js := C.CString(origin), C.CString(guarded)
		defer C.free(unsafe.Pointer(uiOrigin))
		defer C.free(unsafe.Pointer(js))
		C.sciEvaluateWindowScript(native, uiOrigin, js)
	})
}

func (h *desktopHost) menuCommand(command string) {
	h.session.mu.Lock()
	current := h.session.active
	h.session.mu.Unlock()
	if current == nil {
		return
	}
	encoded, _ := json.Marshal(command)
	evaluateWorkstationScript(h.window, current.address, `window.SciStationNav?.command(`+string(encoded)+`)`)
}
