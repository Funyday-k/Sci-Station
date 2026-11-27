// Package cliedit forwards native CLI review requests for one explicitly
// started edit. Only the CLI applies a file change.
package cliedit

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"sync"
	"syscall"
	"time"

	"scistation.local/desktop/internal/workspace"
)

type Scope struct {
	ProjectID, MeetingID, Directory, Prompt string
	MeetingRound                            int
	Paths                                   []string
}
type Change struct {
	Path string `json:"path"`
	Kind string `json:"kind"`
	Diff string `json:"diff"`
}
type Request struct {
	RequestID string   `json:"requestId"`
	ThreadID  string   `json:"threadId"`
	TurnID    string   `json:"turnId"`
	ItemID    string   `json:"itemId"`
	Reason    string   `json:"reason,omitempty"`
	Changes   []Change `json:"changes"`
}
type Sink interface {
	Running(threadID, turnID string) error
	Approval(context.Context, Request) (bool, error)
	Result(detail string)
}
type Adapter func(context.Context, string, Scope, Sink) error
type State struct {
	Prompt       string   `json:"prompt"`
	ID           string   `json:"id"`
	ProjectID    string   `json:"projectId"`
	MeetingID    string   `json:"meetingId"`
	MeetingRound int      `json:"meetingRound"`
	Provider     string   `json:"provider"`
	ThreadID     string   `json:"threadId,omitempty"`
	TurnID       string   `json:"turnId,omitempty"`
	Status       string   `json:"status"`
	Detail       string   `json:"detail,omitempty"`
	Pending      *Request `json:"pending,omitempty"`
	Paths        []string `json:"paths"`
}
type Guard func(Scope) error
type Run struct {
	mu       sync.Mutex
	scope    Scope
	state    State
	cancel   context.CancelFunc
	check    Guard
	reply    chan bool
	seen     map[string]bool
	versions map[string]string
	done     chan struct{}
}
type Manager struct {
	// Coordinate admitting CLI processes with a project history reset.
	admission sync.RWMutex
	mu        sync.Mutex
	runs      map[string]*Run
	closed    bool
}

func key() string { var b [16]byte; rand.Read(b[:]); return hex.EncodeToString(b[:]) }
func newCommand(ctx context.Context, executable string, args ...string) *exec.Cmd {
	cmd := exec.CommandContext(ctx, executable, args...)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error { return syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL) }
	cmd.WaitDelay = time.Second
	return cmd
}

