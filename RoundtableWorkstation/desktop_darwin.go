//go:build darwin && !nogui

package main

import (
	"context"
	"fmt"
	"github.com/wailsapp/wails/v3/pkg/application"
	"github.com/wailsapp/wails/v3/pkg/events"
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
	languageUpdate   atomic.Uint64
	menuLanguage     atomic.Value
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
	language := resolveInterfaceLanguage(h.session.active.interfaceChoice(), preferredSystemLanguage())
	if options.URL == "" {
		message := interfaceText(language, "rootStartupPrompt")
		if issue != nil {
			message = issue.Error() + "。" + message
		}
		options.HTML = `<!doctype html><html lang="` + language + `"><meta charset="utf-8"><style>body{font:18px system-ui;margin:12%;line-height:1.7;color-scheme:light dark}</style><h1>` + interfaceText(language, "rootOpenTitle") + `</h1><p>` + html.EscapeString(message) + `</p></html>`
	}
	h.window = h.app.Window.NewWithOptions(options)
	if h.session.active != nil {
		h.installPickers(h.session.active.api)
	}
	h.window.OnWindowEvent(events.Mac.WebViewDidFinishNavigation, func(*application.WindowEvent) {
		h.session.mu.Lock()
		current := h.session.active
		h.session.mu.Unlock()
		go h.refreshMenu()
		if current != nil && current.api != nil {
			if script := current.api.desktopCredentialSessionScript(current.address); script != "" {
				h.window.ExecJS(script)
			}
		}
	})
	configureNativeLaunch(h.app, h.window)
	h.menu(language)
	h.app.Event.OnApplicationEvent(events.Mac.ApplicationDidBecomeActive, func(*application.ApplicationEvent) {
		go h.refreshMenu()
	})
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
	language := h.currentLanguage()
	copy := func(key string) string { return interfaceText(language, key) }
	if create {
		panel.SetTitle(copy("rootCreateTitle")).SetMessage(copy("rootCreatePrompt")).SetButtonText(copy("toolbarCreateWorkspace"))
	} else {
		panel.SetTitle(copy("rootOpenTitle")).SetMessage(copy("rootOpenPrompt")).SetButtonText(copy("toolbarOpenWorkspace"))
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
			if err == nil {
				go h.refreshMenu()
			}
		}
	}
	if err != nil {
		h.app.Dialog.Error().AttachToWindow(h.window).SetTitle(copy("rootOpenError")).SetMessage(err.Error()).Show()
	}
}
func (h *desktopHost) installPickers(host *apiServer) {
	if host == nil {
		return
	}
	app, window := h.app, h.window
	if service, ok := host.research.(interface{ OnInterfaceLanguageChanged(func()) }); ok {
		service.OnInterfaceLanguageChanged(func() { go h.refreshMenu() })
	}
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
		language := h.currentLanguage()
		return app.Dialog.OpenFile().
			CanChooseDirectories(true).
			CanChooseFiles(false).
			CanCreateDirectories(true).
			AttachToWindow(window).
			SetTitle(interfaceText(language, "pickProjectFolder")).
			SetMessage(interfaceText(language, "pickProjectPrompt")).
			SetButtonText(interfaceText(language, "chooseFolder")).
			PromptForSingleSelection()
	})
	host.setSavePicker(func(filename, _ string) (string, error) {
		h.panelMu.Lock()
		defer h.panelMu.Unlock()
		if h.closing.Load() {
			return "", context.Canceled
		}
		// The plugin export endpoint validates its own file extensions.
		language := h.currentLanguage()
		return app.Dialog.SaveFile().AttachToWindow(window).
			SetFilename(filename).
			HideExtension(false).AllowsOtherFileTypes(true).CanCreateDirectories(true).
			SetMessage(interfaceText(language, "chooseSaveLocation")).SetButtonText(interfaceText(language, "toolbarSave")).
			PromptForSingleSelection()
	})
}
func (h *desktopHost) menu(language string) {
	if h.menuLanguage.Load() == language {
		return
	}
	copy := func(key string) string { return interfaceText(language, key) }
	app := h.app
	menu := app.NewMenu()
	menu.AddRole(application.AppMenu)
	menu.AddRole(application.FileMenu)
	ws := menu.AddSubmenu(copy("toolbarWorkspace"))
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
	ws.Add(copy("toolbarCreateWorkspace") + "…").OnClick(func(*application.Context) { choose(true) })
	ws.Add(copy("toolbarOpenWorkspace") + "…").SetAccelerator("CmdOrCtrl+O").OnClick(func(*application.Context) { choose(false) })
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
	add(ws, []entry{{copy("toolbarNewProject") + "…", "newProject", "CmdOrCtrl+N"}, {copy("revealWorkspace"), "revealWorkspace", ""}, {copy("sidebarResearchShell"), "home", "CmdOrCtrl+1"}, {copy("openRoundtable"), "roundtable", "CmdOrCtrl+2"}, {copy("pluginMarketplace"), "plugins", ""}, {copy("routeSettings") + "…", "settings", "CmdOrCtrl+,"}})
	add(menu.AddSubmenu(copy("libraryMenu")), []entry{{copy("toolbarImportPDF") + "…", "importPDF", ""}, {copy("toolbarAddByIdentifier") + "…", "importIdentifier", ""}, {copy("menuOpenInReader"), "reader", ""}, {copy("menuOpenExternalPDF"), "externalPDF", ""}, {copy("menuRevealPaperInFinder"), "reveal", ""}, {copy("menuCopyCitation"), "copyCitation", ""}, {copy("menuCopyBibTeX"), "copyBibtex", ""}, {copy("menuExportBibTeX") + "…", "bibtex", ""}, {copy("menuDeleteSelectedPaper"), "deletePaper", "CmdOrCtrl+Backspace"}})
	add(menu.AddSubmenu(copy("menuView")), []entry{{copy("back"), "back", "CmdOrCtrl+["}, {copy("forward"), "forward", "CmdOrCtrl+]"}, {copy("find"), "find", "CmdOrCtrl+F"}, {copy("findNext"), "findNext", "CmdOrCtrl+G"}, {copy("findPrevious"), "findPrevious", "CmdOrCtrl+Shift+G"}, {copy("toolbarInspector"), "inspector", "CmdOrCtrl+I"}})
	add(menu.AddSubmenu("Wiki"), []entry{{copy("toolbarSave"), "save", "CmdOrCtrl+S"}})
	menu.AddRole(application.EditMenu)
	menu.AddRole(application.WindowMenu)
	app.Menu.Set(menu)
	h.menuLanguage.Store(language)
}
