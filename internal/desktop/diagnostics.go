package desktop

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"scistation.local/desktop/internal/cli"
	"scistation.local/desktop/internal/magpieconfig"
)

// diagnosticStore belongs to one apiServer. Its zero value is ready to use.
// GET never runs commands or sends requests, including on an empty cache.
type diagnosticStore struct {
	mu   sync.Mutex
	busy bool
	last diagnosticResult
}

type diagnosticSource struct {
	State          string   `json:"state"`
	Title          string   `json:"title"`
	Detail         string   `json:"detail"`
	CheckedAt      string   `json:"checked_at,omitempty"`
	Version        string   `json:"version,omitempty"`
	Transport      string   `json:"transport,omitempty"`
	Model          string   `json:"model,omitempty"`
	LoginState     string   `json:"login_state,omitempty"`
	AuthMethod     string   `json:"auth_method,omitempty"`
	Port           int      `json:"port,omitempty"`
	ModelsCount    int      `json:"models_count,omitempty"`
	Models         []string `json:"models,omitempty"`
	ModelAvailable *bool    `json:"model_available,omitempty"`
	configKey      string
}

type diagnosticResult struct {
	CheckedAt string                      `json:"checked_at"`
	Sources   map[string]diagnosticSource `json:"sources"`
	Preview   bool                        `json:"preview"`
}

func diagnosticConfigKey(name string, p preferences) string {
	values := []any{p.CLIPaths[name], p.Models[name]}
	if name == "magpie" {
		values = []any{p.MagpiePort, p.Models["codex"]}
	}
	if name == "codex" {
		values = append(values, p.CodexTransport)
		if p.CodexTransport == "magpie" {
			values = append(values, p.MagpiePort)
		}
	}
	b, _ := json.Marshal(values)
	return string(b)
}

func (d *diagnosticStore) snapshot(p preferences) diagnosticResult {
	d.mu.Lock()
	defer d.mu.Unlock()
	out := diagnosticResult{CheckedAt: d.last.CheckedAt, Preview: d.last.Preview, Sources: map[string]diagnosticSource{}}
	for _, name := range []string{"magpie", "codex", "cursor"} {
		if s, ok := d.last.Sources[name]; ok {
			if s.configKey != "" && s.configKey != diagnosticConfigKey(name, p) {
				s = diagnosticSource{State: "unchecked", Title: "设置已变化，尚未重检", Detail: "上次检测针对不同端口、模型、程序路径或接入方式；请刷新，旧结果不代表当前连接。", CheckedAt: s.CheckedAt}
			}
			out.Sources[name] = s
		} else {
			out.Sources[name] = diagnosticSource{State: "unchecked", Title: "尚未检测", Detail: "只显示已主动检测的结果；刷新后检查连接与登录，不发送模型请求。"}
		}
	}
	return out
}

type diagnosticRequest struct {
	Target         string            `json:"target"`
	MagpiePort     *int              `json:"magpie_port"`
	CodexTransport *string           `json:"codex_transport"`
	Models         map[string]string `json:"models"`
	CLIPaths       map[string]string `json:"cli_paths"`
}

func diagnosticRequestAllowed(w http.ResponseWriter, r *http.Request) bool {
	host, port, err := net.SplitHostPort(r.Host)
	number, _ := strconv.Atoi(port)
	if err != nil || (host != "127.0.0.1" && host != "localhost") || number < 1 || number > 65535 {
		reject(w, 403, "请通过本机圆桌地址检测")
		return false
	}
	if r.Method != http.MethodGet && r.Method != http.MethodPost {
		reject(w, 405, "仅支持读取或刷新检测")
		return false
	}
	if r.Method == http.MethodPost {
		origin := r.Header.Get("Origin")
		if r.Header.Get("X-Roundtable") != "1" || (origin != "" && origin != "http://"+r.Host) ||
			r.Header.Get("Sec-Fetch-Site") == "cross-site" ||
			strings.ToLower(strings.TrimSpace(strings.Split(r.Header.Get("Content-Type"), ";")[0])) != "application/json" {
			reject(w, 403, "请从本机圆桌刷新检测")
			return false
		}
	}
	return true
}

