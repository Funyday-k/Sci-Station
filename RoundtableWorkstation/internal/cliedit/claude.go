package cliedit

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"syscall"
	"time"

	"scistation.local/desktop/internal/workspace"
)

const claudeSettings = `{"disableAllHooks":true,"autoMemoryEnabled":false,"permissions":{"ask":["Read","Edit"]}}`

func claudeCommand(ctx context.Context, path string) *exec.Cmd {
	cmd := newCommand(ctx, path, "--restricted", "--print", "--verbose", "--no-session-persistence",
		"--input-format", "stream-json", "--output-format", "stream-json",
		"--permission-mode", "manual", "--permission-prompts", "host", "--permission-prompt-tool", "stdio",
		"--tools", "Read,Edit", "--strict-mcp-config", "--disable-slash-commands", "--settings", claudeSettings)
	// The CLI owns account authentication. Never inherit provider, shell,
	// plugin, worker, or permission overrides from the workstation process.
	cmd.Env = []string{"PATH=/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin", "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1", "CLAUDE_CODE_DISABLE_AUTO_MEMORY=1"}
	for _, k := range []string{"HOME", "TMPDIR", "USER", "LOGNAME", "LANG"} {
		if v := os.Getenv(k); v != "" {
			cmd.Env = append(cmd.Env, k+"="+v)
		}
	}
	return cmd
}

type claudeBlock struct {
	Type      string `json:"type"`
	ID        string `json:"id"`
	Name      string `json:"name"`
	ToolUseID string `json:"tool_use_id"`
	IsError   bool   `json:"is_error"`
}

type claudePacket struct {
	Type, Subtype, Cwd string
	SessionID          string `json:"session_id"`
	RequestID          string `json:"request_id"`
	Parent             string `json:"parent_tool_use_id"`
	PermissionMode     string `json:"permissionMode"`
	Tools              []string
	MCP                []json.RawMessage `json:"mcp_servers"`
	Directories        []string          `json:"additional_directories"`
	Plugins            []struct{ Path string }
	Message            struct {
		ID      string
		Content []claudeBlock
	}
	Response struct {
		Subtype string
		ID      string `json:"request_id"`
		Info    struct {
			Version string `json:"claude_code_version"`
			Mode    string `json:"current_permission_mode"`
		} `json:"response"`
	}
	Request struct {
		Subtype string
		Name    string `json:"tool_name"`
		ID      string `json:"tool_use_id"`
		Input   json.RawMessage
		Rule    struct {
			Source string
			Name   string `json:"tool_name"`
		} `json:"matched_ask_rule"`
	}
}

type claudePipe struct {
	scan *bufio.Scanner
	send *json.Encoder
}

func withClaude(cmd *exec.Cmd, fn func(claudePipe) error) error {
	input, err := cmd.StdinPipe()
	if err != nil {
		return err
	}
	output, err := cmd.StdoutPipe()
	if err != nil {
		return err
	}
	cmd.Stderr = io.Discard
	if err = cmd.Start(); err != nil {
		return errors.New("无法启动 Claude Code")
	}
	defer func() { _ = input.Close(); _ = cmd.Cancel(); _ = cmd.Wait() }()
	scan := bufio.NewScanner(output)
	scan.Buffer(make([]byte, 4096), 4<<20)
	c := claudePipe{scan, json.NewEncoder(input)}
	if err := c.send.Encode(map[string]any{"type": "control_request", "request_id": "initialize", "request": map[string]string{"subtype": "initialize"}}); err != nil {
		return err
	}
	for scan.Scan() {
		var p claudePacket
		if err := json.Unmarshal(scan.Bytes(), &p); err != nil {
			return errors.New("Claude Code 初始化协议无效")
		}
		if p.Type == "system" && p.Subtype == "ui_invalidate" {
			continue
		}
		if p.Type != "control_response" || p.Response.ID != "initialize" || p.Response.Subtype != "success" ||
			p.Response.Info.Version == "" || !manualMode(p.Response.Info.Mode) {
			return errors.New("Claude Code 未确认人工文件审批模式")
		}
		return fn(c)
	}
	return errors.New("Claude Code 未完成文件审批协议握手")
}

func manualMode(mode string) bool { return mode == "default" || mode == "manual" }

func ClaudeAvailable(executable string) (bool, string) {
	if !filepath.IsAbs(executable) {
		return false, "未找到 Claude Code"
	}
	ctx, cancel := context.WithTimeout(context.Background(), 4*time.Second)
	defer cancel()
	tmp, err := os.MkdirTemp("", "sci-claude-probe-")
	if err != nil {
		return false, "无法准备 Claude Code 协议探测"
	}
	defer os.RemoveAll(tmp)
	cmd := claudeCommand(ctx, executable)
	cmd.Dir = tmp
	cmd.Env = []string{"HOME=" + tmp, "PATH=/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin", "CLAUDE_CONFIG_DIR=" + filepath.Join(tmp, "config"), "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1"}
	cmd.Args = append(cmd.Args, "--bare")
	if err := withClaude(cmd, func(claudePipe) error { return nil }); err != nil {
		return false, err.Error()
	}
	return true, "支持受限模式下的单次文件编辑审批，运行时使用 Claude Code 自身的登录"
}

