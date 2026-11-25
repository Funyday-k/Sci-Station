package meeting

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"testing"
	"time"
)

func TestTitleUsesFirstParentAndPreservesOriginalTask(t *testing.T) {
	var calls atomic.Int32
	var project string
	topic := "\n  为导航栏增加清晰的键盘焦点。\n先讨论交互取舍，保留所有无关功能。  \n"
	settings := testSettings()
	settings.CodexTransport = "magpie"
	settings.MagpiePort = 3425
	e, err := New(tempDir(t), func(ctx context.Context, seat, model, prompt, executable string) (string, error) {
		calls.Add(1)
		if seat != "cursor" || model != "cursor/main" || executable != "cursor-bin" {
			t.Errorf("title used another seat/child/model: %s %s %s", seat, model, executable)
		}
		if deadline, ok := ctx.Deadline(); !ok || time.Until(deadline) > 3*time.Second {
			t.Error("title call lacked configured timeout")
		}
		mode, port := CodexRoute(ctx)
		if mode != "magpie" || port != 3425 {
			t.Error("existing transport context was not preserved")
		}
		if !strings.HasPrefix(prompt, "TITLE REQUEST:") || !strings.Contains(prompt, "TASK TEXT:\n") || strings.Contains(prompt, project) || strings.Contains(prompt, "ACTION HISTORY") || strings.Contains(prompt, "PRIVATE_CHILD_SECRET") {
			t.Errorf("title call included unrelated context")
		}
		var actualTask string
		parts := strings.SplitN(prompt, "TASK TEXT:\n", 2)
		if len(parts) != 2 || json.Unmarshal([]byte(parts[1]), &actualTask) != nil || actualTask != topic {
			t.Error("naming did not receive original task text")
		}
		return "改善导航栏键盘焦点", nil
	}, func() Settings { return settings })
	if err != nil {
		t.Fatal(err)
	}
	project = tempDir(t)
	s, err := e.Create(topic, project, []string{"cursor", "codex"})
	if err != nil {
		t.Fatal(err)
	}
	if s.Topic != topic || s.Title != "" || calls.Load() != 0 {
		t.Fatal("create lost original task or initiated naming")
	}
	saved, err := os.ReadFile(filepath.Join(e.dir, s.ID+".json"))
	var savedFields map[string]json.RawMessage
	if err != nil || json.Unmarshal(saved, &savedFields) != nil || savedFields["title"] != nil {
		t.Fatal("empty optional title was serialized")
	}
	// Naming has no dependency on even opening the selected project.
	moved := project + "-unavailable"
	if err = os.Rename(project, moved); err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(moved)
	title, err := e.GenerateTitle(context.Background(), s.ID)
	if err != nil || title != "改善导航栏键盘焦点" {
		t.Fatalf("title=%q error=%v", title, err)
	}
	current, err := e.Get(s.ID)
	if err != nil {
		t.Fatal(err)
	}
	if current.Topic != topic || current.Title != title || len(current.Rounds) != 0 || len(current.Events) != 1 || len(current.Operations) != 0 || len(current.UserChanges) != 0 || current.Status != "ready" {
		t.Fatalf("naming changed meeting semantics: %#v", current)
	}
	list, err := e.List()
	if err != nil || len(list) != 1 || list[0].Title != title || list[0].Topic != topic || list[0].RoundCount != 0 {
		t.Fatalf("summary lost title/task: %v %#v", err, list)
	}
	markdown, err := e.Markdown(s.ID)
	if err != nil || !strings.HasPrefix(markdown, "# "+title+"\n\n## Task\n\n") || !strings.Contains(markdown, topic) {
		t.Fatalf("export lost original task or title: %v %q", err, markdown)
	}
	again, err := e.GenerateTitle(context.Background(), s.ID)
	if err != nil || again != title || calls.Load() != 1 {
		t.Fatal("saved title was regenerated")
	}
	other, err := New(e.dir, func(context.Context, string, string, string, string) (string, error) {
		t.Error("persisted title triggered another model request")
		return "覆盖名称", nil
	}, testSettings)
	if err != nil {
		t.Fatal(err)
	}
	if got, err := other.GenerateTitle(context.Background(), s.ID); err != nil || got != title {
		t.Fatal("title was not durable or immutable")
	}
}

