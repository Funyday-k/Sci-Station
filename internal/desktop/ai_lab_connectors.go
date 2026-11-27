package desktop

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net/http"
	"regexp"
	"slices"
	"strings"
	"sync"
	"time"
	"unicode"

	"scistation.local/desktop/internal/credentials"
	"scistation.local/desktop/internal/research"
)

type labConnectorAccess struct {
	modelAudit researchRetryState
	key        func(string, string) credentials.Store
	mu         sync.Mutex
	pending    map[string]labConnectorTicket
}
type labConnectorTicket struct {
	digest  string
	owner   string
	expires time.Time
}
type labConnectorRequest struct {
	ProjectID  string                 `json:"projectId"`
	Revision   int                    `json:"revision"`
	ID         string                 `json:"id"`
	Connection *research.LabConnector `json:"connection,omitempty"`
	Confirmed  bool                   `json:"confirmed,omitempty"`
	Token      string                 `json:"token,omitempty"`
	Action     string                 `json:"action,omitempty"`
	Target     string                 `json:"target,omitempty"`
	Definition string                 `json:"definition,omitempty"`
	Arguments  map[string]any         `json:"arguments,omitempty"`
	Ticket     string                 `json:"ticket,omitempty"`
}

var labConnectorID = regexp.MustCompile(`^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,63}$`)
var bearerToken = regexp.MustCompile(`^[A-Za-z0-9._~+/-]+=*$`)
var noConnector = errors.New("科研连接不存在或设置已改变")

func labDigest(b []byte) string  { sum := sha256.Sum256(b); return hex.EncodeToString(sum[:]) }
func labJSONDigest(v any) string { b, _ := json.Marshal(v); return labDigest(b) }
func (a *labConnectorAccess) store(project string, c research.LabConnector, kind string) credentials.Store {
	if a.key == nil {
		return nil
	}
	endpoint := c.Endpoint
	if kind == "trust" {
		endpoint = ""
	}
	return a.key("research-mcp/"+project+"/"+c.ID+"/"+kind, endpoint)
}

// Invalidate queued reads when credentials change, even at the same endpoint.
func rotateResearchGrant(store credentials.Store, c research.LabConnector) error {
	current, err := store.Resolve()
	if err != nil {
		return err
	}
	if strings.HasPrefix(current, labJSONDigest(c)+":") {
		return store.Save(labJSONDigest(c) + ":" + rand.Text())
	}
	return nil
}