// RunClaude delegates one edit to the installed CLI. The workstation only reads
// the selected file for its preview and verifies the bytes after the CLI's reply.
func RunClaude(ctx context.Context, executable string, scope Scope, sink Sink) error {
	dir, err := workspace.Validate(scope.Directory)
	if err != nil {
		return err
	}
	cmd := claudeCommand(ctx, executable)
	cmd.Dir = dir
	return runClaudeCommand(ctx, cmd, scope, sink)
}

func runClaudeCommand(ctx context.Context, cmd *exec.Cmd, scope Scope, sink Sink) error {
	files, err := json.Marshal(scope.Paths)
	if err != nil {
		return err
	}
	prompt := fmt.Sprintf("%s\n\nSelected files relative to the project: %s\nUse Read and propose one exact Edit to an existing selected file. The user reviews this edit before it runs.", scope.Prompt, files)
	return withClaude(cmd, func(c claudePipe) error {
		if err := c.send.Encode(map[string]any{"type": "user", "session_id": "", "parent_tool_use_id": nil, "message": map[string]string{"role": "user", "content": prompt}}); err != nil {
			return err
		}
		return c.review(ctx, scope, sink)
	})
}

type claudeEdit struct {
	toolID, path, before, after string
	accepted                    bool
}

func (c claudePipe) review(ctx context.Context, scope Scope, sink Sink) error {
	var session, turn, tool, toolName string
	var reviewed *claudeEdit
	for c.scan.Scan() {
		var p claudePacket
		if err := json.Unmarshal(c.scan.Bytes(), &p); err != nil {
			return errors.New("Claude Code 输出无效")
		}
		if p.Type == "system" && p.Subtype == "ui_invalidate" {
			continue
		}
		if session == "" {
			if p.Type != "system" || p.Subtype != "init" || !p.validSession(scope.Directory) {
				return errors.New("Claude Code 工具、项目目录或权限超出本次范围")
			}
			session = p.SessionID
			continue
		}
		if p.SessionID != "" && p.SessionID != session || p.Parent != "" {
			return errors.New("Claude Code 会话标识改变")
		}
		switch p.Type {
		case "assistant":
			if p.SessionID != session {
				return errors.New("Claude Code 缺少会话标识")
			}
			for _, block := range p.Message.Content {
				if block.Type != "tool_use" {
					continue
				}
				if (block.Name != "Read" && block.Name != "Edit") || block.ID == "" || p.Message.ID == "" || tool != "" {
					return errors.New("Claude Code 请求了其他工具或并行操作")
				}
				turn, tool, toolName = p.Message.ID, block.ID, block.Name
			}
		case "control_request":
			if p.Request.Subtype != "can_use_tool" || p.Request.ID == "" || p.Request.ID != tool || p.Request.Name != toolName || p.RequestID == "" || reviewed != nil {
				return errors.New("Claude Code 文件请求与回合不匹配")
			}
			tool = ""
			decision := map[string]any{"behavior": "deny", "message": "The file or action is outside this review."}
			path, file, err := selectedClaudeFile(scope, p.Request.Input)
			if err == nil {
				switch p.Request.Name {
				case "Read":
					decision = map[string]any{"behavior": "allow", "updatedInput": p.Request.Input}
				case "Edit":
					if p.Request.Rule.Source != "flagSettings" || p.Request.Rule.Name != "Edit" {
						return errors.New("Claude Code 未使用本次逐项审批规则")
					}
					edit, request, err := claudeProposal(p, session, turn, path, file)
					if err != nil {
						return err
					}
					if err = sink.Running(session, turn); err != nil {
						return err
					}
					edit.accepted, err = sink.Approval(ctx, request)
					if err != nil {
						return err
					}
					reviewed = &edit
					if edit.accepted {
						_, current, err := selectedClaudeFile(scope, p.Request.Input)
						if err != nil || current.Version != file.Version {
							return errors.New("文件在审批期间发生变化")
						}
						decision = map[string]any{"behavior": "allow", "updatedInput": p.Request.Input}
					}
				}
			}
			if err := ctx.Err(); err != nil {
				return err
			}
			if err := c.send.Encode(map[string]any{"type": "control_response", "response": map[string]any{"subtype": "success", "request_id": p.RequestID, "response": decision}}); err != nil {
				return err
			}
		case "user":
			if reviewed == nil || p.SessionID != session {
				continue
			}
			for _, block := range p.Message.Content {
				if block.Type != "tool_result" || block.ToolUseID != reviewed.toolID {
					continue
				}
				want := reviewed.before
				if reviewed.accepted {
					want = reviewed.after
				}
				f, err := workspace.Read(scope.Directory, reviewed.path)
				if err != nil || f.Text != want || reviewed.accepted && block.IsError {
					return errors.New("Claude Code 的文件结果与审核内容不一致")
				}
				if reviewed.accepted {
					sink.Result("Claude Code 已写入经批准的编辑并核对文件内容")
				} else {
					sink.Result("已拒绝 Claude Code 编辑，原文件内容已核对")
				}
				return nil
			}
		case "result":
			return errors.New("Claude Code 未完成可核实的文件编辑；请检查 CLI 登录、模型与所选文件")
		}
	}
	return errors.New("Claude Code 在报告文件结果前结束")
}

