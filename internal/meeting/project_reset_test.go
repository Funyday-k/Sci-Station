package meeting

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestProjectResetRemovesOnlyConfirmedHistory(t *testing.T) {
	call := func(context.Context, string, string, string, string) (string, error) {
		t.Fatal("reset called a model")
		return "", nil
	}
	e, firstDir := engine(t, call)
	currentDir, otherDir := tempDir(t), tempDir(t)
	dirs := map[string]string{"alpha": firstDir, "beta": otherDir}
	e.SetProjectAccess(func(id string, use func(string) error) error { return use(dirs[id]) })
	store := func(text string) Material {
		t.Helper()
		m, err := e.StoreMaterial("fixture.txt", strings.NewReader(text))
		if err != nil {
			t.Fatal(err)
		}
		return m
	}
	excerpt := ProjectExcerptMarker + `{"projectId":"alpha"}` + "\n\n"
	oldOnly, neutral := store(excerpt+"old"), store("neutral upload also available to drafts")
	unbound, shared := store("unbound fixture"), store("shared by both projects")
	changed, retained := store(excerpt+"changed on disk"), store(excerpt+"also in a legacy session")
	create := func(scope ProjectScope, seats []string, ids ...string) *Session {
		t.Helper()
		room, err := e.CreateScopedWithMaterials("Synthetic session", scope, seats, ids)
		if err != nil {
			t.Fatal(err)
		}
		return room
	}
	chat := create(ProjectScope{ID: "alpha", Directory: firstDir}, []string{"codex"}, oldOnly.ID, neutral.ID, shared.ID, changed.ID, retained.ID)
	dirs["alpha"] = currentDir
	table := create(ProjectScope{ID: "alpha", Directory: currentDir}, nil, oldOnly.ID)
	other := create(ProjectScope{ID: "beta", Directory: otherDir}, []string{"cursor"}, shared.ID)
	global := create(ProjectScope{Global: true}, []string{"codex"})
	legacy := &Session{ID: newID(), Topic: "Legacy synthetic session", Project: firstDir, Seats: []string{"codex"}, Materials: []Material{retained}}
	if err := e.locked(func() error { return e.save(legacy) }); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(e.dir, "materials", changed.ID, "original"), []byte("a replacement with no matching owner"), 0600); err != nil {
		t.Fatal(err)
	}
	for _, draft := range []struct {
		scope    LabScope
		id, text string
	}{
		{LabScope{ProjectID: "alpha"}, "", "project draft"},
		{LabScope{ProjectID: "alpha"}, chat.ID, "thread draft"},
		{LabScope{ProjectID: "beta"}, other.ID, "other draft"},
		{LabScope{Global: true}, "", "global draft"},
	} {
		if _, err := e.LabDraft(draft.scope, draft.id, &LabDraft{Text: draft.text}); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.WriteFile(filepath.Join(e.dir, table.ID+".run.lock"), nil, 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(e.dir, chat.ID+".title.lock"), nil, 0600); err != nil {
		t.Fatal(err)
	}
	if err := e.ResetProjectSessions("alpha", func() error { return ErrConflict }); !errors.Is(err, ErrConflict) {
		t.Fatal(err)
	}
	if _, err := e.Get(chat.ID); err != nil {
		t.Fatalf("failed grant change removed history: %v", err)
	}
	if err := e.ResetProjectSessions("alpha", func() error { return nil }); err != nil {
		t.Fatal(err)
	}
	for _, path := range []string{
		filepath.Join(e.dir, chat.ID+".json"), filepath.Join(e.dir, table.ID+".json"),
		filepath.Join(e.dir, table.ID+".run.lock"), filepath.Join(e.dir, chat.ID+".title.lock"),
		e.labDraftPath("alpha", ""), e.labDraftPath("alpha", chat.ID),
		filepath.Join(e.dir, "materials", oldOnly.ID),
	} {
		if _, err := os.Lstat(path); !errors.Is(err, os.ErrNotExist) {
			t.Fatalf("retained reset item %s: %v", filepath.Base(path), err)
		}
	}
	for _, room := range []*Session{global, other, legacy} {
		if _, err := e.Get(room.ID); err != nil {
			t.Fatalf("lost retained room %s: %v", room.ID, err)
		}
	}
	for _, m := range []Material{neutral, shared, unbound, changed, retained} {
		if _, err := e.FindMaterial(m.ID); err != nil {
			t.Fatalf("lost retained material %s: %v", m.ID, err)
		}
	}
	for _, path := range []string{e.labDraftPath("beta", other.ID), e.labDraftPath("", "")} {
		if _, err := os.Stat(path); err != nil {
			t.Fatalf("lost unrelated draft: %v", err)
		}
	}
	// An earlier title request that had passed its first lookup cannot create
	// a new lock file or republish the old session.
	if _, err := e.titleLease(context.Background(), chat.ID); !errors.Is(err, os.ErrNotExist) {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(e.dir, chat.ID+".title.lock")); !errors.Is(err, os.ErrNotExist) {
		t.Fatal(err)
	}
	reopened, err := New(e.dir, call, testSettings)
	if err != nil {
		t.Fatal(err)
	}
	if err := reopened.ResetProjectSessions("alpha", func() error { return nil }); err != nil {
		t.Fatal(err)
	}
	if _, err := reopened.Get(chat.ID); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("history returned after restart: %v", err)
	}
}