// CLI editors can write in place. A hard link could therefore change a
// different name outside the selected project, even when its path is valid.
func selectedFile(dir, path string) (workspace.File, error) {
	f, err := workspace.Read(dir, path)
	if err != nil {
		return f, err
	}
	info, err := os.Lstat(filepath.Join(dir, path))
	if f.Version == workspace.MissingVersion && errors.Is(err, os.ErrNotExist) {
		return f, nil
	}
	if err != nil || !info.Mode().IsRegular() {
		return f, errors.New("所选文件已改变")
	}
	stat, ok := info.Sys().(*syscall.Stat_t)
	if !ok || stat.Nlink != 1 {
		return f, errors.New("不支持编辑具有其他硬链接的文件")
	}
	return f, nil
}
func (m *Manager) Start(scope Scope, provider, executable string, adapter Adapter, guard Guard) (*Run, error) {
	m.admission.RLock()
	defer m.admission.RUnlock()
	if err := guard(scope); err != nil {
		return nil, err
	}
	directory, err := os.Lstat(scope.Directory)
	if err != nil || !directory.IsDir() {
		return nil, errors.New("项目目录不可用")
	}
	check := func(current Scope) error {
		if err := guard(current); err != nil {
			return err
		}
		info, err := os.Lstat(current.Directory)
		if err != nil || !os.SameFile(directory, info) {
			return errors.New("项目目录已被替换，请重新发起编辑")
		}
		return nil
	}
	versions := map[string]string{}
	for _, path := range scope.Paths {
		file, err := selectedFile(scope.Directory, path)
		if err != nil {
			return nil, err
		}
		if _, ok := versions[path]; ok {
			return nil, errors.New("编辑范围包含重复文件")
		}
		versions[path] = file.Version
	}
	if len(versions) == 0 || len(versions) > 24 {
		return nil, errors.New("请选择 1–24 个项目文本文件")
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.closed {
		return nil, errors.New("工作区正在关闭")
	}
	if old := m.runs[scope.MeetingID]; old != nil {
		select {
		case <-old.done:
		default:
			return nil, errors.New("此会议已有运行中的 CLI 编辑")
		}
	}
	if m.runs == nil {
		m.runs = map[string]*Run{}
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Minute)
	r := &Run{scope: scope, cancel: cancel, check: check, seen: map[string]bool{}, versions: versions, done: make(chan struct{}), state: State{Prompt: scope.Prompt, ID: key(), ProjectID: scope.ProjectID, MeetingID: scope.MeetingID, MeetingRound: scope.MeetingRound, Provider: provider, Paths: slices.Clone(scope.Paths), Status: "starting"}}
	m.runs[scope.MeetingID] = r
	go func() {
		defer close(r.done)
		defer cancel()
		err := adapter(ctx, executable, scope, r)
		r.mu.Lock()
		defer r.mu.Unlock()
		r.state.Pending = nil
		r.reply = nil
		if r.state.Status == "cancelled" {
			return
		}
		switch {
		case ctx.Err() != nil:
			r.state.Status = "cancelled"
			r.state.Detail = "CLI 编辑已中止，请核对文件现状"
		case err != nil:
			r.state.Status = "failed"
			r.state.Detail = err.Error()
		default:
			r.state.Status = "completed"
		}
	}()
	return r, nil
}
func (m *Manager) Get(meeting string) *Run { m.mu.Lock(); defer m.mu.Unlock(); return m.runs[meeting] }
func (m *Manager) Close(ctx context.Context) {
	m.mu.Lock()
	m.closed = true
	jobs := []*Run{}
	for _, r := range m.runs {
		jobs = append(jobs, r)
	}
	m.mu.Unlock()
	for _, r := range jobs {
		r.Stop()
	}
	for _, r := range jobs {
		select {
		case <-r.done:
		case <-ctx.Done():
			return
		}
	}
}
func (r *Run) Snapshot() State {
	r.mu.Lock()
	defer r.mu.Unlock()
	v := r.state
	if v.Pending != nil {
		p := *v.Pending
		p.Changes = slices.Clone(p.Changes)
		v.Pending = &p
	}
	return v
}
func (r *Run) Stop() {
	r.mu.Lock()
	defer r.mu.Unlock()
	switch r.state.Status {
	case "completed", "failed", "cancelled":
		return
	}
	r.state.Status = "cancelled"
	r.state.Detail = "已停止 CLI 进程，未决审批已失效"
	r.state.Pending = nil
	r.reply = nil
	r.cancel()
}
func (r *Run) Running(thread, turn string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	if thread == "" || turn == "" || r.state.Status != "starting" {
		return errors.New("CLI 回合标识无效")
	}
	r.state.ThreadID = thread
	r.state.TurnID = turn
	r.state.Status = "running"
	return nil
}
func (r *Run) Result(detail string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.state.Status != "cancelled" {
		r.state.Detail = detail
	}
}
func (r *Run) checkPaths(changes []Change) error {
	if len(changes) == 0 || len(changes) > len(r.versions) {
		return errors.New("CLI 提交的文件范围无效")
	}
	used := map[string]bool{}
	size := 0
	for _, c := range changes {
		base, ok := r.versions[c.Path]
		if !ok || used[c.Path] || c.Diff == "" || !(c.Kind == "add" || c.Kind == "update" || c.Kind == "delete") {
			return errors.New("CLI 的路径或变更不在所选范围内")
		}
		used[c.Path] = true
		size += len(c.Diff)
		if size > 2<<20 {
			return errors.New("CLI 变更过大，无法完整审核")
		}
		f, err := selectedFile(r.scope.Directory, c.Path)
		if err != nil || f.Version != base {
			return fmt.Errorf("文件 %s 的版本已经改变，请重新发起编辑", c.Path)
		}
	}
	return nil
}
func (r *Run) Approval(ctx context.Context, req Request) (bool, error) {
	if err := r.check(r.scope); err != nil {
		return false, err
	}
	if err := r.checkPaths(req.Changes); err != nil {
		return false, err
	}
	r.mu.Lock()
	if req.RequestID == "" || req.ItemID == "" || req.ThreadID != r.state.ThreadID || req.TurnID != r.state.TurnID || r.state.Status != "running" || r.seen[req.RequestID] {
		r.mu.Unlock()
		return false, errors.New("CLI 审核与运行中的回合不匹配")
	}
	r.seen[req.RequestID] = true
	response := make(chan bool, 1)
	r.reply = response
	r.state.Pending = &req
	r.state.Status = "pending"
	r.mu.Unlock()
	select {
	case <-ctx.Done():
		return false, ctx.Err()
	case accepted := <-response:
		if ctx.Err() != nil {
			return false, ctx.Err()
		}
		if accepted {
			if err := r.check(r.scope); err != nil {
				return false, err
			}
			if err := r.checkPaths(req.Changes); err != nil {
				return false, err
			}
		}
		return accepted, nil
	}
}
func (r *Run) Decide(thread, turn, item, id string, accept bool) error {
	stale := errors.New("CLI 审批已失效或与当前回合不匹配")
	r.mu.Lock()
	p := r.state.Pending
	r.mu.Unlock()
	if p == nil || p.RequestID != id || p.ItemID != item || p.ThreadID != thread || p.TurnID != turn {
		return stale
	}
	// Scope and file reads can block on an external directory. Do not hold
	// the run mutex: a root switch or process exit must still cancel the CLI.
	var err error
	if accept {
		if err = r.check(r.scope); err == nil {
			err = r.checkPaths(p.Changes)
		}
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.state.Pending != p || r.state.Status != "pending" {
		return stale
	}
	r.state.Pending = nil
	if err != nil {
		r.state.Status = "cancelled"
		r.state.Detail = err.Error()
		r.reply = nil
		r.cancel()
		return err
	}
	r.state.Status = "responded"
	if accept {
		r.state.Detail = "已选择本次允许，等待 CLI 的文件结果"
	} else {
		r.state.Detail = "已选择拒绝，等待 CLI 返回结果"
	}
	r.reply <- accept
	r.reply = nil
	return nil
}

func (m *Manager) Busy() bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	for _, r := range m.runs {
		select {
		case <-r.done:
		default:
			return true
		}
	}
	return false
}

// ResetProject refuses to invalidate a running adapter's directory. Completed
// CLI transcripts are in memory and belong to the old project conversations.
func (m *Manager) ResetProject(id string, reset func() error) error {
	m.admission.Lock()
	defer m.admission.Unlock()
	m.mu.Lock()
	for _, r := range m.runs {
		if r.scope.ProjectID != id {
			continue
		}
		select {
		case <-r.done:
		default:
			m.mu.Unlock()
			return fmt.Errorf("%w: 请等待此项目的 CLI 编辑结束或取消后重试", workspace.ErrConflict)
		}
	}
	m.mu.Unlock()
	if err := reset(); err != nil {
		return err
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	for meeting, r := range m.runs {
		if r.scope.ProjectID == id {
			delete(m.runs, meeting)
		}
	}
	return nil
}