func TestTitleFirstCodexUsesCurrentMainModelAndRoute(t *testing.T) {
	settings := testSettings()
	settings.Models["codex"] = "codex/current-main"
	settings.CLIPaths["codex"] = "selected-codex"
	settings.CodexTransport = "magpie"
	settings.MagpiePort = 9876
	settings.Timeout = 180
	e, err := New(tempDir(t), func(ctx context.Context, seat, model, prompt, exe string) (string, error) {
		mode, port := CodexRoute(ctx)
		if seat != "codex" || model != "codex/current-main" || exe != "selected-codex" || mode != "magpie" || port != 9876 {
			t.Error("title did not follow first parent current settings")
		}
		if deadline, ok := ctx.Deadline(); !ok || time.Until(deadline) > titleTimeout {
			t.Error("title lacks independent upper deadline")
		}
		return "改进文件保存流程", nil
	}, func() Settings { return settings })
	if err != nil {
		t.Fatal(err)
	}
	s, err := e.Create("改进文件保存流程，之后再完善状态显示。", tempDir(t), nil)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = e.GenerateTitle(context.Background(), s.ID); err != nil {
		t.Fatal(err)
	}
}

func TestTitleConcurrentOpensShareOneCallAndWaiterCancelIsLocal(t *testing.T) {
	started, release := make(chan struct{}), make(chan struct{})
	var calls atomic.Int32
	e, project := engine(t, func(ctx context.Context, seat, model, prompt, exe string) (string, error) {
		if calls.Add(1) == 1 {
			close(started)
		}
		select {
		case <-release:
			return "改善任务详情展示", nil
		case <-ctx.Done():
			return "", ctx.Err()
		}
	})
	s, err := e.Create("改善任务详情展示", project, nil)
	if err != nil {
		t.Fatal(err)
	}
	owner := make(chan error, 1)
	go func() { _, err := e.GenerateTitle(context.Background(), s.ID); owner <- err }()
	<-started
	var wg sync.WaitGroup
	results := make(chan error, 20)
	for i := 0; i < 20; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			title, err := e.GenerateTitle(context.Background(), s.ID)
			if err == nil && title != "改善任务详情展示" {
				err = errors.New("wrong shared title")
			}
			results <- err
		}()
	}
	waitCtx, cancel := context.WithTimeout(context.Background(), 30*time.Millisecond)
	_, err = e.GenerateTitle(waitCtx, s.ID)
	cancel()
	if !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("waiter cancellation: %v", err)
	}
	if calls.Load() != 1 {
		t.Fatal("waiter launched another title request")
	}
	close(release)
	if err = <-owner; err != nil {
		t.Fatal(err)
	}
	wg.Wait()
	close(results)
	for err := range results {
		if err != nil {
			t.Fatal(err)
		}
	}
	if calls.Load() != 1 {
		t.Fatalf("concurrent opens issued %d requests", calls.Load())
	}
}

func TestTitleLeaseDeduplicatesDifferentEngines(t *testing.T) {
	started, release := make(chan struct{}), make(chan struct{})
	var calls atomic.Int32
	call := func(ctx context.Context, seat, model, prompt, exe string) (string, error) {
		if calls.Add(1) == 1 {
			close(started)
		}
		select {
		case <-release:
			return "优化任务列表筛选", nil
		case <-ctx.Done():
			return "", ctx.Err()
		}
	}
	e, project := engine(t, call)
	s, err := e.Create("优化任务列表筛选", project, nil)
	if err != nil {
		t.Fatal(err)
	}
	other, err := New(e.dir, call, testSettings)
	if err != nil {
		t.Fatal(err)
	}
	results := make(chan error, 2)
	go func() { _, err := e.GenerateTitle(context.Background(), s.ID); results <- err }()
	<-started
	go func() {
		title, err := other.GenerateTitle(context.Background(), s.ID)
		if err == nil && title != "优化任务列表筛选" {
			err = errors.New("wrong durable title")
		}
		results <- err
	}()
	time.Sleep(30 * time.Millisecond)
	close(release)
	for i := 0; i < 2; i++ {
		if err := <-results; err != nil {
			t.Fatal(err)
		}
	}
	if calls.Load() != 1 {
		t.Fatalf("cross-engine title lease allowed %d successful requests", calls.Load())
	}
}

