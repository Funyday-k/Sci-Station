package main

import (
	"context"
	"errors"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"sync"
	"syscall"
	"testing"
	"time"

	"scistation.local/desktop/internal/cliedit"
	"scistation.local/desktop/internal/meeting"
)

func TestSwitchBackWaitsForWorkspaceWritersPastCloseDeadline(t *testing.T) {
	for _, writer := range []string{"meeting", "http", "cli"} {
		t.Run(writer, func(t *testing.T) {
			dir, err := filepath.EvalSymlinks(t.TempDir())
			if err != nil {
				t.Fatal(err)
			}
			if err := markNewRoot(dir); err != nil {
				t.Fatal(err)
			}
			guard, err := os.OpenFile(filepath.Join(dir, ".studio-process.lock"), os.O_CREATE|os.O_RDWR, 0600)
			if err != nil {
				t.Fatal(err)
			}
			if err = syscall.Flock(int(guard.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
				guard.Close()
				t.Fatal(err)
			}
			active, cancelled, resume := make(chan struct{}), make(chan struct{}), make(chan struct{})
			release := sync.OnceFunc(func() { close(resume) })
			waitForRelease := func(ctx context.Context) {
				close(active)
				<-ctx.Done()
				close(cancelled)
				<-resume
			}
			engine, err := meeting.New(filepath.Join(dir, "studio"), func(ctx context.Context, _, _, _, _ string) (string, error) {
				waitForRelease(ctx)
				return "", ctx.Err()
			}, func() meeting.Settings {
				return meeting.Settings{Models: map[string]string{"codex": "codex/fixture"}, Timeout: 10, MaxSteps: 2}
			})
			if err != nil {
				t.Fatal(err)
			}
			record := filepath.Join(dir, "fixture.txt")
			persist := func() error { return os.WriteFile(record, []byte(writer), 0600) }
			api := &apiServer{workspaceDir: dir, meetings: engine, research: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				waitForRelease(r.Context())
				if err := persist(); err != nil {
					http.Error(w, err.Error(), http.StatusInternalServerError)
				}
			})}
			listener, err := net.Listen("tcp4", "127.0.0.1:0")
			if err != nil {
				t.Fatal(err)
			}
			a := api.serveOwnedWorkspace(listener, guard, 40*time.Millisecond)
			session := rootSession{active: a}
			defer session.shutdown()
			defer release()

			var meetingID string
			var clientDone chan struct{}
			switch writer {
			case "meeting":
				started, err := engine.CreateScopedWithMaterials("Shutdown fixture", meeting.ProjectScope{Global: true}, []string{"codex"}, nil)
				if err != nil {
					t.Fatal(err)
				}
				meetingID = started.ID
				if _, err := engine.Start(meetingID, "", "", 0); err != nil {
					t.Fatal(err)
				}
			case "http":
				clientDone = make(chan struct{})
				go func() {
					defer close(clientDone)
					res, err := http.Get(a.address + "/api/research/fixture")
					if err == nil {
						res.Body.Close()
					}
				}()
			case "cli":
				scope := cliedit.Scope{Directory: dir, MeetingID: "fixture", Paths: []string{"fixture.txt"}}
				_, err := api.cliEdits.jobs.Start(scope, "fixture", "", func(ctx context.Context, _ string, _ cliedit.Scope, _ cliedit.Sink) error {
					waitForRelease(ctx)
					return persist()
				}, func(cliedit.Scope) error { return nil })
				if err != nil {
					t.Fatal(err)
				}
			}
			waitWorkspaceSignal(t, active, "writer start")
			b := t.TempDir()
			publish := func(*workspaceInstance) error { return nil }
			if err := session.switchTo(session.beginFor(api), func() (*workspaceInstance, error) {
				return startWorkspace(b, 0, false, true)
			}, publish); err != nil {
				t.Fatal(err)
			}
			waitWorkspaceSignal(t, cancelled, "writer cancellation")
			closeReturned := make(chan struct{})
			go func() { session.draining.Wait(); close(closeReturned) }()
			waitWorkspaceSignal(t, closeReturned, "bounded workspace close")
			if clientDone != nil {
				waitWorkspaceSignal(t, clientDone, "closed HTTP connection")
			}
			openA := func() (*workspaceInstance, error) { return startWorkspace(dir, 0, false, false) }
			if err := session.switchTo(session.beginFor(nil), openA, publish); !errors.Is(err, syscall.EWOULDBLOCK) {
				t.Fatalf("reopened while %s could still write: %v", writer, err)
			}
			release()
			for deadline := time.Now().Add(3 * time.Second); ; {
				err := session.switchTo(session.beginFor(nil), openA, publish)
				if err == nil {
					break
				}
				if !errors.Is(err, syscall.EWOULDBLOCK) || time.Now().After(deadline) {
					t.Fatalf("could not reopen after %s exited: %v", writer, err)
				}
				time.Sleep(time.Millisecond)
			}
			if writer == "meeting" {
				state, err := session.active.api.meetings.Get(meetingID)
				if err != nil || state.Status != "partial" || state.Rounds[0].Turns[0].Status != "error" {
					t.Fatalf("reopened meeting: %+v, %v", state, err)
				}
			} else if data, err := os.ReadFile(record); err != nil || string(data) != writer {
				t.Fatalf("missing final %s write: %q, %v", writer, data, err)
			}
		})
	}
}

func waitWorkspaceSignal(t *testing.T, ch <-chan struct{}, label string) {
	t.Helper()
	select {
	case <-ch:
	case <-time.After(3 * time.Second):
		t.Fatalf("timed out waiting for %s", label)
	}
}
