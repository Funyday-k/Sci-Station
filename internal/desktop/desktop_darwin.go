//go:build darwin && !nogui

package desktop

import (
	"context"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"sync/atomic"
	"time"

	"github.com/wailsapp/wails/v3/pkg/application"
	"github.com/wailsapp/wails/v3/pkg/events"
	"scistation.local/desktop/internal/workspace"
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
	choice, issue := roots.desktopInitial(explicit)
	options := application.WebviewWindowOptions{Hidden: true, Name: "Sci-Station", Title: "Sci-Station", Width: 1380, Height: 900, MinWidth: 900, MinHeight: 620,
		BackgroundColour: application.NewRGB(246, 247, 249), Mac: application.MacWindow{WebviewPreferences: application.MacWebviewPreferences{ApplicationNameForUserAgent: desktopUserAgent}}}
	if issue == nil && choice.dir != "" {
		var instance *workspaceInstance
		instance, issue = h.start(choice, port)
		if issue == nil {
			h.session.active = instance
			options.URL = instance.address + "/resume"
			options.Title = roots.windowTitle(instance)
		}
	}
	language := resolveInterfaceLanguage(h.session.active.interfaceChoice(), preferredSystemLanguage())
	if options.URL == "" {
		message := ""
		if issue != nil {
			message = issue.Error()
		}
		welcome, err := startWorkspaceWelcome(roots, language, message)
		if err != nil {
			return err
		}
		h.session.active = welcome
		options.URL = welcome.address + "/welcome"
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
		if current != nil && current.dir != "" && current.api != nil {
			if script := current.api.cliEditWindowScript(current.address); script != "" {
				evaluateWorkstationScript(h.window, current.address, script)
			}
			if script := current.api.desktopCredentialSessionScript(current.address); script != "" {
				evaluateWorkstationScript(h.window, current.address, script)
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

func (h *desktopHost) start(choice rootChoice, port int, setup ...rootSetup) (*workspaceInstance, error) {
	return startRegisteredWorkspace(h.roots, choice, port, true, setup...)
}
func (h *desktopHost) choose(create bool, expected *apiServer) {
	_, err := h.selectWorkspace(create, expected, nil)
	if err != nil && !h.closing.Load() {
		h.app.Dialog.Error().AttachToWindow(h.window).SetTitle(interfaceText(h.currentLanguage(), "rootOpenError")).SetMessage(err.Error()).Show()
	}
}

func (h *desktopHost) selectWorkspace(create bool, expected *apiServer, setup *rootSetup) (bool, error) {
	token := h.session.beginFor(expected)
	if token == 0 {
		return false, nil
	}
	h.panelMu.Lock()
	if h.closing.Load() {
		h.panelMu.Unlock()
		return false, nil
	}
	panel := h.app.Dialog.OpenFile().CanChooseDirectories(true).CanChooseFiles(false).CanCreateDirectories(create).AttachToWindow(h.window)
	language := h.currentLanguage()
	copy := func(key string) string { return interfaceText(language, key) }
	if setup != nil && !setup.UseEmptyFolder {
		message := "请选择新工作区文件夹的存放位置。"
		if language == "en" {
			message = "Select the parent folder for the new workspace."
		}
		panel.SetTitle(copy("rootCreateTitle")).SetMessage(message).SetButtonText(copy("chooseFolder"))
	} else if create {
		panel.SetTitle(copy("rootCreateTitle")).SetMessage(copy("rootCreatePrompt")).SetButtonText(copy("toolbarCreateWorkspace"))
	} else {
		panel.SetTitle(copy("rootOpenTitle")).SetMessage(copy("rootOpenPrompt")).SetButtonText(copy("toolbarOpenWorkspace"))
	}
	path, err := panel.PromptForSingleSelection()
	h.panelMu.Unlock()
	if err != nil || path == "" || h.closing.Load() {
		return false, err
	}
	if setup == nil {
		return h.openSelectedRoot(token, rootChoice{dir: path, create: create})
	}
	return h.switchRoot(token, func() (*workspaceInstance, error) {
		dir, err := prepareWorkspaceTarget(path, *setup)
		if err != nil {
			return nil, err
		}
		next, err := h.start(rootChoice{dir: dir, create: true}, 0, *setup)
		if err != nil && !setup.UseEmptyFolder {
			// Only remove an empty folder we created. A published or externally
			// populated folder stays available for a subsequent open.
			_ = workspace.ManagedRemove(dir)
		}
		return next, err
	})
}

func (h *desktopHost) changeDataLocation(ctx context.Context, host *apiServer, useDefault bool) (bool, error) {
	token := h.session.beginFor(host)
	if token == 0 {
		return false, nil
	}
	lang := h.currentLanguage()
	copy := func(key string) string { return interfaceText(lang, key) }
	var choice rootChoice
	var err error
	// A loopback request may prompt, but only a native user decision can
	// change the remembered location. Requests never supply a filesystem path.
	h.panelMu.Lock()
	if h.closing.Load() {
		h.panelMu.Unlock()
		return false, nil
	}
	if useDefault {
		answer := make(chan bool, 1)
		panel := h.app.Dialog.Question().AttachToWindow(h.window).SetTitle(copy("storageUseDefault"))
		panel.SetMessage(h.roots.defaultDataDir() + "\n\n" + copy("storageSwitchHint"))
		panel.AddButton(copy("storageCancel")).SetAsCancel().OnClick(func() { answer <- false })
		panel.AddButton(copy("storageUseDefault")).SetAsDefault().OnClick(func() { answer <- true })
		panel.Show()
		var confirmed bool
		select {
		case confirmed = <-answer:
		case <-ctx.Done():
		}
		h.panelMu.Unlock()
		if !confirmed || h.closing.Load() {
			return false, nil
		}
		choice, err = h.roots.initial(h.roots.defaultDataDir())
	} else {
		path, issue := h.app.Dialog.OpenFile().AttachToWindow(h.window).
			CanChooseDirectories(true).CanChooseFiles(false).CanCreateDirectories(true).
			SetTitle(copy("storageChoose")).SetMessage(copy("storageChooseHint")).
			SetButtonText(copy("chooseFolder")).PromptForSingleSelection()
		h.panelMu.Unlock()
		if issue != nil || path == "" || h.closing.Load() {
			return false, issue
		}
		choice, err = storageFolderChoice(path)
	}
	if err != nil {
		return false, err
	}
	return h.openSelectedRoot(token, choice)
}

func (h *desktopHost) openSelectedRoot(token uint64, choice rootChoice) (bool, error) {
	dir, _, err := inspectRoot(choice.dir, choice.create)
	if err != nil {
		return false, err
	}
	choice.dir = dir
	if !choice.create {
		choice.expected, err = folderIdentity(dir)
		if err != nil {
			return false, err
		}
		h.session.mu.Lock()
		current := h.session.active
		if !h.session.closed && token == h.session.generation && current != nil && current.dir == dir && current.binding.matches(choice.expected) {
			err = h.roots.remember(dir, current.binding)
			h.session.mu.Unlock()
			return err == nil, err
		}
		h.session.mu.Unlock()
	}
	return h.switchRoot(token, func() (*workspaceInstance, error) { return h.start(choice, 0) })
}

func (h *desktopHost) switchRoot(token uint64, open func() (*workspaceInstance, error)) (bool, error) {
	opened := false
	err := h.session.switchTo(token, open, func(next *workspaceInstance) error {
		if err := h.roots.remember(next.dir, next.binding); err != nil {
			return err
		}
		if previous := h.session.active; previous != nil {
			previous.api.forgetCLIEditWindow()
		}
		h.presentRoot(next)
		opened = true
		return nil
	})
	if opened {
		go h.refreshMenu()
	}
	return opened, err
}

func (h *desktopHost) presentRoot(next *workspaceInstance) {
	h.installPickers(next.api)
	title := h.roots.windowTitle(next)
	application.InvokeAsync(func() { h.window.SetTitle(title); h.window.SetURL(next.address + "/resume") })
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
	host.changeStorage = func(ctx context.Context, useDefault bool) (bool, error) {
		return h.changeDataLocation(ctx, host, useDefault)
	}
	host.createWorkspace = func(d rootSetup) (bool, error) { return h.selectWorkspace(true, host, &d) }
	startupStamp := h.roots.recentStamp()
	host.forgetWorkspace = func() error {
		h.session.mu.Lock()
		defer h.session.mu.Unlock()
		if h.session.active == nil || h.session.active.api != host {
			return errors.New("工作区已切换 / Workspace changed")
		}
		return h.roots.forget(h.session.active.dir, startupStamp)
	}
	if host.workspaceDir != "" {
		host.renameWorkspace = func(name string) error { return h.rename(host, name) }
	}
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
		h.menuCommand(command)
	}
	ws.Add(copy("toolbarCreateWorkspace") + "…").OnClick(func(*application.Context) { choose(true) })
	ws.Add(copy("toolbarOpenWorkspace") + "…").SetAccelerator("CmdOrCtrl+O").OnClick(func(*application.Context) { choose(false) })
	ws.AddSeparator()
	rename, forget := "重命名工作区…", "清除最近工作区"
	if language == "en" {
		rename, forget = "Rename workspace…", "Forget recent workspace"
	}
	ws.Add(rename).OnClick(func(*application.Context) { h.menuCommand("renameWorkspace") })
	ws.Add(forget).OnClick(func(*application.Context) { h.menuCommand("forgetWorkspace") })
	type entry struct{ label, command, key string }
	add := func(submenu *application.Menu, rows []entry) {
		for _, row := range rows {
			item := submenu.Add(row.label)
			if row.key != "" {
				item.SetAccelerator(row.key)
			}
			item.OnClick(func(*application.Context) {
				h.menuCommand(row.command)
				h.window.Show().Focus()
			})
		}
	}
	add(ws, []entry{{copy("toolbarNewProject") + "…", "newProject", "CmdOrCtrl+N"}, {copy("revealWorkspace"), "revealWorkspace", ""}, {copy("sidebarResearchShell"), "home", "CmdOrCtrl+1"}, {copy("openAIWorkspace"), "lab", "CmdOrCtrl+2"}, {copy("pluginMarketplace"), "plugins", ""}, {copy("routeSettings") + "…", "settings", "CmdOrCtrl+,"}})
	add(menu.AddSubmenu(copy("libraryMenu")), []entry{{copy("toolbarImportPDF") + "…", "importPDF", ""}, {copy("toolbarAddByIdentifier") + "…", "importIdentifier", ""}, {copy("menuOpenInReader"), "reader", ""}, {copy("menuOpenExternalPDF"), "externalPDF", ""}, {copy("menuPreviewSelectedPDF"), "preview", ""}, {copy("menuRevealPaperInFinder"), "reveal", ""}, {copy("menuCopyCitation"), "copyCitation", ""}, {copy("menuCopyBibTeX"), "copyBibtex", ""}, {copy("menuExportBibTeX") + "…", "bibtex", ""}, {copy("menuDeleteSelectedPaper"), "deletePaper", "CmdOrCtrl+Backspace"}})
	add(menu.AddSubmenu(copy("menuView")), []entry{{copy("back"), "back", "CmdOrCtrl+["}, {copy("forward"), "forward", "CmdOrCtrl+]"}, {copy("find"), "find", "CmdOrCtrl+F"}, {copy("findNext"), "findNext", "CmdOrCtrl+G"}, {copy("findPrevious"), "findPrevious", "CmdOrCtrl+Shift+G"}, {copy("toolbarInspector"), "inspector", "CmdOrCtrl+I"}})
	add(menu.AddSubmenu("Wiki"), []entry{{copy("toolbarSave"), "save", "CmdOrCtrl+S"}})
	menu.AddRole(application.EditMenu)
	menu.AddRole(application.WindowMenu)
	app.Menu.Set(menu)
	h.menuLanguage.Store(language)
}

func (h *desktopHost) rename(expected *apiServer, name string) error {
	h.session.mu.Lock()
	current := h.session.active
	if h.session.closed || h.session.moving || current == nil || current.api != expected || current.dir == "" {
		h.session.mu.Unlock()
		return errors.New("工作区已切换 / Workspace changed")
	}
	target := filepath.Join(filepath.Dir(current.dir), name)
	if target == current.dir {
		h.session.mu.Unlock()
		return nil
	}
	if _, err := os.Lstat(target); !errors.Is(err, os.ErrNotExist) {
		h.session.mu.Unlock()
		return errors.New("目标已存在 / Destination already exists")
	}
	identity := current.binding
	if actual, err := folderIdentity(current.dir); err != nil || !identity.matches(actual) {
		h.session.mu.Unlock()
		return errWorkspaceReplaced
	}
	h.session.moving = true
	h.session.generation++
	h.session.draining.Add(1)
	h.session.mu.Unlock()
	go func() {
		defer h.session.draining.Done()
		defer func() { h.session.mu.Lock(); h.session.moving = false; h.session.mu.Unlock() }()
		// Let the requesting POST release its normal HTTP read lease.
		deadline := time.Now().Add(2 * time.Second)
		for !current.freeze() {
			if time.Now().After(deadline) {
				h.renameError(errors.New("请等待当前请求或会议结束 / Wait for active requests or meetings to finish"))
				return
			}
			time.Sleep(25 * time.Millisecond)
		}
		current.close()
		dir := current.dir
		moveErr := h.roots.moveRoot(dir, target, identity)
		if moveErr == nil {
			dir = target
		}
		next, openErr := h.start(rootChoice{dir: dir, expected: identity}, 0)
		if openErr != nil && moveErr == nil {
			moveErr = errors.Join(openErr, h.roots.moveRoot(target, current.dir, identity))
			next, openErr = h.start(rootChoice{dir: current.dir, expected: identity}, 0)
		}
		h.session.mu.Lock()
		if h.session.closed {
			h.session.mu.Unlock()
			if next != nil {
				next.close()
			}
			return
		}
		if openErr == nil {
			h.session.active = next
			if moveErr == nil {
				moveErr = h.roots.afterRename(next.dir, next.binding)
			}
			h.presentRoot(next)
		} else {
			welcome, werr := startWorkspaceWelcome(h.roots, h.currentLanguage(), errors.Join(openErr, moveErr).Error())
			if werr == nil {
				h.session.active = welcome
				h.installPickers(welcome.api)
				application.InvokeAsync(func() {
					h.window.SetTitle("Sci-Station")
					h.window.SetURL(welcome.address + "/welcome")
				})
			}
			moveErr = errors.Join(moveErr, openErr, werr)
		}
		h.session.mu.Unlock()
		if moveErr != nil {
			h.renameError(moveErr)
		}
	}()
	return nil
}
func (h *desktopHost) renameError(err error) {
	if !h.closing.Load() {
		h.app.Dialog.Error().AttachToWindow(h.window).SetTitle("重命名工作区 / Rename workspace").SetMessage(err.Error()).Show()
	}
}
