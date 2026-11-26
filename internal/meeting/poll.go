package meeting

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"syscall"

	"scistation.local/desktop/internal/sessionstore"
)

// Saves publish a new inode with rename. Its identity, size and timestamps
// let readers detect changes without decoding the complete meeting journal.
func (e *Engine) diskRevision(id string) (string, error) {
	if !sessionstore.ValidID(id) {
		return "", fmt.Errorf("invalid session ID: %w", os.ErrNotExist)
	}
	info, err := os.Lstat(filepath.Join(e.dir, id+".json"))
	if err != nil {
		return "", err
	}
	stat := info.Sys().(*syscall.Stat_t)
	return fmt.Sprintf("%x-%x-%x-%x", stat.Dev, stat.Ino, info.Size(), info.ModTime().UnixNano()), nil
}

// Snapshot evaluates the client's revision and reads its matching content
// under the same cross-process lock. A nil session means unchanged.
func (e *Engine) Snapshot(id string, current func(string) bool) (*Session, string, error) {
	var result *Session
	var revision string
	err := e.locked(func() error {
		var err error
		revision, err = e.diskRevision(id)
		if err != nil || (current != nil && current(revision)) {
			return err
		}
		result, err = e.load(id)
		if err != nil {
			return err
		}
		if err = e.recover(result); err != nil {
			return err
		}
		revision, err = e.diskRevision(id)
		return err
	})
	return result, revision, err
}

func (e *Engine) checkRevision(ctx context.Context, id string, previous *string) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	current, err := e.diskRevision(id)
	if err != nil || current == *previous {
		return err
	}
	if err = e.check(ctx, id); err == nil {
		*previous = current
	}
	return err
}