func (a *apiServer) diagnostics(w http.ResponseWriter, r *http.Request) {
	if !diagnosticRequestAllowed(w, r) {
		return
	}
	w.Header().Set("Cache-Control", "no-store")
	if r.Method == http.MethodGet {
		reply(w, 200, a.diag.snapshot(a.prefs.get()))
		return
	}
	var request *diagnosticRequest
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, 64<<10))
	dec.DisallowUnknownFields()
	if err := dec.Decode(&request); err != nil || request == nil {
		reject(w, 400, "检测参数须为单个有效 JSON 对象")
		return
	}
	var extra any
	if dec.Decode(&extra) != io.EOF {
		reject(w, 400, "检测参数须为单个 JSON 对象")
		return
	}
	if request.Target == "" {
		request.Target = "all"
	}
	if request.Target != "all" && request.Target != "magpie" && request.Target != "codex" && request.Target != "cursor" {
		reject(w, 400, "未知检测目标")
		return
	}
	encoded, _ := json.Marshal(a.prefs.get())
	var p preferences
	_ = json.Unmarshal(encoded, &p) // Detach immutable preference maps before preview patches.
	preview := request.MagpiePort != nil || request.CodexTransport != nil || request.Models != nil || request.CLIPaths != nil
	if request.MagpiePort != nil {
		p.MagpiePort = *request.MagpiePort
	}
	if request.CodexTransport != nil {
		p.CodexTransport = *request.CodexTransport
	}
	if p.Models == nil {
		p.Models = map[string]string{}
	}
	if p.CLIPaths == nil {
		p.CLIPaths = map[string]string{}
	}
	for seat, model := range request.Models {
		p.Models[seat] = model
	}
	for seat, path := range request.CLIPaths {
		p.CLIPaths[seat] = path
	}
	if err := validatePrefs(p, false); err != nil {
		reject(w, 400, "检测设置的端口、接入方式或模型标识无效")
		return
	}
	for seat, path := range p.CLIPaths {
		if path == "" {
			continue
		}
		base := filepath.Base(path)
		if len(path) > 4096 || !filepath.IsAbs(path) ||
			(seat == "codex" && base != "codex") ||
			(seat == "cursor" && base != "agent" && base != "cursor-agent") {
			reject(w, 400, "检测 CLI 路径须为官方程序名的绝对路径")
			return
		}
	}
	a.diag.mu.Lock()
	if a.diag.busy {
		a.diag.mu.Unlock()
		reject(w, 409, "已有连接检测正在运行")
		return
	}
	a.diag.busy = true
	a.diag.mu.Unlock()
	defer func() { a.diag.mu.Lock(); a.diag.busy = false; a.diag.mu.Unlock() }()
	ctx, cancel := context.WithTimeout(r.Context(), 18*time.Second)
	defer cancel()
	result := a.diag.snapshot(p)
	result.Preview = preview
	result.CheckedAt = time.Now().UTC().Format(time.RFC3339Nano)
	selected := map[string]diagnosticSource{}
	needMagpie := request.Target == "all" || request.Target == "magpie" || (request.Target == "codex" && p.CodexTransport == "magpie")
	var gateway diagnosticSource
	if needMagpie {
		gateway = diagnoseMagpie(ctx, p.MagpiePort, p.Models["codex"])
		selected["magpie"] = gateway
	}
	var wg sync.WaitGroup
	var codex, cursor diagnosticSource
	if request.Target == "all" || request.Target == "codex" {
		wg.Add(1)
		go func() { defer wg.Done(); codex = diagnoseCLI(ctx, "codex", p, gateway) }()
	}
	if request.Target == "all" || request.Target == "cursor" {
		wg.Add(1)
		go func() { defer wg.Done(); cursor = diagnoseCLI(ctx, "cursor", p, diagnosticSource{}) }()
	}
	wg.Wait()
	if request.Target == "all" || request.Target == "codex" {
		selected["codex"] = codex
	}
	if request.Target == "all" || request.Target == "cursor" {
		selected["cursor"] = cursor
	}
	if r.Context().Err() != nil {
		reject(w, 408, "检测已取消；保留上次结果")
		return
	}
	for name, source := range selected {
		source.CheckedAt = result.CheckedAt
		source.configKey = diagnosticConfigKey(name, p)
		result.Sources[name] = source
	}
	a.diag.mu.Lock()
	a.diag.last = result
	a.diag.mu.Unlock()
	reply(w, 200, result)
}

var diagnosticVersion = regexp.MustCompile(`(?m)^(?:(?:codex(?:-cli)?|Cursor Agent|cursor-agent|agent)[ :vV]*)?([0-9]+\.[0-9]+(?:\.[0-9]+)?(?:[-+][A-Za-z0-9.-]+)?)\s*$`)

