package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"maps"
	"os"
	"path/filepath"
	"strings"
	"syscall"
)

type treeEntry struct {
	Directory bool   `json:"directory,omitempty"`
	SHA256    string `json:"sha256,omitempty"`
	Size      int64  `json:"size,omitempty"`
}

func runtimeLock(path string) bool {
	if path == processLock || path == "studio/.meeting.lock" || path == "plugins/registry.lock" {
		return true
	}
	name, ok := strings.CutPrefix(path, "studio/")
	if !ok {
		return false
	}
	id, ok := strings.CutSuffix(name, ".run.lock")
	if !ok {
		id, ok = strings.CutSuffix(name, ".title.lock")
	}
	return ok && validID(id)
}

func scanTree(source, destination *os.Root, skipLocks bool) (map[string]treeEntry, error) {
	info, err := source.Stat(".")
	if err != nil {
		return nil, err
	}
	device := info.Sys().(*syscall.Stat_t).Dev
	result := make(map[string]treeEntry)
	err = fs.WalkDir(source.FS(), ".", func(path string, e fs.DirEntry, err error) error {
		if err != nil || path == "." {
			return err
		}
		info, err := e.Info()
		if err != nil {
			return err
		}
		stat := info.Sys().(*syscall.Stat_t)
		if stat.Dev != device {
			return fmt.Errorf("refusing to cross a mounted filesystem at %q", path)
		}
		if info.IsDir() {
			result[path] = treeEntry{Directory: true}
			if destination != nil {
				return destination.Mkdir(path, 0700)
			}
			return nil
		}
		if !info.Mode().IsRegular() || stat.Nlink != 1 {
			return fmt.Errorf("refusing a symlink, hard link, or special file at %q", path)
		}
		if skipLocks && runtimeLock(path) {
			return nil
		}
		record, err := hashFile(source, destination, path, info)
		if err != nil {
			return fmt.Errorf("%q: %w", path, err)
		}
		result[path] = record
		return nil
	})
	return result, err
}

func hashFile(source, destination *os.Root, path string, info fs.FileInfo) (treeEntry, error) {
	var entry treeEntry
	src, err := openRegular(source, path, info)
	if err != nil {
		return entry, err
	}
	defer src.Close()
	h := sha256.New()
	writer := io.Writer(h)
	var dst *os.File
	if destination != nil {
		dst, err = destination.OpenFile(path, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600|info.Mode().Perm()&0100)
		if err != nil {
			return entry, err
		}
		writer = io.MultiWriter(h, dst)
	}
	n, err := io.Copy(writer, src)
	if dst != nil {
		if err == nil {
			err = dst.Sync()
		}
		err = errors.Join(err, dst.Close())
	}
	if err != nil {
		return entry, err
	}
	after, err := src.Stat()
	if err != nil || !os.SameFile(info, after) || after.Size() != n || !after.ModTime().Equal(info.ModTime()) {
		return entry, errors.New("file changed while reading")
	}
	return treeEntry{Size: n, SHA256: hex.EncodeToString(h.Sum(nil))}, nil
}

func verifyTree(root *os.Root, expected map[string]treeEntry) error {
	actual, err := scanTree(root, nil, false)
	if err != nil {
		return err
	}
	if maps.Equal(actual, expected) {
		return nil
	}
	for path, entry := range expected {
		if actual[path] != entry {
			return fmt.Errorf("backup tree has a missing or changed entry %q", path)
		}
	}
	return errors.New("backup tree contains unlisted entries")
}

func syncDirectories(root *os.Root) error {
	return fs.WalkDir(root.FS(), ".", func(path string, e fs.DirEntry, err error) error {
		if err != nil || !e.IsDir() {
			return err
		}
		f, err := root.Open(path)
		if err != nil {
			return err
		}
		return errors.Join(f.Sync(), f.Close())
	})
}

func openRegular(root *os.Root, path string, info fs.FileInfo) (*os.File, error) {
	if info == nil {
		var err error
		info, err = root.Lstat(path)
		if err != nil {
			return nil, err
		}
	}
	if !info.Mode().IsRegular() || info.Sys().(*syscall.Stat_t).Nlink != 1 {
		return nil, fmt.Errorf("%q must be a regular file without links", path)
	}
	f, err := root.OpenFile(path, os.O_RDONLY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK, 0)
	if err != nil {
		return nil, err
	}
	opened, err := f.Stat()
	if err != nil || !os.SameFile(info, opened) || opened.Sys().(*syscall.Stat_t).Nlink != 1 {
		f.Close()
		return nil, fmt.Errorf("%q changed while opening", path)
	}
	return f, nil
}

func writePrivate(root *os.Root, path string, data []byte) error {
	f, err := root.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_TRUNC|syscall.O_NOFOLLOW, 0600)
	if err != nil {
		return err
	}
	_, err = f.Write(data)
	if err == nil {
		err = f.Sync()
	}
	return errors.Join(err, f.Close())
}

func readJSON(root *os.Root, name string, target any) error {
	f, err := openRegular(root, name, nil)
	if err != nil {
		return err
	}
	defer f.Close()
	decoder := json.NewDecoder(f)
	if err := decoder.Decode(target); err != nil {
		return fmt.Errorf("invalid JSON in %q: %w", name, err)
	}
	if err := decoder.Decode(new(json.RawMessage)); err != io.EOF {
		return fmt.Errorf("unexpected trailing data in %q", name)
	}
	return nil
}

func validID(id string) bool {
	return len(id) == 32 && validDigest(id)
}

func validDigest(hash string) bool {
	if strings.ToLower(hash) != hash {
		return false
	}
	_, err := hex.DecodeString(hash)
	return err == nil
}

func relativePath(parts ...string) string {
	return filepath.ToSlash(filepath.Join(parts...))
}
