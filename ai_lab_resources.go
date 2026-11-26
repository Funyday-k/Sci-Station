package main

import (
	"bufio"
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime"
	"net/http"
	"net/url"
	"strings"
	"time"

	"scistation.local/desktop/internal/research"
)

type labResource struct {
	URI  string `json:"uri"`
	Name string `json:"name"`
	MIME string `json:"mimeType"`
}
type labRPC struct {
	target  string
	client  *http.Client
	version string
	session string
}
type labRPCMessage struct {
	ID      int             `json:"id"`
	Version string          `json:"jsonrpc"`
	Result  json.RawMessage `json:"result"`
	Error   *struct {
		Message string `json:"message"`
	} `json:"error"`
}

func labEndpoint(value string) bool {
	u, err := url.Parse(value)
	return err == nil && len(value) <= 2048 && u.Scheme == "https" && u.Hostname() != "" && u.User == nil && u.RawQuery == "" && u.Fragment == "" && (u.Port() == "" || u.Port() == "443")
}
func (m *labRPC) call(ctx context.Context, method string, id int, params any, out any) error {
	msg := map[string]any{"jsonrpc": "2.0", "method": method}
	if id > 0 {
		msg["id"] = id
	}
	if params != nil {
		msg["params"] = params
	}
	body, e := json.Marshal(msg)
	if e != nil {
		return e
	}
	req, e := http.NewRequestWithContext(ctx, "POST", m.target, bytes.NewReader(body))
	if e != nil {
		return e
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json, text/event-stream")
	if m.version != "" {
		req.Header.Set("MCP-Protocol-Version", m.version)
	}
	if m.session != "" {
		req.Header.Set("Mcp-Session-Id", m.session)
	}
	res, e := m.client.Do(req)
	if e != nil {
		return errors.New("无法连接公共 MCP 服务")
	}
	defer res.Body.Close()
	if res.StatusCode < 200 || res.StatusCode > 299 {
		return fmt.Errorf("MCP 服务返回 HTTP %d", res.StatusCode)
	}
	if method == "initialize" {
		sid := res.Header.Get("Mcp-Session-Id")
		if len(sid) > 1024 {
			return errors.New("MCP 会话标识无效")
		}
		m.session = sid
	}
	if id == 0 {
		return nil
	}
	const limit = 1 << 20
	r := io.LimitReader(res.Body, limit+1)
	validate := func(data []byte) (bool, error) {
		var env labRPCMessage
		if json.Unmarshal(data, &env) != nil {
			return false, errors.New("MCP 消息不是有效 JSON")
		}
		if env.ID != id {
			return false, nil
		}
		if env.Version != "2.0" || env.Error != nil {
			return false, errors.New("MCP 服务未完成请求")
		}
		if e := json.Unmarshal(env.Result, out); e != nil {
			return false, errors.New("MCP 返回格式无效")
		}
		return true, nil
	}
	mt, _, _ := mime.ParseMediaType(res.Header.Get("Content-Type"))
	if mt == "text/event-stream" {
		scan := bufio.NewScanner(r)
		scan.Buffer(make([]byte, 4096), limit)
		var event []string
		for scan.Scan() {
			line := scan.Text()
			if strings.HasPrefix(line, "data:") {
				event = append(event, strings.TrimSpace(line[5:]))
			} else if line == "" && len(event) > 0 {
				ok, e := validate([]byte(strings.Join(event, "\n")))
				if e != nil || ok {
					return e
				}
				event = nil
			}
		}
		return errors.New("MCP 响应超限或未完成")
	}
	data, e := io.ReadAll(r)
	if e != nil || len(data) > limit {
		return errors.New("MCP 响应过大")
	}
	ok, e := validate(data)
	if e != nil {
		return e
	}
	if !ok {
		return errors.New("MCP 响应编号不匹配")
	}
	return nil
}
func labReadResources(ctx context.Context, client *http.Client, endpoint, uri string) (any, error) {
	m := labRPC{target: endpoint, client: client}
	var init struct {
		Version      string `json:"protocolVersion"`
		Capabilities struct {
			Resources *struct{} `json:"resources"`
		} `json:"capabilities"`
	}
	if e := m.call(ctx, "initialize", 1, map[string]any{"protocolVersion": "2025-06-18", "capabilities": map[string]any{}, "clientInfo": map[string]string{"name": "Sci-Station", "version": "1.0"}}, &init); e != nil {
		return nil, e
	}
	if init.Version != "2025-06-18" && init.Version != "2025-03-26" {
		return nil, errors.New("不支持对端的 MCP 协议版本")
	}
	m.version = init.Version
	if init.Capabilities.Resources == nil {
		return nil, errors.New("此服务未开放资源读取")
	}
	if e := m.call(ctx, "notifications/initialized", 0, nil, nil); e != nil {
		return nil, e
	}
	if m.session != "" {
		defer func() {
			endCtx, cancel := context.WithTimeout(context.Background(), time.Second)
			defer cancel()
			req, err := http.NewRequestWithContext(endCtx, "DELETE", endpoint, nil)
			if err == nil {
				req.Header.Set("Mcp-Session-Id", m.session)
				req.Header.Set("MCP-Protocol-Version", m.version)
				if resp, e := client.Do(req); e == nil {
					resp.Body.Close()
				}
			}
		}()
	}
	index := []labResource{}
	cursor := ""
	for page := 0; page < 4; page++ {
		var out struct {
			Resources []labResource `json:"resources"`
			Next      string        `json:"nextCursor"`
		}
		params := map[string]string{}
		if cursor != "" {
			params["cursor"] = cursor
		}
		if e := m.call(ctx, "resources/list", 2+page, params, &out); e != nil {
			return nil, e
		}
		for _, entry := range out.Resources {
			if entry.URI != "" && len(entry.URI) <= 2048 && len(entry.Name) <= 512 {
				index = append(index, entry)
				if len(index) >= 128 {
					break
				}
			}
		}
		if len(index) >= 128 || out.Next == "" || out.Next == cursor {
			break
		}
		cursor = out.Next
	}
	if uri == "" {
		return index, nil
	}
	found := false
	for _, entry := range index {
		if entry.URI == uri {
			found = true
			break
		}
	}
	if !found {
		return nil, errors.New("该资源不在当前目录")
	}
	var out struct {
		Contents []struct {
			URI  string `json:"uri"`
			Text string `json:"text"`
		} `json:"contents"`
	}
	if e := m.call(ctx, "resources/read", 9, map[string]string{"uri": uri}, &out); e != nil {
		return nil, e
	}
	for _, item := range out.Contents {
		if item.URI == uri && strings.TrimSpace(item.Text) != "" {
			if len(item.Text) > 60<<10 {
				return nil, errors.New("此资源超过 60 KiB 文本预览上限")
			}
			sum := sha256.Sum256([]byte(item.Text))
			return map[string]string{"uri": uri, "server": endpoint, "sha256": hex.EncodeToString(sum[:]), "text": item.Text}, nil
		}
	}
	return nil, errors.New("此资源没有可预览的文字")
}
func (a *apiServer) serveLabResources(w http.ResponseWriter, r *http.Request, path string, client *http.Client) {
	if r.Method != "POST" {
		reject(w, 405, "请从实验室读取资源")
		return
	}
	var input struct {
		Endpoint  string `json:"endpoint"`
		URI       string `json:"uri"`
		ProjectID string `json:"projectId"`
		Scope     string `json:"scope"`
		Revision  int    `json:"revision"`
		Confirmed bool   `json:"confirmed"`
	}
	if !jsonBody(w, r, &input) {
		return
	}
	if !labEndpoint(input.Endpoint) || path == "resources/read" && (input.URI == "" || len(input.URI) > 2048) || path == "resources/list" && input.URI != "" {
		reject(w, 400, "请输入公开 HTTPS MCP 地址，地址不应包含查询参数或凭据")
		return
	}
	if !input.Confirmed {
		reject(w, 403, "访问公共资源前请明确确认")
		return
	}
	lab, ok := a.research.(*research.Service)
	if !ok {
		reject(w, 503, "未打开科研工作区")
		return
	}
	if input.Scope == "global" && input.ProjectID == "" {
		if !checkLabModule(w, lab, "") {
			return
		}
	} else {
		if input.Scope != "" {
			reject(w, 400, "无效的实验室资源范围")
			return
		}
		if !checkLabProject(w, lab, input.ProjectID) {
			return
		}
		config, err := lab.LabSettings(input.ProjectID)
		if err != nil {
			labContextError(w, err)
			return
		}
		if config.Revision != input.Revision {
			labContextError(w, research.ErrLabSettingsConflict)
			return
		}
		if !config.MCPEnabled || input.Endpoint != config.Endpoint {
			reject(w, 403, "请先确认并启用此项目的公开 MCP 服务")
			return
		}
	}
	ctx, cancel := context.WithTimeout(r.Context(), 18*time.Second)
	defer cancel()
	res, e := labReadResources(ctx, client, input.Endpoint, input.URI)
	if e != nil {
		reject(w, 422, e.Error())
		return
	}
	reply(w, 200, res)
}