// Keep a saved secret reachable if the metadata update fails.
func connectorKeyCanDetach(w http.ResponseWriter, store credentials.Store) bool {
	configured, err := store.Configured()
	if err != nil {
		reject(w, 503, minerCredentialUnavailable)
		return false
	}
	if configured {
		reject(w, 409, "请先清除此连接的令牌，再更换地址、停用鉴权或移除连接")
		return false
	}
	return true
}
func connectorIndex(config research.LabSettings, id string) int {
	return slices.IndexFunc(config.Connections, func(c research.LabConnector) bool { return c.ID == id })
}
func unsafeConnectorText(text string) bool {
	return strings.IndexFunc(text, func(r rune) bool { return unicode.IsControl(r) || unicode.Is(unicode.Cf, r) }) >= 0
}
func cleanLabConnector(c research.LabConnector) (research.LabConnector, error) {
	c.ProgramHash, c.ScriptHash = "", ""
	if !labConnectorID.MatchString(c.ID) || len(c.Tools) > 64 || len(c.Arguments) > 24 {
		return c, errors.New("连接名称、工具名单或启动参数无效")
	}
	for _, tool := range c.Tools {
		if !labConnectorID.MatchString(tool) {
			return c, errors.New("工具名单需要逐项填写有效名称")
		}
	}
	for _, s := range append(slices.Clone(c.Arguments), c.ID, c.Endpoint, c.Program) {
		if unsafeConnectorText(s) || len(s) > 2048 || credentials.ContainsSecret(s) {
			return c, errors.New("连接信息含有无效字符或疑似凭据。请使用钥匙串保存令牌")
		}
	}
	switch c.Transport {
	case "https":
		if !labEndpoint(c.Endpoint) || c.Program != "" || len(c.Arguments) != 0 {
			return c, errors.New("远程连接需要不含查询参数及凭据的公开 HTTPS 服务地址")
		}
	case "stdio":
		if c.Endpoint != "" || c.Bearer {
			return c, errors.New("本机 stdio 连接不接受远程地址或令牌")
		}
		if err := inspectLabProgram(&c); err != nil {
			return c, err
		}
	default:
		return c, errors.New("请选择 HTTPS 或本机 stdio 连接")
	}
	return c, nil
}
func (a *labConnectorAccess) grant(project string, c research.LabConnector) (string, error) {
	if !c.Enabled {
		return "", errors.New("请先启用项目科研连接")
	}
	store := a.store(project, c, "trust")
	if store == nil {
		return "", errors.New("无法访问连接信任记录")
	}
	value, err := store.Resolve()
	if err != nil || !strings.HasPrefix(value, labJSONDigest(c)+":") {
		return "", errors.New("请在桌面端核对并信任此连接版本")
	}
	return value, nil
}
func (a *labConnectorAccess) ticket(owner, digest string) string {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.pending == nil {
		a.pending = make(map[string]labConnectorTicket)
	}
	now := time.Now()
	for k, item := range a.pending {
		if !now.Before(item.expires) {
			delete(a.pending, k)
		}
	}
	if len(a.pending) >= 128 {
		return ""
	}
	id := rand.Text()
	a.pending[id] = labConnectorTicket{digest, owner, now.Add(2 * time.Minute)}
	return id
}
func (a *labConnectorAccess) consume(id, digest string) bool {
	a.mu.Lock()
	defer a.mu.Unlock()
	item, ok := a.pending[id]
	delete(a.pending, id)
	return ok && item.digest == digest && time.Now().Before(item.expires)
}
func connectorActionSummary(in labConnectorRequest, c research.LabConnector) (string, error) {
	if in.Connection != nil || in.Token != "" {
		return "", errors.New("科研操作仅接受已保存的连接")
	}
	var detail string
	switch in.Action {
	case "resources/list", "tools/list":
		if in.Target != "" || in.Definition != "" || in.Arguments != nil {
			return "", errors.New("目录查询参数无效")
		}
		detail = map[string]string{"resources/list": "列出资料", "tools/list": "列出已允许的只读工具"}[in.Action]
	case "resources/read":
		if in.Target == "" || len(in.Target) > 2048 || unsafeConnectorText(in.Target) || in.Definition != "" || in.Arguments != nil {
			return "", errors.New("资料标识无效")
		}
		detail = "读取资料 " + in.Target
	case "tools/call":
		if !slices.Contains(c.Tools, in.Target) || !labReadToolName(in.Target) || len(in.Definition) != 64 || in.Arguments == nil {
			return "", errors.New("请选择已允许且声明为只读的工具，并填写 JSON 对象参数")
		}
		args, _ := json.Marshal(in.Arguments)
		if len(args) > 8192 || credentials.ContainsSecret(string(args)) {
			return "", errors.New("工具参数超限或疑似含有凭据")
		}
		detail = "调用只读工具 " + in.Target + "\n参数 " + string(args)
	default:
		return "", errors.New("科研连接只允许列出、读取资料或调用所选只读工具")
	}
	destination := c.Endpoint
	if c.Transport == "stdio" {
		args, _ := json.Marshal(c.Arguments)
		destination = c.Program + " " + string(args) + "\n程序 SHA-256 " + c.ProgramHash
	}
	return detail + "\n连接 " + c.ID + "\n" + destination, nil
}