func TestTitleSaveDoesNotOverwriteRunningRoundOrUserWrite(t *testing.T) {
	titleStarted, titleRelease := make(chan struct{}), make(chan struct{})
	roundStarted, roundRelease := make(chan struct{}), make(chan struct{})
	e, project := engine(t, func(ctx context.Context, seat, model, prompt, exe string) (string, error) {
		if strings.HasPrefix(prompt, "TITLE REQUEST:") {
			close(titleStarted)
			select {
			case <-titleRelease:
				return "完善编辑统计", nil
			case <-ctx.Done():
				return "", ctx.Err()
			}
		}
		close(roundStarted)
		select {
		case <-roundRelease:
			return say("模型公开结论"), nil
		case <-ctx.Done():
			return "", ctx.Err()
		}
	})
	s, err := e.Create("完善编辑统计。请保留原始需求全文。", project, []string{"codex"})
	if err != nil {
		t.Fatal(err)
	}
	titleDone := make(chan error, 1)
	go func() { _, err := e.GenerateTitle(context.Background(), s.ID); titleDone <- err }()
	<-titleStarted
	if _, err = e.Start(s.ID, "同时运行审阅", "", 0); err != nil {
		t.Fatal(err)
	}
	<-roundStarted
	if _, err = e.UserWrite(s.ID, "note.md", "用户真实编辑\n", "missing"); err != nil {
		t.Fatal(err)
	}
	before, err := e.Get(s.ID)
	if err != nil {
		t.Fatal(err)
	}
	close(titleRelease)
	if err = <-titleDone; err != nil {
		t.Fatal(err)
	}
	during, err := e.Get(s.ID)
	if err != nil {
		t.Fatal(err)
	}
	if during.Title != "完善编辑统计" || during.Status != "running" || len(during.Rounds) != 1 || len(during.Operations) != 1 || len(during.UserChanges) != 1 || len(during.Events) != len(before.Events) {
		t.Fatalf("title overwrote concurrent data: %#v", during)
	}
	close(roundRelease)
	final := settled(t, e, s.ID)
	if final.Title != "完善编辑统计" || final.Topic != s.Topic || final.Rounds[0].Turns[0].Text != "模型公开结论" || len(final.UserChanges) != 1 {
		t.Fatal("round save overwrote title or user edit")
	}
	if data, err := os.ReadFile(filepath.Join(project, "note.md")); err != nil || string(data) != "用户真实编辑\n" {
		t.Fatal("naming changed actual project content")
	}
}

func TestTitleFailureAndInvalidAnswerAreRetryable(t *testing.T) {
	var calls atomic.Int32
	e, project := engine(t, func(context.Context, string, string, string, string) (string, error) {
		switch calls.Add(1) {
		case 1:
			return "", errors.New("temporary CLI failure")
		case 2:
			return "{\"action\":\"write\",\"path\":\"bad.md\",\"text\":\"no\"}", nil
		default:
			return "改进导航栏", nil
		}
	})
	s, err := e.Create("改进导航栏", project, nil)
	if err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 2; i++ {
		if _, err = e.GenerateTitle(context.Background(), s.ID); err == nil {
			t.Fatal("failed or action reply was accepted as title")
		}
		current, err := e.Get(s.ID)
		if err != nil || current.Title != "" || current.Topic != s.Topic || len(current.Rounds) != 0 || len(current.Events) != 1 {
			t.Fatal("title failure mutated session")
		}
	}
	if title, err := e.GenerateTitle(context.Background(), s.ID); err != nil || title != "改进导航栏" || calls.Load() != 3 {
		t.Fatalf("title retry failed: %q %v", title, err)
	}
	if _, err = os.Stat(filepath.Join(project, "bad.md")); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("title JSON was executed as a real action")
	}
}