func TestProjectResetFailureRetainsRetryIndexAndFencesStaleWrites(t *testing.T) {
	e, dir := engine(t, func(context.Context, string, string, string, string) (string, error) { return "", nil })
	scope := ProjectScope{ID: "project", Directory: dir}
	e.SetProjectAccess(func(_ string, use func(string) error) error { return use(dir) })
	generation := uint64(0)
	var pending bool
	e.SetConversationAccessCheck(func(id string) error {
		if id == scope.ID && pending {
			return ErrConversationResetPending
		}
		return nil
	}, func() bool { return pending })
	e.SetConversationGenerationCheck(func(_ string, seen uint64) error {
		if seen != generation {
			return ErrConflict
		}
		return nil
	})
	s, err := e.CreateScopedWithMaterials("Synthetic old room", scope, []string{"codex"}, nil)
	if err != nil {
		t.Fatal(err)
	}
	blocker := e.labDraftPath(scope.ID, s.ID)
	if err := os.MkdirAll(blocker, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(blocker, "fixture"), nil, 0600); err != nil {
		t.Fatal(err)
	}
	if err := e.ResetProjectSessions(scope.ID, func() error { generation++; pending = true; return nil }); err == nil {
		t.Fatal("reset accepted failed cleanup")
	}
	if _, err := e.Get(s.ID); !errors.Is(err, ErrConversationResetPending) {
		t.Fatalf("partial archive was readable: %v", err)
	}
	if _, _, err := e.Snapshot(s.ID, func(string) bool { return true }); !errors.Is(err, ErrConversationResetPending) {
		t.Fatalf("pending archive was served from a client cache: %v", err)
	}
	if _, err := e.BoardPresence(context.Background(), s.ID, nil); !errors.Is(err, ErrConversationResetPending) {
		t.Fatalf("pending archive allowed cursor access: %v", err)
	}
	if listed, broken, err := e.ListWithRecovery(); err != nil || len(listed) != 0 || len(broken) != 0 {
		t.Fatalf("pending archive listed: %v %v %v", listed, broken, err)
	}
	if _, err := os.Stat(filepath.Join(e.dir, s.ID+".json")); err != nil {
		t.Fatalf("lost retry index: %v", err)
	}
	if err := os.RemoveAll(blocker); err != nil {
		t.Fatal(err)
	}
	if err := e.ResetProjectSessions(scope.ID, func() error { return nil }); err != nil {
		t.Fatal(err)
	}
	pending = false
	if _, err := e.LabDraft(LabScope{ProjectID: scope.ID}, "", &LabDraft{Text: "stale composer"}); !errors.Is(err, ErrConflict) {
		t.Fatalf("old draft admitted: %v", err)
	}
	if _, err := e.CreateScopedWithMaterials("stale room", scope, nil, nil); !errors.Is(err, ErrConflict) {
		t.Fatalf("old creation admitted: %v", err)
	}
	scope.ConversationGeneration = generation
	fresh, err := e.CreateScopedWithMaterials("New room", scope, nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	freshScope := LabScope{ProjectID: scope.ID, ConversationGeneration: generation}
	if draft, err := e.LabDraft(freshScope, "", nil); err != nil || draft.Text != "" || draft.Revision != 0 {
		t.Fatalf("new composer = %+v, %v", draft, err)
	}
	if _, err := e.LabDraft(freshScope, "", &LabDraft{Text: "new draft"}); err != nil {
		t.Fatal(err)
	}
	if err := e.ResetProjectSessions(scope.ID, func() error { return ErrConflict }); !errors.Is(err, ErrConflict) {
		t.Fatalf("stale recovery: %v", err)
	}
	if _, err := e.Get(fresh.ID); err != nil {
		t.Fatalf("stale recovery removed new room: %v", err)
	}
	if draft, err := e.LabDraft(freshScope, "", nil); err != nil || draft.Text != "new draft" {
		t.Fatalf("stale recovery removed draft: %+v %v", draft, err)
	}
}

func TestProjectResetDetectsWorkerInAnotherEngine(t *testing.T) {
	for _, task := range []string{"round", "title"} {
		t.Run(task, func(t *testing.T) {
			started, finish := make(chan struct{}), make(chan struct{})
			e, dir := engine(t, func(ctx context.Context, seat, model, prompt, path string) (string, error) {
				close(started)
				select {
				case <-ctx.Done():
					return "", ctx.Err()
				case <-finish:
				}
				if task == "title" {
					return "Synthetic title", nil
				}
				return say("Synthetic response"), nil
			})
			e.SetProjectAccess(func(_ string, use func(string) error) error { return use(dir) })
			scope := ProjectScope{ID: "project", Directory: dir}
			s, err := e.CreateScopedWithMaterials("Fixture work", scope, []string{"codex"}, nil)
			if err != nil {
				t.Fatal(err)
			}
			observer, err := New(e.dir, e.call, testSettings)
			if err != nil {
				t.Fatal(err)
			}
			done := make(chan error, 1)
			if task == "round" {
				if _, err := e.Start(s.ID, "", "", 0); err != nil {
					t.Fatal(err)
				}
			} else {
				go func() { _, err := e.GenerateTitle(context.Background(), s.ID); done <- err }()
			}
			select {
			case <-started:
			case <-time.After(3 * time.Second):
				t.Fatal("worker did not start")
			}
			err = observer.ResetProjectSessions(scope.ID, func() error { t.Error("grant changed while worker active"); return nil })
			if !errors.Is(err, ErrConflict) {
				t.Fatalf("active worker result = %v", err)
			}
			close(finish)
			if task == "title" {
				if err := <-done; err != nil {
					t.Fatal(err)
				}
			} else {
				settled(t, e, s.ID)
			}
			if err := observer.ResetProjectSessions(scope.ID, func() error { return nil }); err != nil {
				t.Fatal(err)
			}
			if _, err := e.Get(s.ID); !errors.Is(err, os.ErrNotExist) {
				t.Fatalf("old %s work survived: %v", task, err)
			}
		})
	}
}

func TestProjectResetPreservesUnreadableArchives(t *testing.T) {
	e, dir := engine(t, func(context.Context, string, string, string, string) (string, error) { return "", nil })
	e.SetProjectAccess(func(_ string, use func(string) error) error { return use(dir) })
	m, err := e.StoreMaterial("fixture.txt", strings.NewReader(ProjectExcerptMarker+`{"projectId":"project"}`+"\n\nfixture"))
	if err != nil {
		t.Fatal(err)
	}
	s, err := e.CreateScopedWithMaterials("Fixture room", ProjectScope{ID: "project", Directory: dir}, nil, []string{m.ID})
	if err != nil {
		t.Fatal(err)
	}
	unreadable := filepath.Join(e.dir, newID()+".json")
	if err := os.WriteFile(unreadable, []byte("incomplete archive"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := e.ResetProjectSessions("project", func() error { return nil }); err != nil {
		t.Fatal(err)
	}
	if _, err := e.Get(s.ID); !errors.Is(err, os.ErrNotExist) {
		t.Fatal(err)
	}
	if _, err := os.Stat(unreadable); err != nil {
		t.Fatal(err)
	}
	if _, err := e.FindMaterial(m.ID); err != nil {
		t.Fatalf("attachment references of unreadable archive were unknown: %v", err)
	}
	for _, id := range []string{"", "  "} {
		if err := e.ResetProjectSessions(id, func() error { return fmt.Errorf("unexpected grant transition") }); err == nil {
			t.Fatal("empty project allowed")
		}
	}
}
