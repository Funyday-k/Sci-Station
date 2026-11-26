package workspace

import (
	"crypto/rand"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"runtime"
	"strings"

	"golang.org/x/sys/unix"
)

// macOS presents the system temporary directories via /var and /tmp. Accept
// only these system aliases and pin every remaining directory without links.
func managedPath(path string) (string, error) {
	if path == "" {
		return "", fs.ErrInvalid
	}
	path, err := filepath.Abs(path)
	if err != nil {
		return "", err
	}
	if runtime.GOOS == "darwin" {
		for _, alias := range []string{"/tmp", "/var"} {
			if path == alias || strings.HasPrefix(path, alias+"/") {
				if link, err := os.Readlink(alias); err == nil && (link == "private"+alias || link == "/private"+alias) {
					path = "/private" + path
				}
			}
		}
	}
	return path, nil
}

func ManagedOpenDirectory(path string) (*os.Root, error) {
	absolute, err := managedPath(path)
	if err != nil {
		return nil, err
	}
	return openDirectoryNoLinks(absolute)
}

func ManagedMkdirAll(path string, mode fs.FileMode) error {
	absolute, err := managedPath(path)
	if err != nil {
		return err
	}
	root, err := openDirectory(absolute, mode)
	if err != nil {
		return err
	}
	return root.Close()
}

func managedParent(path string) (*os.Root, string, error) {
	absolute, err := managedPath(path)
	if err != nil {
		return nil, "", err
	}
	root, err := openDirectoryNoLinks(filepath.Dir(absolute))
	return root, filepath.Base(absolute), err
}

func ManagedMkdir(path string, mode fs.FileMode) error {
	dir, name, err := managedParent(path)
	if err != nil {
		return err
	}
	defer dir.Close()
	return dir.Mkdir(name, mode)
}

func validManagedEntry(dir *os.Root, name string, allowMissing bool) error {
	info, err := dir.Lstat(name)
	if allowMissing && errors.Is(err, fs.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	if info.Mode()&fs.ModeSymlink != 0 || !info.Mode().IsRegular() && !info.IsDir() {
		return fmt.Errorf("%w: invalid managed entry %s", fs.ErrPermission, name)
	}
	return nil
}

func ManagedOpenFile(path string, flags int, mode fs.FileMode) (*os.File, error) {
	dir, name, err := managedParent(path)
	if err != nil {
		return nil, err
	}
	defer dir.Close()
	// Openat uses the already pinned parent and forbids following the final
	// component even if it changes after validation.
	fd, err := dir.Open(".")
	if err != nil {
		return nil, err
	}
	defer fd.Close()
	n, err := unix.Openat(int(fd.Fd()), name, flags|unix.O_NOFOLLOW|unix.O_CLOEXEC|unix.O_NONBLOCK, uint32(mode.Perm()))
	if err != nil {
		return nil, &os.PathError{Op: "open", Path: path, Err: err}
	}
	file := os.NewFile(uintptr(n), filepath.Join(dir.Name(), name))
	info, err := file.Stat()
	if err != nil || !info.Mode().IsRegular() {
		file.Close()
		if err == nil {
			err = fs.ErrPermission
		}
		return nil, err
	}
	return file, nil
}

func ManagedReadFile(path string) ([]byte, error) {
	f, err := ManagedOpenFile(path, os.O_RDONLY, 0)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	return io.ReadAll(f)
}

func managedTemp(root *os.Root, pattern string) (*os.File, error) {
	var key [16]byte
	if _, err := rand.Read(key[:]); err != nil {
		return nil, err
	}
	name := strings.TrimSuffix(pattern, "*") + fmt.Sprintf("%x", key[:])
	return root.OpenFile(name, os.O_CREATE|os.O_EXCL|os.O_RDWR, 0600)
}

func ManagedCreateTemp(dir, pattern string) (*os.File, error) {
	root, err := ManagedOpenDirectory(dir)
	if err != nil {
		return nil, err
	}
	defer root.Close()
	return managedTemp(root, pattern)
}

func ManagedAtomicWrite(path string, data []byte) error {
	root, name, err := managedParent(path)
	if err != nil {
		return err
	}
	defer root.Close()
	if err = validManagedEntry(root, name, true); err != nil {
		return err
	}
	f, err := managedTemp(root, ".write-")
	if err != nil {
		return err
	}
	temporary := filepath.Base(f.Name())
	defer root.Remove(temporary)
	if _, err = f.Write(data); err == nil {
		err = f.Sync()
	}
	closeErr := f.Close()
	if err != nil {
		return err
	}
	if closeErr != nil {
		return closeErr
	}
	if err = root.Rename(temporary, name); err != nil {
		return err
	}
	d, err := root.Open(".")
	if err != nil {
		return err
	}
	defer d.Close()
	return d.Sync()
}

// Pin both parents for cross-directory publication (PDF import, project trash).
func ManagedRename(from, to string) error {
	src, old, err := managedParent(from)
	if err != nil {
		return err
	}
	defer src.Close()
	dst, next, err := managedParent(to)
	if err != nil {
		return err
	}
	defer dst.Close()
	if err := validManagedEntry(src, old, false); err != nil {
		return err
	}
	if err := validManagedEntry(dst, next, true); err != nil {
		return err
	}
	a, err := src.Open(".")
	if err != nil {
		return err
	}
	defer a.Close()
	b, err := dst.Open(".")
	if err != nil {
		return err
	}
	defer b.Close()
	return unix.Renameat(int(a.Fd()), old, int(b.Fd()), next)
}

func ManagedRemove(path string) error {
	dir, name, err := managedParent(path)
	if err != nil {
		return err
	}
	defer dir.Close()
	return dir.Remove(name)
}

func ManagedRemoveAll(path string) error {
	dir, name, err := managedParent(path)
	if err != nil {
		return err
	}
	defer dir.Close()
	return dir.RemoveAll(name)
}

func ManagedReadDir(path string) ([]fs.DirEntry, error) {
	dir, err := ManagedOpenDirectory(path)
	if err != nil {
		return nil, err
	}
	defer dir.Close()
	return fs.ReadDir(dir.FS(), ".")
}