func TestTitleCancellationStorageWaitAndShutdown(t *testing.T) {
	var calls atomic.Int32
	var allow atomic.Bool
	started := make(chan struct{}, 2)
	e, project := engine(t, func(ctx context.Context, _ string, _ string, _ string, _ string) (string, error) {
		calls.Add(1)
		if allow.Load() {
			return "改善状态提示", nil
		}
		started <- struct{}{}
		<-ctx.Done()
		return "", ctx.Err()
	})
	s, err := e.Create("改善状态提示", project, nil)
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 25*time.Millisecond)
	_, err = e.GenerateTitle(ctx, s.ID)
	cancel()
	if !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("title deadline not preserved: %v", err)
	}
	<-started
	allow.Store(true)
	if _, err = e.GenerateTitle(context.Background(), s.ID); err != nil {
		t.Fatal("cancelled request could not be retried", err)
	}

	// A second untitled session tests cancellation while awaiting storage.
	second, err := e.Create("优化连接检查", project, nil)
	if err != nil {
		t.Fatal(err)
	}
	e.mu.Lock()
	ctx, cancel = context.WithTimeout(context.Background(), 25*time.Millisecond)
	_, err = e.GenerateTitle(ctx, second.ID)
	cancel()
	e.mu.Unlock()
	if !errors.Is(err, context.DeadlineExceeded) || calls.Load() != 2 {
		t.Fatal("cancelled storage wait started CLI work")
	}

	allow.Store(false)
	done := make(chan error, 1)
	go func() { _, err := e.GenerateTitle(context.Background(), second.ID); done <- err }()
	<-started
	shutdownCtx, stop := context.WithTimeout(context.Background(), time.Second)
	defer stop()
	if err = e.Shutdown(shutdownCtx); err != nil {
		t.Fatal(err)
	}
	if err = <-done; !errors.Is(err, context.Canceled) {
		t.Fatalf("shutdown did not cancel naming: %v", err)
	}
	if _, err = e.GenerateTitle(context.Background(), second.ID); !errors.Is(err, ErrConflict) {
		t.Fatal("shutdown accepted new naming")
	}
	current, err := e.Get(second.ID)
	if err != nil || current.Title != "" || len(current.Rounds) != 0 {
		t.Fatal("cancelled title persisted or added a round")
	}
}

func TestTitleLeaseWaitCanBeCancelled(t *testing.T) {
	var calls atomic.Int32
	e, project := engine(t, func(context.Context, string, string, string, string) (string, error) {
		calls.Add(1)
		return "修复搜索结果排序", nil
	})
	s, err := e.Create("修复搜索结果排序", project, nil)
	if err != nil {
		t.Fatal(err)
	}
	lock, err := os.OpenFile(filepath.Join(e.dir, s.ID+".title.lock"), os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		t.Fatal(err)
	}
	defer lock.Close()
	if err = syscall.Flock(int(lock.Fd()), syscall.LOCK_EX); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 25*time.Millisecond)
	_, err = e.GenerateTitle(ctx, s.ID)
	cancel()
	if !errors.Is(err, context.DeadlineExceeded) || calls.Load() != 0 {
		t.Fatal("blocked title lease was not cancellable")
	}
	_ = syscall.Flock(int(lock.Fd()), syscall.LOCK_UN)
	if _, err = e.GenerateTitle(context.Background(), s.ID); err != nil || calls.Load() != 1 {
		t.Fatal("lease cancellation prevented a later explicit retry")
	}
}

func TestTitleValidationIsConciseAndTaskAgnostic(t *testing.T) {
	for _, tc := range []struct{ raw, want string }{
		{" 修复深色主题配色 \n", "修复深色主题配色"},
		{"标题：优化文件预览", "优化文件预览"},
		{"Title: \"Improve keyboard navigation\"", "Improve keyboard navigation"},
		{"# **整理课程讲义**", "整理课程讲义"},
	} {
		got, err := validateTitle(tc.raw)
		if err != nil || got != tc.want {
			t.Fatalf("valid title %q: %q %v", tc.raw, got, err)
		}
	}
	for _, raw := range []string{
		"", "a", strings.Repeat("长", 49), "a b c d e f g h i",
		"修复导航\n这是解释", "{\"title\":\"修复导航\"}", "[修复导航]", "- 修复导航", "1. 修复导航",
		"/private/project/file.md", "https://example.invalid/title", string([]byte{0xff, 0xfe}), "标题\u2028解释",
	} {
		if _, err := validateTitle(raw); err == nil {
			t.Fatalf("invalid title was accepted: %q", raw)
		}
	}
}
