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

func TestRestoredFolderBindingUsesIdentityOrScopedConversationHistory(t *testing.T) {
	for _, tc := range []struct {
		name                                           string
		priorIdentity, sameTarget, hasHistory, confirm bool
	}{
		{"old restore with project draft", false, false, true, true},
		{"old restore with empty archive", false, false, false, false},
		{"restored original entity", true, true, true, false},
		{"restored different entity", true, false, true, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			real := func() string {
				t.Helper()
				dir, err := filepath.EvalSymlinks(t.TempDir())
				if err != nil {
					t.Fatal(err)
				}
				return dir
			}
			root, a, b := real(), real(), real()
			s := newResearch(t, root)
			identity, err := IdentifyDirectory(a)
			if err != nil {
				t.Fatal(err)
			}
			p, err := s.RegisterDirectoryProject(a, "", identity)
			if err != nil {
				t.Fatal(err)
			}
			// The restore tool revokes external access, but preserves the
			// stable project record. Older restores have no comparison field.
			d := s.projects[p.ID]
			d.Project.Path = ""
			d.Project.DirectoryGrant = nil
			if tc.priorIdentity {
				d.PreviousDirectoryIdentity = &identity
			}
			if err := s.commit(d); err != nil {
				t.Fatal(err)
			}
			s = newResearch(t, root)
			target := b
			if tc.sameTarget {
				target = a
			}
			picked := true
			s.SetPathValidator(func(path string, _ DirectoryGrant) bool {
				if !picked || path != target {
					return false
				}
				picked = false
				return true
			})
			s.SetConversationHistoryCheck(func(id string, use func(bool) error) error {
				if tc.priorIdentity || id != p.ID {
					t.Fatal("unexpected history lookup", id)
				}
				return use(tc.hasHistory)
			})
			resets := 0
			s.SetConversationReset(func(id string, begin func() error) error {
				if id != p.ID {
					t.Fatal(id)
				}
				if err := begin(); err != nil {
					return err
				}
				resets++
				return nil
			})
			request := directoryChange{Revision: p.Revision, Path: target}
			got, err := s.changeProjectDirectory(p.ID, request)
			if tc.confirm {
				if !errors.Is(err, errResetConfirmation) || !picked || resets != 0 {
					t.Fatal(err, picked, resets)
				}
				request.ResetConversations = true
				got, err = s.changeProjectDirectory(p.ID, request)
			}
			if err != nil || picked || got.Path != target || got.ConversationGeneration != uint64(resets) || (resets == 1) != tc.confirm {
				t.Fatal(got, err, picked, resets)
			}
		})
	}
}

func TestLegacyDifferentFolderConfirmsEvenWithNoServerHistory(t *testing.T) {
	root, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	a, b := filepath.Join(root, "a"), filepath.Join(root, "b")
	for _, path := range []string{a, b} {
		if err := os.Mkdir(path, 0700); err != nil {
			t.Fatal(err)
		}
	}
	s := newResearch(t, t.TempDir())
	grant, err := IdentifyDirectory(a)
	if err != nil {
		t.Fatal(err)
	}
	p, err := s.RegisterDirectoryProject(a, "", grant)
	if err != nil {
		t.Fatal(err)
	}
	d := s.projects[p.ID]
	d.Project.DirectoryGrant = nil
	if err := s.commit(d); err != nil {
		t.Fatal(err)
	}
	s.SetConversationHistoryCheck(func(string, func(bool) error) error { t.Fatal("disk-only probe for known A to B change"); return nil })
	if _, err := s.changeProjectDirectory(p.ID, directoryChange{Revision: p.Revision, Path: b}); !errors.Is(err, errResetConfirmation) {
		t.Fatal(err)
	}
}