func cleanDiagnosticVersion(raw string) string {
	if len(raw) > 1024 {
		return ""
	}
	match := diagnosticVersion.FindStringSubmatch(strings.TrimSpace(raw))
	if len(match) != 2 || len(match[1]) > 80 {
		return ""
	}
	return match[1]
}

func diagnosticHTTP(ctx context.Context, port int, path string, out any) error {
	client := http.Client{Timeout: 5 * time.Second, Transport: &http.Transport{Proxy: nil, DisableKeepAlives: true, DialContext: (&net.Dialer{Timeout: 2 * time.Second}).DialContext}, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, fmt.Sprintf("http://127.0.0.1:%d%s", port, path), nil)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+magpieconfig.LoopbackIdentity)
	req.Header.Set("User-Agent", "SciStation/2")
	res, err := client.Do(req)
	if err != nil {
		return err
	}
	defer res.Body.Close()
	if res.StatusCode != 200 {
		return errors.New("unexpected gateway status")
	}
	dec := json.NewDecoder(io.LimitReader(res.Body, (2<<20)+1))
	if err = dec.Decode(out); err != nil {
		return err
	}
	var extra any
	if dec.Decode(&extra) != io.EOF {
		return errors.New("invalid gateway JSON")
	}
	return nil
}

func diagnoseMagpie(ctx context.Context, port int, model string) diagnosticSource {
	s := diagnosticSource{State: "error", Title: "网关无法连接", Detail: "未能读取本机 Magpie 身份；请确认已启动且端口正确。未发送模型请求。", Port: port, Model: "codex/" + strings.TrimPrefix(model, "codex/")}
	var hello struct {
		Name    string `json:"name"`
		Version string `json:"version"`
	}
	if err := diagnosticHTTP(ctx, port, "/api/hello", &hello); err != nil {
		if ctx.Err() != nil {
			s.State, s.Title, s.Detail = "warning", "检测未完成", "检测已取消或超时，无法核实网关。"
		}
		return s
	}
	if hello.Name != "magpie" {
		s.Title, s.Detail = "端口服务不符", "该端口没有返回 Magpie 身份，未继续读取模型目录。"
		return s
	}
	s.Version = cleanDiagnosticVersion(hello.Version)
	var catalog struct {
		Data []struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	if err := diagnosticHTTP(ctx, port, "/v1/models", &catalog); err != nil {
		s.Title, s.Detail = "模型目录无法核实", "已确认 Magpie 身份，但未取得有效模型目录；未验证模型可用性。"
		return s
	}
	if catalog.Data == nil {
		s.State, s.Title, s.Detail = "warning", "网关已连接，目录待核实", "已确认 Magpie 身份，但模型目录未返回有效列表；尚不能核实所选模型。没有发送模型请求。"
		return s
	}
	if len(catalog.Data) > 10000 {
		s.Title, s.Detail = "模型目录无效", "网关目录过大，无法核实所选模型。"
		return s
	}
	seen := map[string]bool{}
	found := false
	invalidEntries := false
	for _, entry := range catalog.Data {
		// Magpie's catalog also contains routing-group names without a
		// provider slash. They are valid gateway IDs, not Codex suggestions.
		// Duplicate entries do not mean the gateway is disconnected.
		if strings.TrimSpace(entry.ID) == "" || len(entry.ID) > 500 || strings.ContainsFunc(entry.ID, func(r rune) bool { return r < 32 || r == 127 }) {
			invalidEntries = true
			continue
		}
		if seen[entry.ID] {
			continue
		}
		seen[entry.ID] = true
		if entry.ID == s.Model {
			found = true
		}
		if strings.HasPrefix(entry.ID, "codex/") {
			id := strings.TrimPrefix(entry.ID, "codex/")
			if id != "" && !strings.ContainsAny(id, "/ \t\r\n\x00") {
				s.Models = append(s.Models, entry.ID)
			}
		}
	}
	s.ModelsCount = len(seen)
	s.ModelAvailable = &found
	if !found {
		s.State, s.Title, s.Detail = "warning", "网关已连接，所选模型缺失", "已确认 Magpie 身份并读取目录，但没有当前 Codex 路径实际请求的模型标识；请检查账户源或选择本席型号。没有发送模型请求。"
		if len(catalog.Data) == 0 {
			s.Title, s.Detail = "网关已连接，目录为空", "已确认 Magpie 身份，当前目录没有可用模型；网关连接正常，所选 Codex 模型尚不可用。没有发送模型请求。"
		}
		if invalidEntries {
			s.Detail += " 目录中的无效条目已忽略；未将其视为网关离线。"
		}
		return s
	}
	s.State, s.Title, s.Detail = "ready", "网关与目录已检查", "已确认本机 Magpie 身份并在目录找到所选模型，可提交给网关路由；没有发送模型请求，未验证推理、额度或工具兼容性。"
	if s.Version == "" {
		s.State, s.Title, s.Detail = "warning", "目录已检查，版本未知", "Magpie 身份和所选模型目录已确认，但未能核实版本；没有发送模型请求。"
	}
	if invalidEntries {
		s.State, s.Title = "warning", "网关已连接，部分目录待核实"
		s.Detail += " 目录中的无效条目已忽略。"
	}
	return s
}

func diagnoseCLI(ctx context.Context, seat string, p preferences, gateway diagnosticSource) diagnosticSource {
	name := "Codex"
	if seat == "cursor" {
		name = "Cursor"
	}
	transport := "direct"
	if seat == "codex" {
		transport = p.CodexTransport
	}
	s := diagnosticSource{State: "error", Title: name + " 未安装", Detail: "未找到可执行的官方 CLI。", Transport: transport, Model: p.Models[seat], LoginState: "unknown"}
	info := cli.Discover(seat, p.CLIPaths[seat])
	if !info.Available {
		return s
	}
	version, versionErr := diagnosticCommand(ctx, seat, info.Path, "--version")
	if versionErr == nil {
		s.Version = cleanDiagnosticVersion(version)
	}
	args := []string{"login", "status"}
	if seat == "cursor" {
		args = []string{"status", "--format", "json"}
	}
	status, statusErr := diagnosticCommand(ctx, seat, info.Path, args...)
	if seat == "cursor" {
		var auth struct {
			Status          string `json:"status"`
			IsAuthenticated bool   `json:"isAuthenticated"`
			HasAccessToken  bool   `json:"hasAccessToken"`
			HasRefreshToken bool   `json:"hasRefreshToken"`
			Message         string `json:"message"`
		}
		if statusErr == nil && json.Unmarshal([]byte(status), &auth) == nil {
			switch auth.Status {
			case "authenticated":
				if auth.IsAuthenticated && auth.HasAccessToken && auth.HasRefreshToken {
					s.LoginState, s.AuthMethod = "logged_in", "account"
					s.State, s.Title, s.Detail = "ready", "Cursor 登录状态已检查", "官方 CLI 报告本机登录完整；没有发送模型请求，未验证所选模型、实时额度或推理。"
					if strings.Contains(strings.ToLower(auth.Message), "unable") || strings.Contains(strings.ToLower(auth.Message), "not available") {
						s.State, s.Title, s.Detail = "warning", "登录缓存存在，联网未核实", "官方 CLI 发现本机登录，但未能取得账户详情；不能确认实时连接。没有发送模型请求。"
					}
				}
			case "unauthenticated", "partially-authenticated":
				s.LoginState = "not_logged_in"
				s.State, s.Title, s.Detail = "error", "Cursor 未登录或登录不完整", "请在官方 Cursor CLI 登录；检测不会改用环境 API key，也不执行登录。"
			}
		}
	} else {
		text := strings.ToLower(status)
		switch {
		case strings.Contains(text, "not logged in"), strings.Contains(text, "not authenticated"), strings.Contains(text, "authentication required"):
			s.LoginState = "not_logged_in"
		case statusErr == nil && (strings.Contains(text, "api key configured") || strings.Contains(text, "logged in using api key")):
			s.LoginState, s.AuthMethod = "logged_in", "api_key"
		case statusErr == nil && strings.Contains(text, "logged in using chatgpt"):
			s.LoginState, s.AuthMethod = "logged_in", "chatgpt"
		case statusErr == nil && strings.Contains(text, "logged in using"):
			s.LoginState, s.AuthMethod = "logged_in", "account"
		}
		if transport == "magpie" {
			s.State, s.Title, s.Detail = gateway.State, "Codex 网关路径已检查", "已检查 CLI 与 Magpie 目录；此路径由 Magpie 管理账户，不依赖本机 Codex 登录。没有发送模型请求，未验证推理。"
			if gateway.State == "error" {
				s.Title, s.Detail = "Codex 网关路径受阻", "CLI 可执行，但 Magpie 身份、目录或所选模型未通过检查；不会改用直连。"
			}
			if gateway.State == "warning" {
				s.Title, s.Detail = "Codex 网关路径待核实", "CLI 可执行，但 Magpie 预检仍有未核实项；不会改用直连。"
			}
			if gateway.ModelAvailable != nil && !*gateway.ModelAvailable {
				s.State, s.Title, s.Detail = "error", "Codex 所选模型不可用", "Magpie 已连接，但目录中缺少本席当前请求的模型；网关在线不代表所选模型可用。不会改用直连。"
			}
		} else {
			switch s.LoginState {
			case "not_logged_in":
				s.State, s.Title, s.Detail = "error", "Codex 未登录", "请在官方 Codex CLI 登录；检测不会改用环境 API key，也不执行登录。"
			case "logged_in":
				s.State, s.Title, s.Detail = "ready", "Codex 登录状态已检查", "官方 CLI 报告已登录；没有发送模型请求，未验证直连网络、所选模型或额度。"
				if s.AuthMethod == "api_key" {
					s.State, s.Title, s.Detail = "warning", "Codex 当前为 API key 登录", "官方 CLI 报告其已保存身份为 API key；这不是已核实的 ChatGPT 订阅登录。请在官方客户端自行切换，检测不会退出账户。"
				}
			}
		}
	}
	if s.LoginState == "unknown" && !(seat == "codex" && transport == "magpie") {
		s.State, s.Title, s.Detail = "warning", name+" 登录无法核实", "官方状态命令未给出可确认的登录结果，或检查超时／取消。未返回厂商原始输出，也没有发送模型请求。"
	}
	if versionErr != nil || s.Version == "" {
		if s.State == "ready" {
			s.State = "warning"
		}
		if s.State != "error" {
			s.Title = name + " 版本待核实"
		}
		s.Detail += " CLI 版本命令未完成或格式无法识别。"
	}
	return s
}

type diagnosticBuffer struct {
	bytes.Buffer
	overflow bool
}

func (b *diagnosticBuffer) Write(p []byte) (int, error) {
	n := len(p)
	left := (64 << 10) - b.Len()
	if left < n {
		b.overflow = true
		if left > 0 {
			_, _ = b.Buffer.Write(p[:left])
		}
	} else {
		_, _ = b.Buffer.Write(p)
	}
	return n, nil
}

func diagnosticEnvironment(seat string) []string {
	home, _ := os.UserHomeDir()
	dirs := filepath.SplitList(os.Getenv("PATH"))
	if home != "" {
		dirs = append(dirs, filepath.Join(home, ".local", "bin"))
	}
	dirs = append(dirs, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin")
	env := []string{"PATH=" + strings.Join(dirs, string(os.PathListSeparator)), "NO_COLOR=1", "NO_OPEN_BROWSER=1"}

	// Status checks use the CLI's locally saved login. Inherit only runtime
	// settings and paths needed to find that login.
	keys := []string{"HOME", "CFFIXED_USER_HOME", "TMPDIR", "LANG", "LC_ALL", "LC_CTYPE", "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME"}
	switch seat {
	case "codex":
		keys = append(keys, "CODEX_HOME")
	case "cursor":
		keys = append(keys, "CURSOR_CONFIG_DIR")
	}
	for _, key := range keys {
		if value, ok := os.LookupEnv(key); ok {
			env = append(env, key+"="+value)
		}
	}
	return env
}

// Only --version, codex login status, and cursor status are supplied by callers.
// The user cannot supply command arguments; raw output stays in process memory.
func diagnosticCommand(parent context.Context, seat, executable string, args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(parent, 5*time.Second)
	defer cancel()
	if err := ctx.Err(); err != nil {
		return "", err
	}
	dir, err := os.MkdirTemp("", "roundtable-diagnostic-")
	if err != nil {
		return "", err
	}
	defer os.RemoveAll(dir)
	cmd := exec.Command(executable, args...)
	cmd.Dir = dir
	cmd.Env = diagnosticEnvironment(seat)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.WaitDelay = time.Second
	var out diagnosticBuffer
	cmd.Stdout = &out
	cmd.Stderr = &out // os/exec serializes copies to the same comparable writer.
	if err = cmd.Start(); err != nil {
		return "", err
	}
	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()
	select {
	case err = <-done:
	case <-ctx.Done():
		_ = syscall.Kill(-cmd.Process.Pid, syscall.SIGTERM)
		finished := false
		select {
		case <-done:
			finished = true
		case <-time.After(150 * time.Millisecond):
		}
		_ = syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
		// WaitDelay closes inherited output pipes when descendants keep them open.
		if !finished {
			select {
			case <-done:
			case <-time.After(1200 * time.Millisecond):
			}
		}
		return "", ctx.Err()
	}
	if out.overflow {
		return "", errors.New("diagnostic output exceeded limit")
	}
	return out.String(), err
}
