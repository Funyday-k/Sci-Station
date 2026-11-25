//go:build darwin && !nogui

package main

import (
	"context"
	"fmt"
	"github.com/wailsapp/wails/v3/pkg/application"
	"html"
	"os/exec"
	"path/filepath"
	"sync"
	"sync/atomic"
)

type desktopHost struct {
	closing, drained atomic.Bool
	panelMu          sync.Mutex
	app              *application.App
	window           *application.WebviewWindow
	roots            desktopRoots
	session          rootSession
}

func runDesktop(explicit string, port int) error {
	roots, err := rootRegistry()
	if err != nil {
		return err
	}
	h := &desktopHost{roots: roots}
	h.app = application.New(application.Options{Name: "Sci-Station", Description: "A local workspace for research conversations",
		OnShutdown: h.session.shutdown,
		ShouldQuit: func() bool {
			if h.drained.Load() {
				return true
			}
			if h.closing.CompareAndSwap(false, true) {
				prepareNativeQuit()
				go func() { h.session.shutdown(); h.drained.Store(true); h.app.Quit() }()
			}
			return false
		}, Mac: application.MacOptions{ApplicationShouldTerminateAfterLastWindowClosed: true}})
	choice, issue := roots.initial(explicit)
	options := application.WebviewWindowOptions{Hidden: true, Name: "Sci-Station", Title: "Sci-Station", Width: 1380, Height: 900, MinWidth: 900, MinHeight: 620,
		BackgroundColour: application.NewRGB(246, 247, 249), Mac: application.MacWindow{WebviewPreferences: application.MacWebviewPreferences{ApplicationNameForUserAgent: desktopUserAgent}}}
	if issue == nil && choice.dir != "" {
		var instance *workspaceInstance
		instance, issue = h.start(choice, port)
		if issue == nil {
			h.session.active = instance
			options.URL = instance.address + "/resume"
		}
	}
	if options.URL == "" {
		message := "请在“工作区”菜单中选择已有工作区，或在空文件夹中新建工作区。"
		if issue != nil {
			message = issue.Error() + "。" + message
		}
		options.HTML = `<!doctype html><html lang="zh-CN"><meta charset="utf-8"><style>body{font:18px system-ui;margin:12%;line-height:1.7;color-scheme:light dark}</style><h1>打开科研工作区</h1><p>` + html.EscapeString(message) + `</p></html>`
	}
	h.window = h.app.Window.NewWithOptions(options)
	if h.session.active != nil {
		h.installPickers(h.session.active.api)
	}
	configureNativeLaunch(h.app, h.window)
	h.menu()
	defer h.session.shutdown()
	return h.app.Run()
}

