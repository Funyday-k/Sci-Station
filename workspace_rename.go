package main

import (
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"syscall"

	"scistation.local/desktop/internal/workspace"
)

// This registry is installation-owned. A file supplied inside a research root
// cannot nominate another workspace's WebKit origin or Keychain account.
type rootBinding struct {
	disk      json.RawMessage
	ID        string   `json:"id"`
	Device    uint64   `json:"device"`
	Directory uint64   `json:"directory"`
	Marker    uint64   `json:"marker"`
	Paths     []string `json:"paths"`
}

type bindingIndex struct {
	records []rootBinding
	fields  map[string]json.RawMessage
}

func (r desktopRoots) bindingIndex() (bindingIndex, error) {
	index := bindingIndex{fields: map[string]json.RawMessage{"version": json.RawMessage("1")}}
	b, err := workspace.ManagedReadFile(filepath.Join(r.dir, "renamed-workspaces.json"))
	if errors.Is(err, os.ErrNotExist) {
		return index, nil
	}
	if err != nil {
		return index, err
	}
	var fields map[string]json.RawMessage
	var version int
	var list []json.RawMessage
	invalid := errors.New("invalid workspace relocation registry")
	if json.Unmarshal(b, &fields) != nil || json.Unmarshal(fields["version"], &version) != nil || version != 1 ||
		json.Unmarshal(fields["records"], &list) != nil || list == nil {
		return index, invalid
	}
	index.fields = fields
	for _, raw := range list {
		var record rootBinding
		if json.Unmarshal(raw, &record) != nil || record.Directory == 0 || record.Marker == 0 || len(record.Paths) == 0 {
			return index, invalid
		}
		id, err := hex.DecodeString(record.ID)
		if err != nil || len(id) != 32 {
			return index, invalid
		}
		for _, path := range record.Paths {
			if !filepath.IsAbs(path) || filepath.Clean(path) != path {
				return index, invalid
			}
		}
		record.disk = raw
		index.records = append(index.records, record)
	}
	return index, nil
}
func (r desktopRoots) saveBinding(index bindingIndex, record rootBinding) error {
	rows := make([]json.RawMessage, 0, len(index.records)+1)
	var prior json.RawMessage
	for _, item := range index.records {
		if item.matches(record) {
			prior = item.disk
		} else {
			rows = append(rows, item.disk)
		}
	}
	latest, err := overlayFields(prior, record)
	if err != nil {
		return err
	}
	rows = append(rows, latest)
	index.fields["records"], err = json.Marshal(rows)
	if err != nil {
		return err
	}
	data, err := json.Marshal(index.fields)
	if err != nil {
		return err
	}
	return workspace.ManagedAtomicWrite(filepath.Join(r.dir, "renamed-workspaces.json"), data)
}
func folderIdentity(path string) (rootBinding, error) {
	d, err := os.Lstat(path)
	if err != nil {
		return rootBinding{}, err
	}
	if !d.IsDir() {
		return rootBinding{}, os.ErrPermission
	}
	stat := d.Sys().(*syscall.Stat_t)
	identity := rootBinding{Device: uint64(stat.Dev), Directory: uint64(stat.Ino), ID: rootID(path)}
	m, err := os.Lstat(filepath.Join(path, rootMarker))
	if err == nil && m.Mode().IsRegular() {
		identity.Marker = uint64(m.Sys().(*syscall.Stat_t).Ino)
	} else if err != nil && !errors.Is(err, os.ErrNotExist) {
		return rootBinding{}, err
	}
	return identity, nil
}
func (b rootBinding) matches(other rootBinding) bool {
	return b.Device == other.Device && b.Directory == other.Directory && b.Marker != 0 && b.Marker == other.Marker
}
func (r desktopRoots) binding(path string) (rootBinding, error) {
	index, err := r.bindingIndex()
	if err != nil {
		return rootBinding{}, err
	}
	if len(index.records) == 0 {
		return rootBinding{ID: rootID(path)}, nil
	}
	actual, err := folderIdentity(path)
	if err != nil {
		return rootBinding{}, err
	}
	for _, record := range index.records {
		if !slices.Contains(record.Paths, path) {
			continue
		}
		if record.matches(actual) {
			return record, nil
		}
		// Reusing an old folder name must not inherit private state.
		actual.ID = rootID(fmt.Sprintf("replacement:%s:%d:%d", path, actual.Device, actual.Directory))
	}
	return actual, nil
}

