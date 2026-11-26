package main

import (
	"context"
	"errors"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"time"

	"scistation.local/desktop/internal/magpieconfig"
)

const magpieRoundtableName = "Sci-Station"

type magpieAgentStatus struct {
	ID              string `json:"id"`
	Installed       bool   `json:"installed"`
	Enabled         bool   `json:"enabled"`
	Registered      bool   `json:"registered"`
	Connected       bool   `json:"connected"`
	CanInstall      bool   `json:"can_install"`
	CanOpen         bool   `json:"can_open"`
	RestartRequired bool   `json:"restart_required"`
	Model           string `json:"model,omitempty"`
	Port            int    `json:"port,omitempty"`
	Detail          string `json:"detail"`
}

type magpieDesktop struct {
	bundle string
	cli    string
}

var magpieInstallMu sync.Mutex

func findMagpieDesktop(ctx context.Context) magpieDesktop {
	if runtime.GOOS != "darwin" {
		return magpieDesktop{}
	}
	home, _ := os.UserHomeDir()
	dirs := []string{"/Applications"}
	if filepath.IsAbs(home) {
		dirs = append(dirs, filepath.Join(home, "Applications"))
	}
	for _, dir := range dirs {
		// Both cases are accepted on volumes that distinguish them.
		for _, name := range []string{"magpie.app", "Magpie.app"} {
			bundle := filepath.Join(dir, name)
			cli := filepath.Join(bundle, "Contents", "MacOS", "magpie")
			fi, err := os.Stat(cli)
			if err != nil || !fi.Mode().IsRegular() || fi.Mode().Perm()&0111 == 0 {
				continue
			}
			plist := filepath.Join(bundle, "Contents", "Info.plist")
			out, err := exec.CommandContext(ctx, "/usr/bin/plutil", "-extract", "CFBundleIdentifier", "raw", plist).Output()
			if err == nil && strings.TrimSpace(string(out)) == "com.yetone.magpie" {
				return magpieDesktop{bundle: bundle, cli: cli}
			}
		}
	}
	return magpieDesktop{}
}

func roundtableAgentResource() (bundle, resource string) {
	exe, err := os.Executable()
	if err != nil {
		return "", ""
	}
	if exe, err = filepath.EvalSymlinks(exe); err != nil || filepath.Base(exe) != "sci-station" {
		return "", ""
	}
	macOS := filepath.Dir(exe)
	contents := filepath.Dir(macOS)
	bundle = filepath.Dir(contents)
	if filepath.Base(macOS) != "MacOS" || filepath.Base(contents) != "Contents" || filepath.Ext(bundle) != ".app" {
		return "", ""
	}
	resource = filepath.Join(contents, "Resources", magpieconfig.AgentFile)
	fi, err := os.Lstat(resource)
	if err != nil || !fi.Mode().IsRegular() {
		return "", ""
	}
	return bundle, resource
}

// Magpie displays the agent's own help only when the enabled module loads.
// The help path skips Magpie's startup migrations and provider probes.
func magpieKnowsRoundtable(ctx context.Context, path string) bool {
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, path, magpieconfig.AgentID, "--help").Output()
	return err == nil && strings.HasPrefix(string(out), magpieRoundtableName+"\n\n") &&
		strings.Contains(string(out), "\n  magpie "+magpieconfig.AgentID+" <model>") &&
		strings.Contains(string(out), "\nfields: model\n")
}

func matchingMagpieEntry(entries []magpieconfig.Entry, resource string) (magpieconfig.Entry, bool) {
	for _, entry := range entries {
		if entry.Spec == resource {
			return entry, true
		}
	}
	if len(entries) > 0 {
		return entries[0], true
	}
	return magpieconfig.Entry{}, false
}