func (h *desktopHost) start(choice rootChoice, port int) (*workspaceInstance, error) {
	dir, _, err := inspectRoot(choice.dir, choice.create)
	if err != nil {
		return nil, err
	}
	borrow := port != 0 && !choice.create
	port, err = h.roots.reserve(dir, port)
	if err != nil {
		return nil, err
	}
	if borrow {
		if borrowed := attachedWorkspace(dir, port); borrowed != nil {
			return borrowed, nil
		}
	}
	return startWorkspace(dir, port, true, choice.create)
}
func (h *desktopHost) choose(create bool, expected *apiServer) {
	token := h.session.beginFor(expected)
	if token == 0 {
		return
	}
	h.panelMu.Lock()
	if h.closing.Load() {
		h.panelMu.Unlock()
		return
	}
	panel := h.app.Dialog.OpenFile().CanChooseDirectories(true).CanChooseFiles(false).CanCreateDirectories(create).AttachToWindow(h.window)
	if create {
		panel.SetTitle("新建科研工作区").SetMessage("选择空文件夹，或点击新建文件夹。").SetButtonText("新建工作区")
	} else {
		panel.SetTitle("打开科研工作区").SetMessage("选择一个 Sci-Station 桌面工作区。").SetButtonText("打开工作区")
	}
	path, err := panel.PromptForSingleSelection()
	h.panelMu.Unlock()
	if h.closing.Load() {
		return
	}
	if path == "" && err == nil {
		return
	}
	if err == nil {
		var dir string
		dir, _, err = inspectRoot(path, create)
		if err == nil {
			h.session.mu.Lock()
			same := h.session.active != nil && h.session.active.dir == dir
			h.session.mu.Unlock()
			if same {
				return
			}
			err = h.session.switchTo(token, func() (*workspaceInstance, error) { return h.start(rootChoice{dir: dir, create: create}, 0) }, func(next *workspaceInstance) error {
				if err := h.roots.remember(next.dir); err != nil {
					return err
				}
				h.installPickers(next.api)
				application.InvokeAsync(func() {
					h.window.SetTitle("Sci-Station · " + filepath.Base(next.dir))
					h.window.SetURL(next.address + "/resume")
				})
				return nil
			})
		}
	}
	if err != nil {
		h.app.Dialog.Error().AttachToWindow(h.window).SetTitle("无法打开工作区").SetMessage(err.Error()).Show()
	}
}
func (h *desktopHost) installPickers(host *apiServer) {
	if host == nil {
		return
	}
	app, window := h.app, h.window
	configureMaterialDesktop(host, app, window, &h.panelMu)
	host.pickMu.Lock()
	host.chooseWorkspace = func(create bool) { h.choose(create, host) }
	host.revealWorkspace = func() error { return exec.Command("/usr/bin/open", "-R", host.workspaceDir).Run() }
	host.pickMu.Unlock()
	// PromptForSingleSelection dispatches the panel creation to the UI thread
	// itself. Do not wrap this entire blocking call in InvokeSync: the native
	// completion callback must be free to run on that same thread.
	host.setPicker(func() (string, error) {
		h.panelMu.Lock()
		defer h.panelMu.Unlock()
		if h.closing.Load() {
			return "", context.Canceled
		}
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
		h.panelMu.Lock()
		defer h.panelMu.Unlock()
		if h.closing.Load() {
			return "", context.Canceled
		}
		// The plugin export endpoint validates its own file extensions.
		return app.Dialog.SaveFile().AttachToWindow(window).
			SetFilename(filename).
			HideExtension(false).AllowsOtherFileTypes(true).CanCreateDirectories(true).
			SetMessage("选择文件的保存位置").SetButtonText("保存").
			PromptForSingleSelection()
	})
}
func (h *desktopHost) menu() {
	app := h.app
	menu := app.NewMenu()
	menu.AddRole(application.AppMenu)
	menu.AddRole(application.FileMenu)
	ws := menu.AddSubmenu("工作区")
	choose := func(create bool) {
		h.session.mu.Lock()
		live := h.session.active != nil && h.session.active.api != nil
		h.session.mu.Unlock()
		if !live {
			go h.choose(create, nil)
			return
		}
		command := "openWorkspace"
		if create {
			command = "createWorkspace"
		}
		h.window.ExecJS(fmt.Sprintf("window.SciStationNav?.command(%q)", command))
	}
	ws.Add("新建科研工作区…").OnClick(func(*application.Context) { choose(true) })
	ws.Add("打开科研工作区…").SetAccelerator("CmdOrCtrl+O").OnClick(func(*application.Context) { choose(false) })
	ws.AddSeparator()
	type entry struct{ label, command, key string }
	add := func(submenu *application.Menu, rows []entry) {
		for _, row := range rows {
			item := submenu.Add(row.label)
			if row.key != "" {
				item.SetAccelerator(row.key)
			}
			item.OnClick(func(*application.Context) {
				h.window.ExecJS(fmt.Sprintf("window.SciStationNav?.command(%q)", row.command))
				h.window.Show().Focus()
			})
		}
	}
	add(ws, []entry{{"新建项目…", "newProject", "CmdOrCtrl+N"}, {"在访达中显示工作区", "revealWorkspace", ""}, {"科研工作台", "home", "CmdOrCtrl+1"}, {"打开圆桌", "roundtable", "CmdOrCtrl+2"}, {"插件市场", "plugins", ""}, {"设置…", "settings", "CmdOrCtrl+,"}})
	add(menu.AddSubmenu("文献"), []entry{{"导入 PDF…", "importPDF", ""}, {"按标识符导入…", "importIdentifier", ""}, {"阅读文献", "reader", ""}, {"使用外部阅读器", "externalPDF", ""}, {"在访达中显示文献", "reveal", ""}, {"复制引用", "copyCitation", ""}, {"复制 BibTeX", "copyBibtex", ""}, {"导出 BibTeX…", "bibtex", ""}, {"移除文献", "deletePaper", "CmdOrCtrl+Backspace"}})
	add(menu.AddSubmenu("显示"), []entry{{"后退", "back", "CmdOrCtrl+["}, {"前进", "forward", "CmdOrCtrl+]"}, {"查找", "find", "CmdOrCtrl+F"}, {"查找下一处", "findNext", "CmdOrCtrl+G"}, {"查找上一处", "findPrevious", "CmdOrCtrl+Shift+G"}, {"检查器", "inspector", "CmdOrCtrl+I"}})
	add(menu.AddSubmenu("Wiki"), []entry{{"保存页面", "save", "CmdOrCtrl+S"}})
	menu.AddRole(application.EditMenu)
	menu.AddRole(application.WindowMenu)
	app.Menu.Set(menu)
}
