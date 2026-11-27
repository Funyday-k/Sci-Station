package meeting

import (
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"unicode/utf8"

	"scistation.local/desktop/internal/sessionstore"
	"scistation.local/desktop/internal/workspace"
)

// ResetProjectSessions runs the host's durable grant transition and the purge
// under the same storage lock as session creation, draft edits and workers.
// The host must keep the new grant unavailable until cleanup succeeds. On
// recovery begin must verify that the same transition is still pending.
func (e *Engine) ResetProjectSessions(projectID string, begin func() error) error {
	if strings.TrimSpace(projectID) == "" || begin == nil {
		return errors.New("需要已确认的科研项目目录变更")
	}
	return e.locked(func() error {
		targets, ownedMaterials, err := e.projectHistory(projectID)
		if err != nil {
			return err
		}
		for _, id := range targets {
			for _, suffix := range []string{".run.lock", ".title.lock"} {
				if err := requireIdleLease(filepath.Join(e.dir, id+suffix)); err != nil {
					return err
				}
			}
		}
		if err := begin(); err != nil {
			return err
		}

		// Retain the session files as a retry index until their attachments
		// and drafts have been removed durably. Another project's draft can
		// still hold a neutral upload even if no saved session references it.
		for id := range ownedMaterials {
			if err := e.removeProjectMaterial(projectID, id); err != nil {
				return err
			}
		}
		if err := syncExistingDirectory(filepath.Join(e.dir, "materials")); err != nil {
			return err
		}
		if err := removeIfPresent(e.labDraftPath(projectID, "")); err != nil {
			return err
		}
		for _, id := range targets {
			if err := removeIfPresent(e.labDraftPath(projectID, id)); err != nil {
				return err
			}
		}
		if err := syncExistingDirectory(filepath.Join(e.dir, "lab-drafts")); err != nil {
			return err
		}
		for _, id := range targets {
			for _, suffix := range []string{".run.lock", ".title.lock", ".json"} {
				if err := removeIfPresent(filepath.Join(e.dir, id+suffix)); err != nil {
					return err
				}
			}
			e.presence.forget(id)
		}
		return syncExistingDirectory(e.dir)
	})
}

// Ownership comes only from the stable ID in the archive. Never recover or
// update a different project's sessions as a side effect of the reset.
func (e *Engine) projectHistory(projectID string) ([]string, map[string]bool, error) {
	ids, err := sessionstore.IDs(e.dir)
	if err != nil {
		return nil, nil, err
	}
	var targets []string
	candidates, retained := map[string]bool{}, map[string]bool{}
	unknownReferences := false
	for _, id := range ids {
		s, err := e.readArchive(id)
		if err != nil {
			var unreadable *sessionstore.Unreadable
			if !errors.As(err, &unreadable) {
				return nil, nil, err
			}
			unknownReferences = true
			continue
		}
		if s.ProjectID == projectID {
			targets = append(targets, id)
			for _, m := range s.Materials {
				if owner, valid := researchMaterialProject(m); valid && owner == projectID && sessionstore.ValidID(m.ID) {
					candidates[m.ID] = true
				}
			}
			continue
		}
		for _, m := range s.Materials {
			retained[m.ID] = true
		}
		for _, round := range s.Rounds {
			for _, id := range round.MaterialIDs {
				retained[id] = true
			}
		}
	}
	for id := range candidates {
		if unknownReferences || retained[id] {
			delete(candidates, id)
		}
	}
	return targets, candidates, nil
}

func requireIdleLease(path string) error {
	// Round, agenda and report leases are opened under the store lock. Title
	// workers must re-read the session under that lock after taking their lease.
	f, err := workspace.ManagedOpenFile(path, os.O_RDWR, 0)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	defer f.Close()
	if err = syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); errors.Is(err, syscall.EWOULDBLOCK) || errors.Is(err, syscall.EAGAIN) {
		return fmt.Errorf("%w: 此项目仍有会话任务正在运行，请在任务结束后重试", ErrConflict)
	}
	return err
}

func removeIfPresent(path string) error {
	err := workspace.ManagedRemove(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	return err
}

func syncExistingDirectory(path string) error {
	dir, err := workspace.ManagedOpenDirectory(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	defer dir.Close()
	f, err := dir.Open(".")
	if err != nil {
		return err
	}
	defer f.Close()
	return f.Sync()
}

func (e *Engine) removeProjectMaterial(projectID, id string) error {
	dir := filepath.Join(e.dir, "materials", id)
	entries, err := workspace.ManagedReadDir(dir)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	if len(entries) == 0 {
		return removeIfPresent(dir)
	}
	// Both the committed snapshot and the current pool record must establish
	// the same owner. Preserve altered, unrecognized or mixed-use entries.
	for _, entry := range entries {
		if !entry.Type().IsRegular() || (entry.Name() != "original" && entry.Name() != "metadata.json") {
			return nil
		}
	}
	m, err := e.FindMaterial(id)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	if owner, valid := researchMaterialProject(m); !valid || owner != projectID {
		return nil
	}
	if f, err := e.openMaterial(id); err == nil {
		prefix, readErr := io.ReadAll(io.LimitReader(f, maxMaterialExcerptRunes*utf8.UTFMax+3))
		_ = f.Close()
		if readErr != nil {
			return readErr
		}
		raw := strings.TrimPrefix(string(prefix), "\ufeff")
		if owner, valid := researchMaterialProject(Material{Excerpt: raw}); !valid || owner != projectID {
			return nil
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return err
	}
	if err := removeIfPresent(filepath.Join(dir, "original")); err != nil {
		return err
	}
	if err := syncExistingDirectory(dir); err != nil {
		return err
	}
	if err := removeIfPresent(filepath.Join(dir, "metadata.json")); err != nil {
		return err
	}
	return removeIfPresent(dir)
}
