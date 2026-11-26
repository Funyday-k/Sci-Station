package main

import (
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"

	"scistation.local/desktop/internal/research"
	"scistation.local/desktop/internal/workspace"
)

// Newly selected roots require an explicit workstation format marker.
const rootMarker = workspace.RootMarker
const rootFormat = workspace.RootFormat

func inspectRoot(path string, create bool) (string, bool, error) {
	if path == "" {
		return "", false, errors.New("请选择一个工作区文件夹")
	}
	path, err := filepath.Abs(path)
	if err != nil {
		return "", false, err
	}
	path, err = filepath.EvalSymlinks(path)
	if err != nil {
		return "", false, err
	}
	if err := workspace.CheckRootAncestors(path); err != nil {
		return "", false, err
	}
	entries, err := workspace.ManagedReadDir(path)
	if err != nil {
		return "", false, err
	}
	names := make(map[string]os.DirEntry, len(entries))
	for _, e := range entries {
		if e.Name() != ".DS_Store" {
			names[e.Name()] = e
		}
	}
	if create {
		if len(names) != 0 {
			return "", false, errors.New("新工作区需要空文件夹。已有科研工作区请使用“打开工作区”。")
		}
		return path, true, nil
	}
	if _, ok := names[".sci-station"]; ok {
		return "", false, errors.New("这是旧版 Swift 科研根，请另选新版工作区；此目录不会被转换。")
	}
	if entry, ok := names[rootMarker]; ok {
		if !entry.Type().IsRegular() {
			return "", false, errors.New("工作区标记无效")
		}
		data, err := workspace.ManagedReadFile(filepath.Join(path, rootMarker))
		if err != nil {
			return "", false, err
		}
		if string(data) != rootFormat {
			return "", false, errors.New("无法读取此版本的工作区标记")
		}
	} else {
		return "", false, errors.New("未识别为已创建的桌面工作区。请在空文件夹中新建工作区。")
	}
	for _, name := range []string{"projects.json", "studio", "research", "research/records", "research/library", "research/library/pdf", "research/library/records", "research/workspaces", "research/trash", "research/blobs", "plugins", "settings.json", ".studio-process.lock"} {
		fi, err := os.Lstat(filepath.Join(path, name))
		if os.IsNotExist(err) {
			continue
		}
		if err != nil {
			return "", false, err
		}
		if fi.Mode()&os.ModeSymlink != 0 {
			return "", false, fmt.Errorf("工作区的受管路径是符号链接：%s", name)
		}
	}
	for _, name := range []string{"studio", "research", "plugins"} {
		base := filepath.Join(path, name)
		if _, err := os.Lstat(base); os.IsNotExist(err) {
			continue
		}
		err := filepath.WalkDir(base, func(loc string, entry fs.DirEntry, err error) error {
			if err != nil {
				return err
			}
			if entry.Type()&os.ModeSymlink != 0 || !entry.IsDir() && !entry.Type().IsRegular() {
				return fmt.Errorf("受管记录类型异常：%s", entry.Name())
			}
			if entry.IsDir() && (filepath.Dir(loc) == filepath.Join(path, "research", "workspaces") || filepath.Dir(loc) == filepath.Join(path, "research", "trash")) {
				return fs.SkipDir
			}
			return nil
		})
		if err != nil {
			return "", false, err
		}
	}
	if _, err := readRootDescription(path); err != nil {
		return "", false, err
	}
	return path, false, nil
}

