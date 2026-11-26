//go:build darwin && cgo && !nogui

package desktop

/*
#cgo CFLAGS: -fobjc-arc
#cgo LDFLAGS: -framework AppKit -framework QuartzCore
void sciLaunchBegin(void);
void sciPrepareToQuit(void);
void sciLaunchReady(void *window, unsigned int windowID);
*/
import "C"

import (
	"sync"

	"github.com/wailsapp/wails/v3/pkg/application"
	"github.com/wailsapp/wails/v3/pkg/events"
)

// configureNativeLaunch attaches the splash to process startup, never to a
// view transition. A ready WKWebView and the splash timer may finish in either
// order. Only the native main thread touches AppKit or Core Animation.
func configureNativeLaunch(app *application.App, window *application.WebviewWindow) {
	desktopCalendarActive.Store(true)
	app.Event.OnApplicationEvent(events.Common.ApplicationStarted, func(*application.ApplicationEvent) {
		application.InvokeAsync(func() { C.sciLaunchBegin() })
	})

	var firstPage sync.Once
	window.OnWindowEvent(events.Mac.WebViewDidFinishNavigation, func(*application.WindowEvent) {
		firstPage.Do(func() {
			application.InvokeAsync(func() {
				C.sciLaunchBegin()
				C.sciLaunchReady(window.NativeWindow(), C.uint(window.ID()))
			})
		})
	})
}

// Called by the native animation after navigation and the minimum duration.
// Wails tracks hidden windows separately from NSWindow's visible state.
//
//export sciShowLaunchWindow
func sciShowLaunchWindow(id C.uint) {
	if window, ok := application.Get().Window.GetByID(uint(id)); ok {
		window.Show()
	}
}

// AppKit calls ShouldQuit on the main thread.
func prepareNativeQuit() { C.sciPrepareToQuit() }
