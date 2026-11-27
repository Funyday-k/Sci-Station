package research

import (
	"errors"
	"os"
	"path/filepath"
	"testing"

	"scistation.local/desktop/internal/workspace"
)

func TestConversationResetRequiresConfirmationAndRecoversOnlyItsProject(t *testing.T) {
	real := func() string {
		t.Helper()
		dir, err := filepath.EvalSymlinks(t.TempDir())
		if err != nil {
			t.Fatal(err)
		}
		return dir
	}
	source, target, root := real(), real(), real()
	s := newResearch(t, root)
	own := func(path string) Project {
		t.Helper()
		grant, err := IdentifyDirectory(path)
		if err != nil {
			t.Fatal(err)
		}
		p, err := s.RegisterDirectoryProject(path, "", grant)
		if err != nil {
			t.Fatal(err)
		}
		return p
	}
	project, other := own(source), own(real())
	seed := s.projects[project.ID]
	seed.Reviews = map[string]MeetingReview{"previous": {SourceText: "old conversation"}}
	seed.Notes = map[string]Note{"retained": {Title: "Published research note"}}
	if err := s.commit(seed); err != nil {
		t.Fatal(err)
	}
	fixtureFile := filepath.Join(source, "work.txt")
	if err := os.WriteFile(fixtureFile, []byte("external work"), 0600); err != nil {
		t.Fatal(err)
	}
	var selected = true
	s.SetPathValidator(func(path string, grant DirectoryGrant) bool {
		if path != target || !selected {
			return false
		}
		selected = false
		return true
	})
	change := directoryChange{Revision: project.Revision, Path: target}
	if _, err := s.changeProjectDirectory(project.ID, change); !errors.Is(err, errResetConfirmation) || !selected {
		t.Fatal(err, selected)
	}
	s.SetConversationReset(func(id string, begin func() error) error { return workspace.ErrConflict })
	change.ResetConversations = true
	if _, err := s.changeProjectDirectory(project.ID, change); !errors.Is(err, workspace.ErrConflict) || !selected {
		t.Fatal(err, selected)
	}
	s.SetConversationReset(func(id string, begin func() error) error {
		if err := begin(); err != nil {
			return err
		}
		if s.CheckConversationGeneration(id, 1) == nil {
			t.Fatal("admitted new work before archive cleanup finished")
		}
		return errors.New("fixture archive operation interrupted")
	})
	if _, err := s.changeProjectDirectory(project.ID, change); !errors.Is(err, errResetPending) || selected {
		t.Fatal(err, selected)
	}
	s = newResearch(t, root)
	pending := s.projects[project.ID]
	if !s.AnyConversationResetPending() || pending.Project.Path != target || len(pending.Reviews) != 0 || pending.Notes["retained"].Title == "" {
		t.Fatal(pending.Project)
	}
	cleanups := 0
	s.SetConversationReset(func(id string, begin func() error) error {
		if id != project.ID {
			t.Fatal(id)
		}
		if err := begin(); err != nil {
			return err
		}
		cleanups++
		return nil
	})
	if err := s.RecoverConversationResets(); err != nil {
		t.Fatal(err)
	}
	if err := s.RecoverConversationResets(); err != nil {
		t.Fatal(err)
	}
	if cleanups != 1 || s.AnyConversationResetPending() || s.CheckConversationGeneration(project.ID, 0) == nil || s.CheckConversationGeneration(project.ID, 1) != nil || s.CheckConversationGeneration(other.ID, 0) != nil {
		t.Fatal(cleanups)
	}
	if _, err := s.finishConversationReset(project.ID, 1, nil); !errors.Is(err, workspace.ErrConflict) || cleanups != 1 {
		t.Fatal("late cleanup entered new generation", err, cleanups)
	}
	if content, err := os.ReadFile(fixtureFile); err != nil || string(content) != "external work" {
		t.Fatal(err)
	}
}

func TestConversationResetComparesDirectoryIdentityAcrossRevocation(t *testing.T) {
	base, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	old, next := filepath.Join(base, "original"), filepath.Join(base, "renamed")
	if err := os.Mkdir(old, 0700); err != nil {
		t.Fatal(err)
	}
	s := newResearch(t, t.TempDir())
	s.SetPathValidator(func(string, DirectoryGrant) bool { return true })
	grant, err := IdentifyDirectory(old)
	if err != nil {
		t.Fatal(err)
	}
	p, err := s.RegisterDirectoryProject(old, "", grant)
	if err != nil {
		t.Fatal(err)
	}
	p, err = s.changeProjectDirectory(p.ID, directoryChange{Revision: p.Revision})
	if err != nil {
		t.Fatal(err)
	}
	if err = os.Rename(old, next); err != nil {
		t.Fatal(err)
	}
	p, err = s.changeProjectDirectory(p.ID, directoryChange{Revision: p.Revision, Path: next})
	if err != nil || p.ConversationGeneration != 0 {
		t.Fatal(p, err)
	}
	if err = os.Rename(next, old); err != nil {
		t.Fatal(err)
	}
	if err = os.Mkdir(next, 0700); err != nil {
		t.Fatal(err)
	}
	if _, err = s.changeProjectDirectory(p.ID, directoryChange{Revision: p.Revision, Path: next}); !errors.Is(err, errResetConfirmation) {
		t.Fatal(err)
	}
}
