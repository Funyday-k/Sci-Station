//go:build darwin && !nogui

package main

import (
	"sync"

	"github.com/wailsapp/wails/v3/pkg/application"
)

// runDesktop hosts the loopback application in a real WKWebView. The HTTP
// server owns application state; Wails owns the native window and dialogs.
func runDesktop(address string, host *apiServer, shutdown func()) error {
	app := application.New(application.Options{
		Name:        "Sci-Station",
		Description: "A local workspace for research conversations",
		OnShutdown:  shutdown,
		Mac: application.MacOptions{
			ApplicationShouldTerminateAfterLastWindowClosed: true,
		},
	})
	window := app.Window.NewWithOptions(application.WebviewWindowOptions{
		Hidden: true,
		Name:   "Sci-Station", Title: "Sci-Station",
		Width: 1380, Height: 900, MinWidth: 900, MinHeight: 620,
		URL:              address,
		BackgroundColour: application.NewRGB(246, 247, 249),
		Mac: application.MacWindow{
			WebviewPreferences: application.MacWebviewPreferences{ApplicationNameForUserAgent: desktopUserAgent},
		},
	})

	configureNativeLaunch(app, window)

	// PromptForSingleSelection dispatches the panel creation to the UI thread
	// itself. Do not wrap this entire blocking call in InvokeSync: the native
	// completion callback must be free to run on that same thread.
	var pickerMu sync.Mutex
	if host != nil {
		host.setPicker(func() (string, error) {
			pickerMu.Lock()
			defer pickerMu.Unlock()
			return app.Dialog.OpenFile().
				CanChooseDirectories(true).
				CanChooseFiles(false).
				CanCreateDirectories(true).
				AttachToWindow(window).
				SetTitle("选择项目文件夹").
				SetMessage("圆桌会关联所选文件夹，项目协作使用这里的文件。").
				SetButtonText("选择文件夹").
				PromptForSingleSelection()
		})
		host.setSavePicker(func(filename, _ string) (string, error) {
			pickerMu.Lock()
			defer pickerMu.Unlock()
			// The plugin export endpoint validates its own file extensions.
			return app.Dialog.SaveFile().AttachToWindow(window).
				SetFilename(filename).
				HideExtension(false).AllowsOtherFileTypes(true).CanCreateDirectories(true).
				SetMessage("选择文件的保存位置").SetButtonText("保存").
				PromptForSingleSelection()
		})
	}

	menu := app.NewMenu()
	menu.AddRole(application.AppMenu)
	menu.AddRole(application.FileMenu)
	workspace := menu.AddSubmenu("工作区")
	workspace.Add("科研工作台").SetAccelerator("CmdOrCtrl+1").OnClick(func(*application.Context) {
		window.ExecJS(`location.assign("/research")`)
		window.Show().Focus()
	})
	workspace.Add("打开圆桌").SetAccelerator("CmdOrCtrl+2").OnClick(func(*application.Context) {
		window.ExecJS(`if (window.dispatchEvent(new CustomEvent("roundtable:navigate", {cancelable:true, detail:"table"}))) location.assign("/studio");`)
		window.Show().Focus()
	})
	workspace.Add("插件市场").OnClick(func(*application.Context) {
		window.ExecJS(`if (window.dispatchEvent(new CustomEvent("roundtable:navigate", {cancelable:true, detail:"plugins"}))) location.assign("/studio?view=plugins");`)
		window.Show().Focus()
	})
	workspace.Add("设置…").SetAccelerator("CmdOrCtrl+,").OnClick(func(*application.Context) {
		window.ExecJS(`if (window.dispatchEvent(new CustomEvent("roundtable:navigate", {cancelable:true, detail:"settings"}))) location.assign("/studio?view=settings");`)
		window.Show().Focus()
	})
	menu.AddRole(application.EditMenu)
	menu.AddRole(application.WindowMenu)
	app.Menu.Set(menu)
	return app.Run()
}