func (a *apiServer) serveLabConnector(w http.ResponseWriter, r *http.Request, path string, client *http.Client) {
	if r.Method != http.MethodPost {
		reject(w, 405, "请使用实验室科研连接操作")
		return
	}
	if !a.desktop || a.minerCreds == nil || a.minerCreds.labProof == "" || subtle.ConstantTimeCompare([]byte(r.Header.Get("X-Sci-Station-Connector-Session")), []byte(a.minerCreds.labProof)) != 1 || a.labConnect.key == nil {
		reject(w, 403, "请从 Sci-Station 桌面实验室管理和使用科研连接")
		return
	}
	var in labConnectorRequest
	if !jsonBody(w, r, &in) {
		return
	}
	lab := a.research
	if lab == nil {
		reject(w, 503, "未打开科研工作区")
		return
	}
	if !checkLabProject(w, lab, in.ProjectID) {
		return
	}
	// Serialize settings and Keychain changes across views. Protocol exchanges
	// run outside this lock and recheck the project grant before the selected read.
	if path != "prepare" && path != "execute" {
		a.labConnect.mu.Lock()
		defer a.labConnect.mu.Unlock()
	}
	config, err := lab.LabSettings(in.ProjectID)
	if err != nil {
		labContextError(w, err)
		return
	}
	view := func(config research.LabSettings) labContextResponse {
		out := labContextSummary(config)
		out.Connections = config.Connections
		return out
	}
	if path == "index" {
		reply(w, 200, view(config))
		return
	}
	if config.Revision != in.Revision {
		labContextError(w, research.ErrLabSettingsConflict)
		return
	}
	if path != "status" && path != "prepare" && path != "execute" && in.Confirmed {
		for k, t := range a.labConnect.pending {
			if t.owner == in.ProjectID+"/"+in.ID {
				delete(a.labConnect.pending, k)
			}
		}
	}
	index := connectorIndex(config, in.ID)
	var conn research.LabConnector
	if index >= 0 {
		conn = config.Connections[index]
	}
	if path == "save" {
		if !in.Confirmed || in.Connection == nil || in.Connection.ID != in.ID || in.Token != "" {
			reject(w, 403, "请确认保存的连接配置")
			return
		}
		c, err := cleanLabConnector(*in.Connection)
		if err != nil {
			labContextError(w, err)
			return
		}
		if index < 0 && len(config.Connections) >= 16 {
			reject(w, 422, "项目最多可配置 16 个科研连接")
			return
		}
		if index >= 0 && (conn.Endpoint != c.Endpoint || conn.Bearer && !c.Bearer) {
			if !connectorKeyCanDetach(w, a.labConnect.store(in.ProjectID, conn, "bearer")) {
				return
			}
		}
		result, err := lab.EditLabSettings(in.ProjectID, in.Revision, func(config *research.LabSettings) error {
			if index < 0 {
				config.Connections = append(config.Connections, c)
			} else {
				config.Connections[index] = c
			}
			return nil
		})
		if err != nil {
			labContextError(w, err)
			return
		}
		reply(w, 200, view(result))
		return
	}
	if index < 0 {
		reject(w, 404, noConnector.Error())
		return
	}
	trust := a.labConnect.store(in.ProjectID, conn, "trust")
	bearer := a.labConnect.store(in.ProjectID, conn, "bearer")
	switch path {
	case "status":
		trusted, e := trust.Resolve()
		if e != nil {
			reject(w, 503, minerCredentialUnavailable)
			return
		}
		configured := false
		if conn.Bearer {
			configured, e = bearer.Configured()
			if e != nil {
				reject(w, 503, minerCredentialUnavailable)
				return
			}
		}
		reply(w, 200, map[string]bool{"trusted": strings.HasPrefix(trusted, labJSONDigest(conn)+":"), "configured": configured})
		return
	case "trust", "untrust", "set-token", "clear-token", "remove":
		if !in.Confirmed {
			reject(w, 403, "请确认此项目连接操作")
			return
		}
		switch path {
		case "trust":
			if !conn.Enabled {
				reject(w, 409, "请先启用此连接")
				return
			}
			validated, err := cleanLabConnector(conn)
			if err != nil || labJSONDigest(validated) != labJSONDigest(conn) {
				reject(w, 409, "配置或本机程序已改变，请重新保存后复核")
				return
			}
			err = trust.Save(labJSONDigest(conn) + ":" + rand.Text())
			if err != nil {
				reject(w, 503, minerCredentialUnavailable)
				return
			}
		case "untrust":
			err = trust.Delete()
		case "set-token":
			if conn.Transport != "https" || !conn.Bearer || (!validStoredToken(in.Token) || !bearerToken.MatchString(in.Token)) {
				reject(w, 422, "此远程连接需要有效的 Bearer 令牌")
				return
			}
			err = rotateResearchGrant(trust, conn)
			if err == nil {
				err = bearer.Save(in.Token)
			}
		case "clear-token":
			err = rotateResearchGrant(trust, conn)
			if err == nil {
				err = bearer.Delete()
			}
		case "remove":
			if !connectorKeyCanDetach(w, bearer) {
				return
			}
			err = trust.Delete()
			if err == nil {
				result, e := lab.EditLabSettings(in.ProjectID, in.Revision, func(config *research.LabSettings) error {
					config.Connections = slices.Delete(config.Connections, index, index+1)
					return nil
				})
				if e != nil {
					labContextError(w, e)
					return
				}
				reply(w, 200, view(result))
				return
			}
		}
		if err != nil {
			reject(w, 503, minerCredentialUnavailable)
			return
		}
		reply(w, 200, map[string]bool{"ok": true})
		return
	case "prepare", "execute":
	default:
		reject(w, 404, "未知的连接操作")
		return
	}
	grant, check, err := a.checkResearchConnection(lab, in.ProjectID, "", in.Revision, conn)
	if err != nil {
		reject(w, 403, err.Error())
		return
	}
	summary, err := connectorActionSummary(in, conn)
	if err != nil {
		reject(w, 422, err.Error())
		return
	}
	ticket := in.Ticket
	in.Ticket = ""
	confirmed := in.Confirmed
	in.Confirmed = false
	digest := labJSONDigest([]any{in, conn, grant})
	if path == "prepare" {
		ticket = a.labConnect.ticket(in.ProjectID+"/"+in.ID, digest)
		if ticket == "" {
			reject(w, 429, "待确认操作过多，请稍后重试")
			return
		}
		reply(w, 200, map[string]string{"ticket": ticket, "summary": summary})
		return
	}
	if !confirmed || !a.labConnect.consume(ticket, digest) {
		reject(w, 403, "本次操作尚未批准、已执行或已过期")
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 18*time.Second)
	defer cancel()
	result, err := a.runLabConnector(ctx, client, in, conn, check)
	if err != nil {
		reject(w, 422, err.Error())
		return
	}
	if err = check(); err != nil {
		reject(w, 409, err.Error())
		return
	}
	receipt := map[string]string{"projectId": in.ProjectID, "connection": conn.ID, "configHash": labJSONDigest(conn), "operation": in.Action, "target": in.Target, "argumentsHash": labJSONDigest(in.Arguments), "id": labDigest([]byte(ticket)), "time": time.Now().UTC().Format(time.RFC3339)}
	reply(w, 200, map[string]any{"data": result, "receipt": receipt})
}
