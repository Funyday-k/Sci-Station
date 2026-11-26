package desktop

import (
	"context"
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"

	"scistation.local/desktop/internal/cli"
	"scistation.local/desktop/internal/cliedit"
)

type cliEditProvider struct {
	ID        string `json:"id"`
	Label     string `json:"label"`
	Available bool   `json:"available"`
	Reason    string `json:"reason,omitempty"`
	path      string
	run       cliedit.Adapter
}
type cliEditAPI struct {
	windowMu    sync.RWMutex
	windowProof string
	jobs        cliedit.Manager
	mu          sync.Mutex
	providers   map[string]cachedEditProvider
	lookup      func(context.Context, string) cliEditProvider // nil in packaged builds
}
type cachedEditProvider struct {
	info     os.FileInfo
	provider cliEditProvider
}

func (a *apiServer) editProvider(ctx context.Context, id string) cliEditProvider {
	if a.cliEdits.lookup != nil {
		return a.cliEdits.lookup(ctx, id)
	}
	label := map[string]string{"codex": "Codex", "cursor": "Cursor", "claude": "Claude Code"}[id]
	p := cliEditProvider{ID: id, Label: label, Reason: "未找到可验证的本机 CLI"}
	if label == "" {
		return p
	}
	home, dirs, overrides := a.clientInventorySources()
	inventory := detectClientsBy(home, dirs, overrides, cli.Discover, installedCLIIdentity)
	for _, record := range inventory {
		if record.ID == id && record.Installed && record.State == "installed" {
			p.path, _ = filepath.EvalSymlinks(record.Path)
			break
		}
	}
	if p.path == "" {
		return p
	}
	info, err := os.Stat(p.path)
	if err != nil {
		return p
	}
	a.cliEdits.mu.Lock()
	defer a.cliEdits.mu.Unlock()
	cached, ok := a.cliEdits.providers[id]
	if ok && p.path == cached.provider.path && os.SameFile(cached.info, info) && cached.info.ModTime() == info.ModTime() && cached.info.Size() == info.Size() {
		return cached.provider
	}
	switch id {
	case "codex":
		if err := cliedit.ProbeCodex(ctx, p.path); err != nil {
			p.Reason = "本机 Codex 未协商文件审批协议"
		} else {
			p.Available = true
			p.Reason = ""
			p.run = cliedit.RunCodex
		}
	case "cursor":
		p.Available, p.Reason = cliedit.CursorAvailable(p.path)
	case "claude":
		p.Available, p.Reason = cliedit.ClaudeAvailable(p.path)
		if p.Available {
			p.run = cliedit.RunClaude
		}
	}
	if a.cliEdits.providers == nil {
		a.cliEdits.providers = map[string]cachedEditProvider{}
	}
	if ctx.Err() == nil {
		a.cliEdits.providers[id] = cachedEditProvider{info, p}
	}
	return p
}

type cliEditAction struct {
	Action       string   `json:"action"`
	ProjectID    string   `json:"projectId"`
	Provider     string   `json:"provider"`
	MeetingRound *int     `json:"meetingRound"`
	Prompt       string   `json:"prompt"`
	Paths        []string `json:"paths"`
	RunID        string   `json:"runId"`
	ThreadID     string   `json:"threadId"`
	TurnID       string   `json:"turnId"`
	ItemID       string   `json:"itemId"`
	RequestID    string   `json:"requestId"`
}

func (a *apiServer) checkEditScope(scope cliedit.Scope) error {
	s, err := a.meetings.Get(scope.MeetingID)
	if err != nil || s.ProjectID != scope.ProjectID || s.Project != scope.Directory || s.Status == "closed" || s.Status == "running" || len(s.Rounds) != scope.MeetingRound {
		return errors.New("会议、项目或回合已经改变")
	}
	return a.meetings.WithProjectDirectory(s, func(path string) error {
		if path != scope.Directory {
			return errors.New("项目目录已改变")
		}
		return nil
	})
}
func (a *apiServer) serveCLIEdits(w http.ResponseWriter, r *http.Request, id string) {
	if !a.authorizedCLIEditWindow(r) {
		reject(w, 403, "请在当前 Sci-Station 桌面会议窗口审核 CLI 文件编辑")
		return
	}
	if a.meetings == nil {
		reject(w, 503, "会议未启动")
		return
	}
	if r.Method != "GET" && r.Method != "POST" {
		reject(w, 405, "不支持该方法")
		return
	}
	s, err := a.meetings.Get(id)
	if err != nil {
		fail(w, err)
		return
	}
	var state *cliedit.State
	run := a.cliEdits.jobs.Get(id)
	if r.Method == "POST" {
		var in cliEditAction
		if !jsonBody(w, r, &in) {
			return
		}
		if s.ProjectID == "" || s.ProjectID != in.ProjectID {
			reject(w, 403, "此会议没有所选项目的编辑范围")
			return
		}
		switch in.Action {
		case "start":
			prompt := strings.TrimSpace(in.Prompt)
			if in.MeetingRound == nil || *in.MeetingRound != len(s.Rounds) || prompt == "" || len(prompt) > 16<<10 || len(in.Paths) == 0 || len(in.Paths) > 24 {
				reject(w, 400, "请指定当前会议轮次、编辑指令与 1–24 个项目文件")
				return
			}
			p := a.editProvider(r.Context(), in.Provider)
			if !p.Available || p.run == nil {
				reject(w, 409, "该 CLI 无可用的文件审批适配器")
				return
			}
			run, err = a.cliEdits.jobs.Start(cliedit.Scope{ProjectID: s.ProjectID, MeetingID: id, MeetingRound: *in.MeetingRound, Directory: s.Project, Prompt: prompt, Paths: in.Paths}, in.Provider, p.path, p.run, a.checkEditScope)
		case "accept", "decline", "cancel":
			if run == nil || run.Snapshot().ID != in.RunID {
				reject(w, 409, "CLI 运行已失效")
				return
			}
			if in.Action == "cancel" {
				run.Stop()
			} else {
				err = run.Decide(in.ThreadID, in.TurnID, in.ItemID, in.RequestID, in.Action == "accept")
			}
		default:
			reject(w, 400, "未知的 CLI 编辑操作")
			return
		}
		if err != nil {
			reject(w, 409, err.Error())
			return
		}
	}
	if run != nil {
		current := run.Snapshot()
		state = &current
	}
	providers := []cliEditProvider{}
	for _, provider := range []string{"codex", "cursor", "claude"} {
		providers = append(providers, a.editProvider(r.Context(), provider))
	}
	reply(w, 200, map[string]any{"providers": providers, "run": state})
}