func markNewRoot(dir string) error {
	f, err := workspace.ManagedOpenFile(filepath.Join(dir, rootMarker), os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if err != nil {
		return err
	}
	if _, err = f.WriteString(rootFormat); err == nil {
		err = f.Sync()
	}
	if closeErr := f.Close(); err == nil {
		err = closeErr
	}
	if err != nil {
		_ = workspace.ManagedRemove(filepath.Join(dir, rootMarker))
	}
	return err
}

// A local immutable port reservation keeps WebKit's origin and local storage
// attached to one canonical root across switches and relaunches. No process
// can acquire a port previously assigned to another root through the chooser.
type desktopRoots struct{ dir string }

func (r desktopRoots) reserve(path string, requested int) (int, error) {
	if err := workspace.ManagedMkdirAll(r.dir, 0700); err != nil {
		return 0, err
	}
	lock, err := workspace.ManagedOpenFile(filepath.Join(r.dir, ".ports.lock"), os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		return 0, err
	}
	defer lock.Close()
	if err = syscall.Flock(int(lock.Fd()), syscall.LOCK_EX); err != nil {
		return 0, err
	}
	binding, err := r.binding(path)
	if err != nil {
		return 0, err
	}
	key := binding.ID + "\n"
	if requested == 0 {
		entries, err := workspace.ManagedReadDir(r.dir)
		if err != nil {
			return 0, err
		}
		for _, e := range entries {
			raw, ok := strings.CutPrefix(e.Name(), "port-")
			if !ok || !e.Type().IsRegular() {
				continue
			}
			p, err := strconv.Atoi(raw)
			if err != nil || p < 1 || p > 65535 {
				continue
			}
			data, err := workspace.ManagedReadFile(filepath.Join(r.dir, e.Name()))
			if err != nil {
				return 0, err
			}
			if string(data) == key {
				return p, nil
			}
		}
	}
	// Ring selection is deterministic. The small ticket files resolve collisions
	// and remain reserved even while a volume is unmounted.
	start := int(sha256.Sum256([]byte(path))[0]) * 128
	for i := -1; i < 32768; i++ {
		port := requested
		if port == 0 {
			if i < 0 {
				port = 18765
			} else {
				port = 20000 + (start+i)%32768
			}
		}
		file := filepath.Join(r.dir, fmt.Sprintf("port-%d", port))
		occupied, err := workspace.ManagedReadFile(file)
		if err == nil {
			if string(occupied) == key {
				return port, nil
			}
			if requested != 0 {
				return 0, fmt.Errorf("端口 %d 已属于另一个工作区", port)
			}
			continue
		}
		if !os.IsNotExist(err) {
			return 0, err
		}
		if requested == 0 {
			// A prototype or unrelated application may already own the default
			// address. Reserve a fresh origin only if it is currently usable.
			probe, err := net.Listen("tcp4", fmt.Sprintf("127.0.0.1:%d", port))
			if errors.Is(err, syscall.EADDRINUSE) {
				continue
			}
			if err != nil {
				return 0, err
			}
			defer probe.Close()
		}
		if err := atomicFile(file, []byte(key)); err != nil {
			return 0, err
		}
		return port, nil
	}
	return 0, errors.New("没有可用的工作区端口")
}

func (r desktopRoots) last() (string, error) {
	data, err := workspace.ManagedReadFile(filepath.Join(r.dir, "last-workspace.json"))
	if errors.Is(err, os.ErrNotExist) {
		return "", nil
	}
	if err != nil {
		return "", err
	}
	var path string
	var identity string
	if json.Unmarshal(data, &path) != nil {
		var item struct {
			Version        int
			Path, Identity string
		}
		if json.Unmarshal(data, &item) != nil || item.Version != 1 {
			return "", errors.New("上次工作区的位置记录无法读取")
		}
		path, identity = item.Path, item.Identity
	}
	if !filepath.IsAbs(path) || strings.ContainsRune(path, 0) {
		return "", errors.New("上次工作区的位置记录无法读取")
	}
	return r.recordedPath(path, identity)
}
func (r desktopRoots) remember(path string) error {
	return r.withRecentLock(func() error { return r.writeRecent(path) })
}
func (r desktopRoots) writeRecent(path string) error {
	binding, err := r.binding(path)
	if err != nil {
		return err
	}
	file := filepath.Join(r.dir, "last-workspace.json")
	data, err := workspace.ManagedReadFile(file)
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	if len(data) > 0 {
		var legacy string
		if json.Unmarshal(data, &legacy) == nil {
			data = nil
		} else {
			var known struct{ Version int }
			if json.Unmarshal(data, &known) != nil || known.Version != 1 {
				return errors.New("无法覆盖未知最近工作区记录 / Unrecognized recent-workspace record")
			}
		}
	}
	raw, err := overlayFields(data, map[string]any{"version": 1, "path": path, "identity": binding.ID})
	if err != nil {
		return err
	}
	return atomicFile(file, raw)
}
func (r desktopRoots) afterRename(path string) error {
	return r.withRecentLock(func() error {
		recent, err := r.last()
		if err != nil || recent != path {
			return err
		}
		return r.writeRecent(path)
	})
}
func (r desktopRoots) recentStamp() string {
	data, err := workspace.ManagedReadFile(filepath.Join(r.dir, "last-workspace.json"))
	if err != nil {
		return ""
	}
	return fmt.Sprintf("%x", sha256.Sum256(data))
}

// Serialize recent-root mutations across desktop processes; an older window
// cannot clear the newer window's remembered selection.
func (r desktopRoots) withRecentLock(operation func() error) error {
	if err := workspace.ManagedMkdirAll(r.dir, 0700); err != nil {
		return err
	}
	f, err := workspace.ManagedOpenFile(filepath.Join(r.dir, ".recent.lock"), os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		return err
	}
	defer f.Close()
	if err = syscall.Flock(int(f.Fd()), syscall.LOCK_EX); err != nil {
		return err
	}
	return operation()
}
func (r desktopRoots) forget(expected string, stamp ...string) error {
	return r.withRecentLock(func() error {
		if len(stamp) > 0 && stamp[0] != r.recentStamp() {
			return errors.New("最近工作区已改变 / Recent workspace changed")
		}
		path, err := r.last()
		if err != nil && expected != "" {
			return err
		}
		if expected != "" && path != expected {
			return nil
		}
		err = workspace.ManagedRemove(filepath.Join(r.dir, "last-workspace.json"))
		if errors.Is(err, os.ErrNotExist) {
			return nil
		}
		return err
	})
}

func rootID(dir string) string { return fmt.Sprintf("%x", sha256.Sum256([]byte(dir))) }

type rootChoice struct {
	dir    string
	create bool
}

func (r desktopRoots) initial(explicit string) (rootChoice, error) {
	if explicit == "" {
		path, err := r.last()
		if err != nil {
			return rootChoice{}, err
		}
		return rootChoice{dir: path}, err
	}
	explicit, err := filepath.Abs(explicit)
	if err != nil {
		return rootChoice{}, err
	}
	if err = workspace.CheckRootAncestors(explicit); err != nil {
		return rootChoice{}, err
	}
	if err := workspace.ManagedMkdirAll(explicit, 0700); err != nil {
		return rootChoice{}, err
	}
	entries, err := workspace.ManagedReadDir(explicit)
	if err != nil {
		return rootChoice{}, err
	}
	create := len(entries) == 0 || len(entries) == 1 && entries[0].Name() == ".DS_Store"
	return rootChoice{dir: explicit, create: create}, nil
}

// A new selection invalidates older pending loads. The live service and origin
// are changed together only after the target has opened and can be restored.
type rootSession struct {
	mu         sync.Mutex
	generation uint64
	active     *workspaceInstance
	closed     bool
	moving     bool
	draining   sync.WaitGroup
}

func (s *rootSession) beginFor(expected *apiServer) uint64 {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed || s.moving || expected != nil && (s.active == nil || s.active.api != expected) {
		return 0
	}
	s.generation++
	return s.generation
}
func (s *rootSession) switchTo(token uint64, open func() (*workspaceInstance, error), publish func(*workspaceInstance) error) error {
	// Track pending opens as well as draining instances when the app quits.
	s.mu.Lock()
	if s.closed || token != s.generation {
		s.mu.Unlock()
		return nil
	}
	s.draining.Add(1)
	s.mu.Unlock()
	defer s.draining.Done()
	candidate, err := open()
	if err != nil {
		return err
	}
	s.mu.Lock()
	if s.closed || token != s.generation {
		s.mu.Unlock()
		candidate.close()
		return nil
	}
	previous := s.active
	if err = publish(candidate); err != nil {
		s.mu.Unlock()
		candidate.close()
		return err
	}
	s.active = candidate
	if previous != nil {
		s.draining.Add(1)
		go func() { defer s.draining.Done(); previous.close() }()
	}
	s.mu.Unlock()
	return nil
}
func (s *rootSession) shutdown() {
	s.mu.Lock()
	s.closed = true
	old := s.active
	s.active = nil
	s.mu.Unlock()
	if old != nil {
		old.close()
	}
	s.draining.Wait()
}

func (a *apiServer) workspaceAPI(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path == "/api/workspace/templates" && r.Method == http.MethodGet {
		reply(w, 200, research.CreationTemplates())
		return
	}
	if r.URL.Path == "/api/workspace" && r.Method == http.MethodGet {
		reply(w, 200, map[string]any{"id": a.rootIdentity(), "name": a.workspaceDisplay(), "folder": filepath.Base(a.workspaceDir), "desktop": a.desktop})
		return
	}
	if r.Method != http.MethodPost {
		reject(w, 405, "请使用工作区菜单")
		return
	}
	a.pickMu.RLock()
	choose := a.chooseWorkspace
	reveal := a.revealWorkspace
	create, forget, rename := a.createWorkspace, a.forgetWorkspace, a.renameWorkspace
	a.pickMu.RUnlock()
	switch r.URL.Path {
	case "/api/workspace/setup":
		var d rootSetup
		if !jsonBody(w, r, &d) {
			return
		}
		if err := d.validate(); err != nil {
			fail(w, err)
			return
		}
		if create == nil {
			reject(w, 409, "请在桌面应用中创建工作区")
			return
		}
		changed, err := create(d)
		if err != nil {
			fail(w, err)
			return
		}
		reply(w, 200, map[string]bool{"opened": changed})
		return
	case "/api/workspace/forget":
		var b struct{}
		if !jsonBody(w, r, &b) {
			return
		}
		if forget == nil {
			reject(w, 409, "请在桌面应用中管理最近工作区")
			return
		}
		if err := forget(); err != nil {
			fail(w, err)
			return
		}
		reply(w, 200, map[string]bool{"forgotten": true})
		return
	case "/api/workspace/rename":
		var b struct {
			Name string `json:"name"`
		}
		if !jsonBody(w, r, &b) {
			return
		}
		b.Name = strings.TrimSpace(b.Name)
		if rename == nil || b.Name == "" || !validWorkspaceName(b.Name) || strings.HasPrefix(b.Name, ".") {
			reject(w, 400, "请选择有效的工作区文件夹名称")
			return
		}
		if err := rename(b.Name); err != nil {
			fail(w, err)
			return
		}
		reply(w, 202, map[string]bool{"renaming": true})
		return
	}
	if r.URL.Path == "/api/workspace/reveal" {
		if reveal == nil {
			reject(w, 409, "请在桌面窗口显示工作区")
			return
		}
		var body struct{}
		if !jsonBody(w, r, &body) {
			return
		}
		if err := reveal(); err != nil {
			fail(w, err)
			return
		}
		reply(w, 200, map[string]bool{"revealed": true})
		return
	}
	if choose == nil {
		reject(w, 409, "请在桌面窗口选择工作区")
		return
	}
	var body struct{}
	if !jsonBody(w, r, &body) {
		return
	}
	// The native chooser and navigation outlive the requesting WebView document.
	go choose(r.URL.Path == "/api/workspace/create")
	reply(w, 202, map[string]bool{"choosing": true})
}
