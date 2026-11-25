package cliedit

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestSingleDecisionScopeAndShutdown(t *testing.T) {
	for _, mode := range []string{"accept", "decline", "stale", "shutdown", "scope"} {
		t.Run(mode, func(t *testing.T) {
			dir, err := filepath.EvalSymlinks(t.TempDir())
			if err != nil {
				t.Fatal(err)
			}
			file := filepath.Join(dir, "paper.md")
			if err := os.WriteFile(file, []byte("a\n"), 0600); err != nil {
				t.Fatal(err)
			}
			manager := new(Manager)
			valid := true
			scope := Scope{Directory: dir, MeetingID: "meeting", ProjectID: "project", Paths: []string{"paper.md"}}
			final := make(chan bool, 1)
			adapter := func(ctx context.Context, _ string, _ Scope, s Sink) error {
				if err := s.Running("thread", "turn"); err != nil {
					return err
				}
				allowed, err := s.Approval(ctx, Request{RequestID: "2", ThreadID: "thread", TurnID: "turn", ItemID: "item", Changes: []Change{{"paper.md", "update", "-a\n+b"}}})
				final <- allowed
				if err == nil {
					s.Result("CLI receipt")
				}
				return err
			}
			run, err := manager.Start(scope, "fixture", "", adapter, func(Scope) error {
				if !valid {
					return errors.New("grant revoked")
				}
				return nil
			})
			if err != nil {
				t.Fatal(err)
			}
			waitState(t, run, "pending")
			if err := run.Decide("other", "turn", "item", "2", true); err == nil {
				t.Fatal("mixed thread identity")
			}
			if _, err = manager.Start(scope, "fixture", "", adapter, func(Scope) error { return nil }); err == nil {
				t.Fatal("overlapping run")
			}
			switch mode {
			case "shutdown":
				manager.Close(t.Context())
			default:
				if mode == "stale" {
					if err := os.WriteFile(file, []byte("changed\n"), 0600); err != nil {
						t.Fatal(err)
					}
				}
				if mode == "scope" {
					valid = false
				}
				err = run.Decide("thread", "turn", "item", "2", mode != "decline")
				if (mode == "stale" || mode == "scope") != (err != nil) {
					t.Fatalf("unexpected decision error %v", err)
				}
			}
			select {
			case accepted := <-final:
				if accepted != (mode == "accept") {
					t.Fatal("wrong decision", accepted)
				}
			case <-time.After(2 * time.Second):
				t.Fatal("CLI did not receive closure or decision")
			}
			<-run.done
			if err := run.Decide("thread", "turn", "item", "2", true); err == nil {
				t.Fatal("replayed response accepted")
			}
			if mode == "shutdown" || mode == "stale" || mode == "scope" {
				if run.Snapshot().Status != "cancelled" {
					t.Fatal(run.Snapshot())
				}
			} else if run.Snapshot().Detail != "CLI receipt" {
				t.Fatal("missing CLI result")
			}
		})
	}
}
func waitState(t *testing.T, r *Run, status string) {
	t.Helper()
	for deadline := time.Now().Add(2 * time.Second); time.Now().Before(deadline); {
		if r.Snapshot().Status == status {
			return
		}
		time.Sleep(time.Millisecond)
	}
	t.Fatal("run did not reach", status, r.Snapshot())
}
func TestMCPOverridesUseOnlyDisabledRegistrationNames(t *testing.T) {
	fixture := "Name   Command Args Env Status Auth\nlocal-one   /fixture/path secret-placeholder ENV=***** enabled none\n\nName Url Bearer Token Env Var Status Auth\nother_2   https://example.invalid/private secret-placeholder enabled none\n"
	val, err := disabledMCPConfig(strings.NewReader(fixture))
	if err != nil || val != `mcp_servers={local-one={enabled=false,command="/usr/bin/false"},other_2={enabled=false,url="http://127.0.0.1:9"}}` {
		t.Fatal(val, err)
	}
	for _, bad := range []string{"Name Unrecognized\nx test\n", "Name Url\na.b config\n", "Name Command\nx one\nx two\n"} {
		if _, err := disabledMCPConfig(strings.NewReader(bad)); err == nil {
			t.Fatal("ambiguous list accepted")
		}
	}
}
