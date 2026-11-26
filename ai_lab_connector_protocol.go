package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"slices"
	"strings"

	"scistation.local/desktop/internal/credentials"
	"scistation.local/desktop/internal/research"
)

// Explicit trust and a user allowlist are required even when the service
// declares a tool read-only. General command and file-mutation interfaces
// are not research tools and cannot be enabled by their read-only annotation.
func labReadToolName(name string) bool {
	if !labConnectorID.MatchString(name) {
		return false
	}
	tokens := strings.FieldsFunc(strings.ToLower(name), func(r rune) bool { return r == '-' || r == '_' || r == '.' })
	for _, token := range tokens {
		switch token {
		case "exec", "execute", "shell", "bash", "powershell", "terminal", "command", "write", "patch", "delete", "edit", "overwrite", "remove", "rename":
			return false
		}
	}
	return true
}

func (a *apiServer) runLabConnector(ctx context.Context, client *http.Client, in labConnectorRequest, c research.LabConnector, check func() error) (any, error) {
	if err := check(); err != nil {
		return nil, err
	}
	m := labRPC{target: c.Endpoint, client: client}
	switch c.Transport {
	case "https":
		if !labEndpoint(c.Endpoint) {
			return nil, errors.New("保存的远程 MCP 地址无效")
		}
		if c.Bearer {
			value, err := a.labConnect.store(in.ProjectID, c, "bearer").Resolve()
			if err != nil || (!validStoredToken(value) || !bearerToken.MatchString(value)) {
				return nil, errors.New("请在钥匙串中设置此连接的令牌")
			}
			m.bearer = value
		}
	case "stdio":
		stdio, err := startLabStdio(ctx, c)
		if err != nil {
			return nil, err
		}
		m.local = stdio
		m.target = "MCP · " + c.ID
	default:
		return nil, noConnector
	}
	defer m.close()
	caps, err := m.initialize(ctx)
	if err != nil {
		return nil, err
	}
	var result any
	if strings.HasPrefix(in.Action, "resources/") {
		if caps.Resources == nil {
			return nil, errors.New("此连接未提供资料目录")
		}
		result, err = m.resources(ctx, in.Target, check)
	} else {
		if caps.Tools == nil {
			return nil, errors.New("此连接未提供工具目录")
		}
		result, err = m.readOnlyTools(ctx, c, in, check)
	}
	if err != nil {
		return nil, err
	}
	data, _ := json.Marshal(result)
	if m.bearer != "" && strings.Contains(string(data), m.bearer) || credentials.ContainsSecret(string(data)) {
		return nil, errors.New("返回内容疑似包含凭据，已停止预览")
	}
	return result, nil
}

type labMCPTool struct {
	Name        string          `json:"name"`
	Description string          `json:"description"`
	Schema      json.RawMessage `json:"inputSchema"`
	Annotations struct {
		ReadOnly    bool `json:"readOnlyHint"`
		Destructive bool `json:"destructiveHint"`
	} `json:"annotations"`
}
type labToolView struct {
	Name        string          `json:"name"`
	Description string          `json:"description"`
	Schema      json.RawMessage `json:"inputSchema"`
	Definition  string          `json:"definition"`
}

func (m *labRPC) readOnlyTools(ctx context.Context, c research.LabConnector, in labConnectorRequest, check func() error) (any, error) {
	rows := []labToolView{}
	seen := map[string]bool{}
	cursor := ""
	for page := 0; page < 4; page++ {
		var out struct {
			Tools []labMCPTool `json:"tools"`
			Next  string       `json:"nextCursor"`
		}
		params := map[string]string{}
		if cursor != "" {
			params["cursor"] = cursor
		}
		if err := m.call(ctx, "tools/list", 2+page, params, &out); err != nil {
			return nil, err
		}
		for _, tool := range out.Tools {
			if seen[tool.Name] {
				return nil, errors.New("工具目录包含重复名称，请检查科研服务")
			}
			seen[tool.Name] = true
			if !labReadToolName(tool.Name) || !tool.Annotations.ReadOnly || tool.Annotations.Destructive || !slices.Contains(c.Tools, tool.Name) || len(tool.Schema) > 12<<10 || len(tool.Description) > 2048 {
				continue
			}
			var schema struct {
				Type string `json:"type"`
			}
			if json.Unmarshal(tool.Schema, &schema) != nil || schema.Type != "object" {
				continue
			}
			rows = append(rows, labToolView{tool.Name, tool.Description, tool.Schema, labJSONDigest(tool)})
			if len(rows) >= 128 {
				break
			}
		}
		if len(rows) >= 128 || out.Next == "" || out.Next == cursor {
			break
		}
		cursor = out.Next
	}
	if in.Action == "tools/list" {
		return rows, nil
	}
	allowed := slices.ContainsFunc(rows, func(t labToolView) bool { return t.Name == in.Target && t.Definition == in.Definition })
	if !allowed {
		return nil, errors.New("该工具的只读声明、参数定义或允许名单已改变，请重新列出工具")
	}
	if err := check(); err != nil {
		return nil, err
	}
	var out struct {
		IsError bool `json:"isError"`
		Content []struct {
			Type string `json:"type"`
			Text string `json:"text"`
		} `json:"content"`
	}
	if err := m.call(ctx, "tools/call", 9, map[string]any{"name": in.Target, "arguments": in.Arguments}, &out); err != nil {
		return nil, err
	}
	if out.IsError {
		return nil, errors.New("只读工具未完成请求")
	}
	var pieces []string
	for _, item := range out.Content {
		if item.Type == "text" && item.Text != "" {
			pieces = append(pieces, item.Text)
		}
	}
	text := strings.Join(pieces, "\n")
	if len(text) > 60<<10 || strings.TrimSpace(text) == "" {
		return nil, errors.New("只读工具未返回可预览的文本，或文本超过 60 KiB")
	}
	return map[string]string{"uri": fmt.Sprintf("mcp-tool:%s/%s", c.ID, in.Target), "server": m.target, "sha256": labDigest([]byte(text)), "text": text}, nil
}
