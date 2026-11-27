package research

import (
	"encoding/json"
	"errors"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"syscall"

	"scistation.local/desktop/internal/workspace"
)

var minerBatchIDPattern = regexp.MustCompile(`^[A-Za-z0-9_-]{1,128}$`)

func ValidMinerBatchID(batch string) bool { return minerBatchIDPattern.MatchString(batch) }

type minerReceiptRecord struct {
	Version int    `json:"version"`
	Attempt string `json:"attempt"`
	State   string `json:"state"`
	Batch   string `json:"batch,omitempty"`
}

// MinerReceipt holds the per-source file lock while the provider action runs.
// The stable lock file is independent of atomically replaced JSON records.
type MinerReceipt struct {
	minerReceiptRecord
	path string
	lock *os.File
}

func (s *Service) OpenMinerReceipt(sourceID string) (*MinerReceipt, error) {
	if !validID(sourceID) {
		return nil, os.ErrInvalid
	}
	dir := filepath.Join(s.papers.dir, "mineru")
	if err := workspace.ManagedMkdirAll(dir, 0700); err != nil {
		return nil, err
	}
	lock, err := workspace.ManagedOpenFile(filepath.Join(dir, sourceID+".lock"), os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		return nil, err
	}
	if err := syscall.Flock(int(lock.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		lock.Close()
		return nil, err
	}
	r := &MinerReceipt{path: filepath.Join(dir, sourceID+".json"), lock: lock}
	f, err := workspace.ManagedOpenFile(r.path, os.O_RDONLY, 0)
	if errors.Is(err, os.ErrNotExist) {
		return r, nil
	}
	if err == nil {
		defer f.Close()
		decoder := json.NewDecoder(f)
		decoder.DisallowUnknownFields()
		if err = decoder.Decode(&r.minerReceiptRecord); err == nil {
			if decoder.Decode(new(any)) != io.EOF || !r.valid() {
				err = os.ErrInvalid
			}
		}
	}
	if err != nil {
		r.Close()
		return nil, err
	}
	return r, nil
}

func (r *MinerReceipt) Close() { r.lock.Close() }

func (r minerReceiptRecord) valid() bool {
	if r.Version != 1 || !validID(r.Attempt) {
		return false
	}
	switch r.State {
	case "batch":
		return ValidMinerBatchID(r.Batch)
	case "creating", "rejected":
		return r.Batch == ""
	default:
		return false
	}
}

func (r *MinerReceipt) update(next minerReceiptRecord) error {
	if !next.valid() {
		return os.ErrInvalid
	}
	b, err := json.Marshal(next)
	if err == nil {
		err = workspace.ManagedAtomicWrite(r.path, b)
	}
	if err == nil {
		r.minerReceiptRecord = next
	}
	return err
}

func (r *MinerReceipt) Begin() error {
	return r.update(minerReceiptRecord{Version: 1, Attempt: makeID(), State: "creating"})
}

func (r *MinerReceipt) RecordBatch(batch string) error {
	return r.update(minerReceiptRecord{Version: 1, Attempt: r.Attempt, State: "batch", Batch: batch})
}

// RecoverBatch invalidates any outstanding confirmation for an unresolved
// submission when the user locates a source-matching job at MinerU.
func (r *MinerReceipt) RecoverBatch(batch string) error {
	if r.State == "batch" {
		return nil
	}
	return r.update(minerReceiptRecord{Version: 1, Attempt: makeID(), State: "batch", Batch: batch})
}

func (r *MinerReceipt) Reject() error {
	return r.update(minerReceiptRecord{Version: 1, Attempt: r.Attempt, State: "rejected"})
}

// RememberMinerBatch records a manually recovered, source-bound provider batch.
// A lookup of an older job cannot replace a different recorded batch.
func (s *Service) RememberMinerBatch(sourceID, batch string) error {
	r, err := s.OpenMinerReceipt(sourceID)
	if err != nil {
		return err
	}
	defer r.Close()
	return r.RecoverBatch(batch)
}