func (p claudePacket) validSession(dir string) bool {
	if p.SessionID == "" || p.Cwd != dir || !manualMode(p.PermissionMode) || len(p.MCP) != 0 || len(p.Directories) != 0 || len(p.Tools) != 2 || !slices.Contains(p.Tools, "Read") || !slices.Contains(p.Tools, "Edit") {
		return false
	}
	for _, p := range p.Plugins {
		if p.Path != "builtin" {
			return false
		}
	}
	return true
}

func selectedClaudeFile(scope Scope, raw json.RawMessage) (string, workspace.File, error) {
	var in struct {
		Path string `json:"file_path"`
	}
	err := json.Unmarshal(raw, &in)
	bad := errors.New("Claude Code 请求的文件不在授权范围内")
	if err != nil || !filepath.IsAbs(in.Path) || filepath.Clean(in.Path) != in.Path {
		return "", workspace.File{}, bad
	}
	rel, err := filepath.Rel(scope.Directory, in.Path)
	if err != nil || !slices.Contains(scope.Paths, rel) {
		return "", workspace.File{}, bad
	}
	info, err := os.Lstat(in.Path)
	if err != nil || !info.Mode().IsRegular() {
		return "", workspace.File{}, bad
	}
	stat, ok := info.Sys().(*syscall.Stat_t)
	if !ok || stat.Nlink != 1 {
		return "", workspace.File{}, bad
	}
	f, err := workspace.Read(scope.Directory, rel)
	if err != nil || f.Version == workspace.MissingVersion {
		return "", workspace.File{}, bad
	}
	return rel, f, nil
}

func claudeProposal(p claudePacket, session, turn, path string, file workspace.File) (claudeEdit, Request, error) {
	var in struct {
		Path string  `json:"file_path"`
		Old  string  `json:"old_string"`
		New  *string `json:"new_string"`
		All  bool    `json:"replace_all"`
	}
	decoder := json.NewDecoder(strings.NewReader(string(p.Request.Input)))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&in); err != nil || in.Old == "" || in.New == nil || *in.New == in.Old {
		return claudeEdit{}, Request{}, errors.New("Claude Code 编辑缺少可核对的原文或替换文本")
	}
	// CLI Edit matches LF text and writes using the existing file's newline
	// convention. Avoid an approval for ambiguous mixed line endings.
	old, replacement := in.Old, *in.New
	if strings.ContainsAny(old+replacement, "\r") {
		return claudeEdit{}, Request{}, errors.New("Claude Code 替换文本需要使用 LF 换行")
	}
	if strings.ContainsRune(file.Text, '\r') {
		lines := strings.ReplaceAll(file.Text, "\r\n", "")
		if strings.ContainsAny(lines, "\r\n") {
			return claudeEdit{}, Request{}, errors.New("Claude Code 无法准确预览混合换行符的文件")
		}
		old = strings.ReplaceAll(old, "\n", "\r\n")
		replacement = strings.ReplaceAll(replacement, "\n", "\r\n")
	}
	count := strings.Count(file.Text, old)
	if count == 0 || !in.All && count != 1 {
		return claudeEdit{}, Request{}, errors.New("Claude Code 编辑未在所选文件中找到确切匹配")
	}
	if difference := len(replacement) - len(old); difference > 0 && count > (workspace.MaxFileBytes-len(file.Text))/difference {
		return claudeEdit{}, Request{}, errors.New("编辑后的文件超过大小限制")
	}
	after := strings.ReplaceAll(file.Text, old, replacement)
	diff, err := workspace.PreviewDiff(path, file.Text, after)
	if err != nil {
		return claudeEdit{}, Request{}, err
	}
	edit := claudeEdit{toolID: p.Request.ID, path: path, before: file.Text, after: after}
	return edit, Request{RequestID: p.RequestID, ThreadID: session, TurnID: turn, ItemID: p.Request.ID, Reason: "Claude Code requests one text replacement", Changes: []Change{{Path: path, Kind: "update", Diff: diff}}}, nil
}