func (r desktopRoots) recordedPath(path, identity string) (string, error) {
	if path == "" {
		return "", nil
	}
	index, err := r.bindingIndex()
	if err != nil {
		return "", err
	}
	if info, err := os.Lstat(path); err == nil && info.IsDir() {
		binding, err := r.binding(path)
		if err != nil {
			return "", err
		}
		if identity == "" || identity == binding.ID {
			return path, nil
		}
	}
	for i := len(index.records) - 1; i >= 0; i-- {
		record := index.records[i]
		if (identity != "" && identity != record.ID) || !slices.Contains(record.Paths, path) {
			continue
		}
		if actual, err := folderIdentity(path); err == nil && record.matches(actual) {
			return path, nil
		}
		for j := len(record.Paths) - 1; j >= 0; j-- {
			p := record.Paths[j]
			if actual, err := folderIdentity(p); err == nil && record.matches(actual) {
				return p, nil
			}
		}
	}
	if identity != "" {
		if info, err := os.Lstat(path); err == nil && info.IsDir() {
			return "", errors.New("记住的工作区已被替换 / Remembered workspace was replaced")
		}
	}
	return path, nil
}

// Hold the original process lock throughout the actual move. Record the
// directory identity before publishing its new name so a crash is recoverable.
func (r desktopRoots) moveRoot(from, to string, expected rootBinding) error {
	if filepath.Dir(from) != filepath.Dir(to) || from == to || !validWorkspaceName(filepath.Base(to)) || strings.HasPrefix(filepath.Base(to), ".") {
		return os.ErrInvalid
	}
	guard, err := workspace.ManagedOpenFile(filepath.Join(from, ".studio-process.lock"), os.O_RDWR, 0)
	if err != nil {
		return err
	}
	defer guard.Close()
	if err = syscall.Flock(int(guard.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		return err
	}
	return r.withRecentLock(func() error {
		current, err := folderIdentity(from)
		if err != nil {
			return err
		}
		if !current.matches(expected) {
			return errors.New("工作区文件夹已改变 / Workspace folder changed")
		}
		dir, err := workspace.ManagedOpenDirectory(filepath.Dir(from))
		if err != nil {
			return err
		}
		defer dir.Close()
		if _, err := dir.Lstat(filepath.Base(to)); !errors.Is(err, os.ErrNotExist) {
			return errors.New("目标文件夹已存在 / Destination already exists")
		}
		index, err := r.bindingIndex()
		if err != nil {
			return err
		}
		bind, err := r.binding(from)
		if err != nil {
			return err
		}
		current.ID = bind.ID
		current.Paths = append([]string(nil), bind.Paths...)
		for _, p := range []string{from, to} {
			if !slices.Contains(current.Paths, p) {
				current.Paths = append(current.Paths, p)
			}
		}
		if err := r.saveBinding(index, current); err != nil {
			return err
		}
		fd, err := dir.Open(".")
		if err != nil {
			return err
		}
		defer fd.Close()
		return renameRootExclusive(int(fd.Fd()), filepath.Base(from), filepath.Base(to))
	})
}
func (a *apiServer) rootIdentity() string {
	if a.boundRootID != "" {
		return a.boundRootID
	}
	return rootID(a.workspaceDir)
}

func (a *apiServer) workspaceDisplay() string {
	return rootDisplay(a.workspaceDir)
}
func (s *workspaceInstance) displayName() string {
	if s.api != nil {
		return s.api.workspaceDisplay()
	}
	return rootDisplay(s.dir)
}
