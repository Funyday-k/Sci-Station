package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"

	"scistation.local/desktop/internal/cli"
	"scistation.local/desktop/internal/gateway"
	"scistation.local/desktop/internal/meeting"
)

type preferences struct {
	meeting.Settings
	Appearance string `json:"appearance"`
	ColorTheme string `json:"color_theme"`
	TextSize   string `json:"text_size"`
}

type settingsStore struct {
	mu               sync.RWMutex
	file             string
	prefs            preferences
	providerProfiles *providerProfileStore
	gatewayOnce      sync.Once
	gateway          *gateway.Gateway
}

func openSettings(dir string) (*settingsStore, error) {
	p := preferences{
		Settings: meeting.Settings{
			Models:      map[string]string{"codex": "gpt-6.2-sol", "cursor": "composer-2.5"},
			ChildModels: map[string]string{"codex": "gpt-6-luna", "cursor": "composer-2.5"},
			CLIPaths:    map[string]string{"codex": "", "cursor": ""},
			Timeout:     180, MaxChildren: 1, MaxSteps: 10, AllowEdits: true,
			CodexTransport: "magpie", MagpiePort: 3425,
		},
		Appearance: "system",
		ColorTheme: "iris",
		TextSize:   "standard",
	}
	// Import only Magpie's port as an initial default. Its sign-ins stay in Magpie.
	base, err := os.UserHomeDir()
	if err == nil {
		config := os.Getenv("XDG_CONFIG_HOME")
		if config == "" {
			config = filepath.Join(base, ".config")
		}
		if b, e := os.ReadFile(filepath.Join(config, "magpie", "settings.json")); e == nil {
			var local struct {
				Port int `json:"port"`
			}
			if json.Unmarshal(b, &local) == nil && local.Port > 0 && local.Port <= 65535 {
				p.MagpiePort = local.Port
			}
		}
	}
	s := &settingsStore{file: filepath.Join(dir, "settings.json")}
	b, e := os.ReadFile(s.file)
	if e == nil {
		if e = json.Unmarshal(b, &p); e != nil {
			return nil, fmt.Errorf("无法读取圆桌设置: %w", e)
		}
	} else if !errors.Is(e, os.ErrNotExist) {
		return nil, e
	}
	if err := validatePrefs(p, false); err != nil {
		return nil, err
	}
	s.prefs = p
	return s, nil
}

// Readers retain this snapshot for the duration of a turn. Its maps are immutable.
func (s *settingsStore) get() preferences {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.prefs
}

func validatePrefs(p preferences, checkExecutables bool) error {
	if p.CodexTransport != "direct" && p.CodexTransport != "magpie" {
		return errors.New("请选择 Magpie 网关或 Codex 官方直连")
	}
	if p.MagpiePort < 1 || p.MagpiePort > 65535 || p.Timeout < 10 || p.Timeout > 1800 ||
		p.MaxSteps < 2 || p.MaxSteps > 40 || p.MaxChildren < 0 || p.MaxChildren > 5 {
		return errors.New("请检查端口（1–65535）、单次超时（10–1800 秒）、步骤数（2–40）或每席子代理数（0–5）")
	}
	if p.Appearance != "system" && p.Appearance != "dark" && p.Appearance != "light" {
		return errors.New("未知明暗模式")
	}
	switch p.ColorTheme {
	case "iris", "teal", "amber", "blue":
	default:
		return errors.New("未知配色主题")
	}
	switch p.TextSize {
	case "standard", "large", "extra-large":
	default:
		return errors.New("未知字号")
	}
	for _, m := range []map[string]string{p.Models, p.ChildModels, p.CLIPaths} {
		for k := range m {
			if k != "codex" && k != "cursor" {
				return fmt.Errorf("未知 CLI 席位 %q", k)
			}
		}
	}
	for _, seat := range []string{"codex", "cursor"} {
		for _, id := range []string{p.Models[seat], p.ChildModels[seat]} {
			if len(id) > 160 || strings.ContainsAny(id, " \r\n\t\x00") {
				return errors.New("CLI 型号应是单个模型标识")
			}
		}
		path := p.CLIPaths[seat]
		if checkExecutables && path != "" {
			if !filepath.IsAbs(path) || !cli.Discover(seat, path).Available {
				return fmt.Errorf("%s 的 CLI 路径须指向已安装的可执行文件", seat)
			}
			name := filepath.Base(path)
			if (seat == "codex" && name != "codex") || (seat == "cursor" && name != "cursor-agent" && name != "agent") {
				return fmt.Errorf("%s 路径的程序名不匹配", seat)
			}
		}
	}
	return nil
}

func (s *settingsStore) update(raw map[string]json.RawMessage) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	// Deep copy maps before decoding patches, so failed updates cannot affect live turns.
	existing, _ := json.Marshal(s.prefs)
	var next preferences
	if e := json.Unmarshal(existing, &next); e != nil {
		return e
	}
	allowed := map[string]bool{"models": true, "child_models": true, "cli_paths": true, "timeout": true,
		"max_children": true, "max_steps": true, "allow_edits": true, "magpie_port": true, "appearance": true,
		"color_theme": true, "text_size": true, "codex_transport": true}
	delete(raw, "cli_status")
	for k, v := range raw {
		if !allowed[k] || string(v) == "null" {
			return fmt.Errorf("无效的设置项 %q", k)
		}
	}
	patch, _ := json.Marshal(raw)
	if e := json.Unmarshal(patch, &next); e != nil {
		return errors.New("设置格式有误")
	}
	if e := validatePrefs(next, true); e != nil {
		return e
	}
	b, e := json.MarshalIndent(next, "", "  ")
	if e != nil {
		return e
	}
	if e = atomicFile(s.file, b); e != nil {
		return e
	}
	s.prefs = next
	return nil
}

func atomicFile(path string, body []byte) error {
	f, e := os.CreateTemp(filepath.Dir(path), ".roundtable-*")
	if e != nil {
		return e
	}
	defer os.Remove(f.Name())
	if _, e = f.Write(body); e == nil {
		e = f.Sync()
	}
	closeErr := f.Close()
	if e != nil {
		return e
	}
	if closeErr != nil {
		return closeErr
	}
	return os.Rename(f.Name(), path)
}