func (a *apiServer) readMagpieAgent(ctx context.Context, desktop magpieDesktop, resource string) magpieAgentStatus {
	s := magpieAgentStatus{ID: magpieconfig.AgentID, CanOpen: a.desktop && desktop.bundle != ""}
	entries, err := magpieconfig.Registered()
	if err != nil {
		s.Detail = magpieconfig.ErrRegistry.Error()
		return s
	}
	entry, found := matchingMagpieEntry(entries, resource)
	s.Installed, s.Enabled = found, found && !entry.Off
	canInstall := a.desktop && desktop.cli != "" && resource != ""
	switch {
	case !found:
		s.CanInstall = canInstall
		if canInstall {
			s.Detail = "可将圆桌作为 Agent 注册到本机 Magpie。"
		} else if desktop.cli == "" {
			s.Detail = "未找到已安装的 Magpie 桌面应用。"
		} else {
			s.Detail = "请从已签名的圆桌桌面应用注册 Magpie 插件。"
		}
	case entry.Off:
		s.Detail = "圆桌 Agent 插件已关闭。请在 Magpie 的 Plugins 页面启用。"
	case desktop.cli == "":
		s.Detail = "已找到插件记录，未找到 Magpie 桌面应用来验证。"
	default:
		fi, err := os.Stat(entry.Spec)
		if err != nil || !fi.Mode().IsRegular() {
			s.Detail = "已登记的圆桌插件文件找不到。请在 Magpie 的 Plugins 页面移除失效条目后重新安装。"
			return s
		}
		s.Registered = magpieKnowsRoundtable(ctx, desktop.cli)
		if !s.Registered {
			s.CanInstall = canInstall && entry.Spec == resource
			s.Detail = "Magpie 的插件记录已存在，Agent 尚未通过加载验证。请检查 Magpie 的 Plugins 页面后重试。"
			return s
		}
		cfg, err := magpieconfig.Load(a.prefs.get().MagpiePort)
		s.Connected = err == nil && cfg.Connected
		if s.Connected {
			s.Model, s.Port = cfg.Model, cfg.Port
			s.Detail = "已使用 Magpie 为圆桌选定的模型。"
		} else if errors.Is(err, magpieconfig.ErrCustomKey) {
			s.Detail = err.Error()
		} else if errors.Is(err, magpieconfig.ErrDisconnected) {
			s.CanInstall = canInstall && entry.Spec == resource && !magpieconfig.ConnectionFileExists()
			s.Detail = "圆桌 Agent 已注册。请在 Magpie 的 Agents 页面刷新列表，再为圆桌选择模型。"
		} else {
			s.Detail = magpieconfig.ErrConfig.Error()
		}
	}
	return s
}

func (a *apiServer) magpieAgent(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 50*time.Second)
	defer cancel()
	desktop := findMagpieDesktop(ctx)
	bundle, resource := roundtableAgentResource()
	if r.Method == http.MethodGet {
		reply(w, http.StatusOK, a.readMagpieAgent(ctx, desktop, resource))
		return
	}
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", "GET, POST")
		reject(w, http.StatusMethodNotAllowed, "不支持这个操作")
		return
	}
	var request struct {
		Action string `json:"action"`
	}
	if !jsonBody(w, r, &request) {
		return
	}
	if !a.desktop || desktop.cli == "" {
		reject(w, http.StatusForbidden, "此操作需要圆桌和 Magpie 桌面应用。")
		return
	}
	switch request.Action {
	case "open":
		if err := exec.CommandContext(ctx, "/usr/bin/open", "-a", desktop.bundle).Run(); err != nil {
			reject(w, http.StatusBadGateway, "无法打开 Magpie 桌面应用。")
			return
		}
		reply(w, http.StatusOK, a.readMagpieAgent(ctx, desktop, resource))
	case "", "install":
		a.installMagpieAgent(ctx, w, desktop, bundle, resource)
	default:
		reject(w, http.StatusBadRequest, "未知的 Magpie 插件操作。")
	}
}

func (a *apiServer) installMagpieAgent(ctx context.Context, w http.ResponseWriter, desktop magpieDesktop, bundle, resource string) {
	if resource == "" || exec.CommandContext(ctx, "/usr/bin/codesign", "--verify", "--strict", `-R=identifier "com.funyday.scistation.desktop"`, bundle).Run() != nil {
		reject(w, http.StatusForbidden, "请从已签名的圆桌桌面应用安装内置插件。")
		return
	}
	magpieInstallMu.Lock()
	defer magpieInstallMu.Unlock()
	entries, err := magpieconfig.Registered()
	if err != nil {
		reject(w, http.StatusBadGateway, magpieconfig.ErrRegistry.Error())
		return
	}
	if entry, exists := matchingMagpieEntry(entries, resource); exists {
		if entry.Off {
			reply(w, http.StatusOK, a.readMagpieAgent(ctx, desktop, resource))
			return
		}
		if entry.Spec != resource {
			reply(w, http.StatusOK, a.readMagpieAgent(ctx, desktop, resource))
			return
		}
	} else {
		// Magpie may return an error while listing unrelated plugins after
		// writing the registry. Check what it actually registered below.
		_ = exec.CommandContext(ctx, desktop.cli, "plugin", "add", resource).Run()
	}
	s := a.readMagpieAgent(ctx, desktop, resource)
	if !s.Installed {
		reject(w, http.StatusBadGateway, "Magpie 未登记圆桌插件。请检查 Magpie 后重试。")
		return
	}
	if s.Registered {
		if err := magpieconfig.EnsureConnectionFile(); err != nil {
			reject(w, http.StatusInternalServerError, err.Error())
			return
		}
		s.CanInstall = false
	}
	reply(w, http.StatusOK, s)
}
