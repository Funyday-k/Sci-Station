// Package magpieconfig reads Sci-Station's local Magpie model selection.
package magpieconfig

import (
	"encoding/json"
	"errors"
	"io"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"unicode"
)

const AgentID = "sci-station"

// LoopbackIdentity follows Magpie's TokenFor(agentID) convention. It identifies
// the calling app to the local gateway and is the same on every installation.
const LoopbackIdentity = "magpie-" + AgentID
const AgentFile = "sci-station.agent.js"

var (
	ErrCustomKey    = errors.New("此连接使用自定义网关密钥。请在 Magpie 中重新连接本机网关。")
	ErrDisconnected = errors.New("请在 Magpie 的 Agents 页面为 Sci-Station 选择模型并连接")
	ErrConfig       = errors.New("圆桌的 Magpie 连接配置无效，请在 Magpie 中重新连接")
	ErrRegistry     = errors.New("无法读取 Magpie 插件状态")
)

type Config struct {
	Port      int
	Model     string
	Connected bool
}

type Entry struct {
	Spec string `json:"spec"`
	Off  bool   `json:"off"`
}

func connectionPath() (string, error) {
	home, err := os.UserHomeDir()
	if err != nil || !filepath.IsAbs(home) {
		return "", ErrConfig
	}
	return filepath.Join(home, ".config", "sci-station", "connection.json"), nil
}

// ConnectionFileExists reports whether Magpie can detect the app from its
// config file before a model has been chosen.
func ConnectionFileExists() bool {
	path, err := connectionPath()
	if err != nil {
		return false
	}
	fi, err := os.Stat(path)
	return err == nil && fi.Mode().IsRegular()
}

// EnsureConnectionFile makes an empty config so Magpie detects the installed
// desktop app even before a model is selected. Magpie owns the connection
// fields, so an existing file is preserved.
func EnsureConnectionFile() error {
	path, err := connectionPath()
	if err != nil {
		return err
	}
	if err = os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return ErrConfig
	}
	if ConnectionFileExists() {
		return nil
	}
	f, err := os.CreateTemp(filepath.Dir(path), ".connection-*")
	if err != nil {
		return ErrConfig
	}
	defer os.Remove(f.Name())
	_, writeErr := f.WriteString("{}\n")
	closeErr := f.Close()
	if writeErr != nil || closeErr != nil {
		return ErrConfig
	}
	// Publish a complete file and let an existing Magpie write win.
	if err := os.Link(f.Name(), path); err != nil && !ConnectionFileExists() {
		return ErrConfig
	}
	return nil
}

// Registered reads the Magpie registry, using the same config home as
// the installed macOS app and its CLI.
func Registered() ([]Entry, error) {
	path, err := connectionPath()
	if err != nil {
		return nil, ErrRegistry
	}
	config := os.Getenv("XDG_CONFIG_HOME")
	if !filepath.IsAbs(config) {
		config = filepath.Dir(filepath.Dir(path))
	}
	var registry struct {
		Plugins []Entry `json:"plugins"`
	}
	err = readJSON(filepath.Join(config, "magpie", "plugins.json"), 4<<20, &registry)
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, ErrRegistry
	}
	var entries []Entry
	for _, entry := range registry.Plugins {
		resource := filepath.Dir(entry.Spec)
		contents := filepath.Dir(resource)
		if filepath.IsAbs(entry.Spec) && filepath.Base(entry.Spec) == AgentFile &&
			filepath.Base(resource) == "Resources" && filepath.Base(contents) == "Contents" &&
			filepath.Ext(filepath.Dir(contents)) == ".app" {
			entries = append(entries, entry)
		}
	}
	return entries, nil
}

// Load reads the current local model and address for each operation. An app that
// has never been connected to Magpie can use its configured local port. Once
// the plugin takes over, a disconnect stops that route until reconnected.
func Load(fallbackPort int) (Config, error) {
	cfg := Config{Port: fallbackPort}
	path, err := connectionPath()
	if err != nil {
		return cfg, err
	}
	var connection struct {
		BaseURL   string `json:"baseURL"`
		LegacyKey string `json:"gatewayKey"`
		Model     string `json:"model"`
	}
	fileErr := readJSON(path, 16<<10, &connection)
	if fileErr != nil && !errors.Is(fileErr, os.ErrNotExist) {
		return cfg, ErrConfig
	}
	entries, err := Registered()
	if err != nil {
		return cfg, err
	}
	if len(entries) == 0 && errors.Is(fileErr, os.ErrNotExist) {
		return cfg, nil
	}
	// Previous plug-ins wrote Magpie's public loopback identifier to this
	// field. A user-supplied credential may carry distinct access limits.
	if connection.LegacyKey != "" && connection.LegacyKey != LoopbackIdentity {
		return cfg, ErrCustomKey
	}
	if connection.BaseURL == "" && connection.Model == "" {
		return cfg, ErrDisconnected
	}
	enabled := false
	for _, entry := range entries {
		if st, e := os.Stat(entry.Spec); !entry.Off && e == nil && st.Mode().IsRegular() {
			enabled = true
			break
		}
	}
	if !enabled {
		return cfg, ErrDisconnected
	}
	port, err := localPort(connection.BaseURL)
	if err != nil || !oneValue(connection.Model, 512) {
		return cfg, ErrConfig
	}
	return Config{Port: port, Model: connection.Model, Connected: true}, nil
}

func oneValue(value string, max int) bool {
	return value != "" && len(value) <= max && strings.IndexFunc(value, func(r rune) bool {
		return unicode.IsSpace(r) || unicode.IsControl(r)
	}) == -1
}

// A connected caller always dials 127.0.0.1 at this port, including when the
// settings use localhost. Reject paths and authorities that change the route.
func localPort(base string) (int, error) {
	u, err := url.Parse(base)
	if err != nil || u.Scheme != "http" || u.User != nil || u.Fragment != "" ||
		u.ForceQuery || u.RawQuery != "" || u.RawPath != "" ||
		(u.Path != "/v1" && u.Path != "/v1/") ||
		(u.Hostname() != "127.0.0.1" && !strings.EqualFold(u.Hostname(), "localhost")) {
		return 0, ErrConfig
	}
	port, err := strconv.Atoi(u.Port())
	if err != nil || port < 1 || port > 65535 {
		return 0, ErrConfig
	}
	return port, nil
}

func readJSON(path string, max int64, out any) error {
	f, err := os.Open(path)
	if err != nil {
		return err
	}
	defer f.Close()
	body, err := io.ReadAll(io.LimitReader(f, max+1))
	if err != nil {
		return err
	}
	if int64(len(body)) > max {
		return ErrConfig
	}
	return json.Unmarshal(body, out)
}
