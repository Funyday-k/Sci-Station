package research

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"syscall"
)

const libraryBibliographyName = "library.bib"
const maxLibraryBibliography = 64 << 20

var errUnreadableBibliography = errors.New("工作区书目无法解析，请检查 research/library/refs/library.bib 后重试")
var errBibliographyConflict = errors.New("工作区书目已在其他位置修改，请重新导入")

// Resolve a regular managed directory with an os.Root handle. The shared
// bibliography may be edited by the user, so follow neither directory nor
// file symlinks, and check its bytes again just before replacement.
func (s *PaperLibrary) bibliographyDirectory(create bool) (*os.Root, error) {
	library, err := os.OpenRoot(s.dir)
	if err != nil {
		return nil, err
	}
	defer library.Close()
	opened, err := library.Stat(".")
	if err != nil || !os.SameFile(s.dirInfo, opened) {
		return nil, errBibliographyConflict
	}
	if create {
		if err = library.Mkdir("refs", 0700); err != nil && !errors.Is(err, os.ErrExist) {
			return nil, err
		}
	}
	info, err := library.Lstat("refs")
	if err != nil {
		return nil, err
	}
	if !info.IsDir() {
		return nil, errUnreadableBibliography
	}
	dir, err := library.OpenRoot("refs")
	if err != nil {
		return nil, err
	}
	current, err := dir.Stat(".")
	if err != nil || !os.SameFile(info, current) {
		dir.Close()
		return nil, errBibliographyConflict
	}
	return dir, nil
}

type bibliographySnapshot struct {
	body    []byte
	mode    os.FileMode
	existed bool
}

func readLibraryBibliography(dir *os.Root) (bibliographySnapshot, error) {
	var snapshot bibliographySnapshot
	file, err := dir.OpenFile(libraryBibliographyName, os.O_RDONLY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK, 0)
	if errors.Is(err, os.ErrNotExist) {
		return snapshot, nil
	}
	if err != nil {
		return snapshot, fmt.Errorf("%w: %v", errUnreadableBibliography, err)
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil || !info.Mode().IsRegular() {
		return snapshot, errUnreadableBibliography
	}
	body, err := io.ReadAll(io.LimitReader(file, maxLibraryBibliography+1))
	if err != nil || len(body) > maxLibraryBibliography {
		return snapshot, errUnreadableBibliography
	}
	return bibliographySnapshot{body, info.Mode().Perm(), true}, nil
}

func replaceLibraryBibliography(dir *os.Root, before, after bibliographySnapshot) error {
	staged := ""
	if after.existed {
		staged = ".bibliography-" + makeID()
		file, err := dir.OpenFile(staged, os.O_WRONLY|os.O_CREATE|os.O_EXCL|syscall.O_NOFOLLOW, 0600)
		if err != nil {
			return err
		}
		defer dir.Remove(staged)
		_, err = file.Write(after.body)
		if err == nil {
			err = file.Chmod(after.mode)
		}
		if err == nil {
			err = file.Sync()
		}
		if closeErr := file.Close(); err == nil {
			err = closeErr
		}
		if err != nil {
			return err
		}
	}
	current, err := readLibraryBibliography(dir)
	if err != nil {
		return err
	}
	if before.existed != current.existed || before.mode != current.mode || !bytes.Equal(before.body, current.body) {
		return errBibliographyConflict
	}
	if after.existed {
		err = dir.Rename(staged, libraryBibliographyName)
	} else {
		err = dir.Remove(libraryBibliographyName)
	}
	if err == nil {
		if parent, openErr := dir.Open("."); openErr == nil {
			_ = parent.Sync()
			_ = parent.Close()
		}
	}
	return err
}

// Cooperating imports are serialized by the paper-record lock. If a user
// changes the file after this append, rollback leaves their bytes intact.
func (s *PaperLibrary) appendLibraryBibliography(p Paper) (finish func(bool) error, err error) {
	dir, err := s.bibliographyDirectory(true)
	if err != nil {
		return nil, err
	}
	claimed := false
	defer func() {
		if !claimed {
			_ = dir.Close()
		}
	}()
	before, err := readLibraryBibliography(dir)
	if err != nil {
		return nil, err
	}
	source := string(before.body)
	found := false
	if err = walkBibtexKeys(source, func(start, end int) { found = found || source[start:end] == p.Citekey }); err != nil {
		return nil, errUnreadableBibliography
	}
	if found {
		return nil, nil
	}
	mode := before.mode
	if !before.existed {
		mode = 0600
		source = "% Sci-Station bibliography\n"
	}
	content := source + "\n" + paperBibtex(p)
	if len(content) > maxLibraryBibliography {
		return nil, errUnreadableBibliography
	}
	after := bibliographySnapshot{[]byte(content), mode, true}
	if err = replaceLibraryBibliography(dir, before, after); err != nil {
		return nil, err
	}
	claimed = true
	return func(committed bool) error {
		defer dir.Close()
		if committed {
			return nil
		}
		return replaceLibraryBibliography(dir, after, before)
	}, nil
}

func (s *PaperLibrary) workspaceBibliographyHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		paperMethod(w, http.MethodGet)
		return
	}
	dir, err := s.bibliographyDirectory(false)
	if err != nil {
		paperError(w, err)
		return
	}
	defer dir.Close()
	current, err := readLibraryBibliography(dir)
	if err != nil {
		paperError(w, err)
		return
	}
	if !current.existed {
		paperError(w, os.ErrNotExist)
		return
	}
	w.Header().Set("Content-Type", "application/x-bibtex; charset=utf-8")
	w.Header().Set("Content-Disposition", `attachment; filename="library.bib"`)
	_, _ = w.Write(current.body)
}
