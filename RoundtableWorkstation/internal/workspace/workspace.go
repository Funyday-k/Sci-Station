// Package workspace provides bounded, versioned access to explicitly selected
// project directories. It never creates directories or follows symlinks.
// Editable files are common UTF-8 source/document formats, at most 2 MiB;
// hidden paths, dependency/build trees, credential names and binary files are
// excluded from both the catalog and direct operations. Writes preserve the
// supplied bytes (including line endings) and the existing permission bits.
package workspace

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"syscall"
	"unicode/utf8"
)

const MaxFileBytes = 2 << 20
const MaxCatalogFiles = 10000
const MissingVersion = "missing"

var ErrConflict = errors.New("workspace version conflict")
var ErrInvalid = errors.New("invalid workspace input")

type File struct {
	Path    string `json:"path"`
	Text    string `json:"text"`
	Version string `json:"version"`
}

type Change struct {
	Path   string `json:"path"`
	Before string `json:"before"`
	After  string `json:"after"`
	Diff   string `json:"diff"`
}

var projectLocks sync.Map

func invalid(format string, args ...any) error {
	return fmt.Errorf("%w: %s", ErrInvalid, fmt.Sprintf(format, args...))
}

// Validate requires an explicit absolute directory, excluding filesystem roots,
// the whole home directory, and ancestors of home. Symlink components are refused.
func Validate(project string) (string, error) {
	if project == "" || !filepath.IsAbs(project) || strings.ContainsRune(project, 0) {
		return "", invalid("select an absolute project directory")
	}
	project = filepath.Clean(project)
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	home = filepath.Clean(home)
	rel, err := filepath.Rel(project, home)
	if project == string(filepath.Separator) || (err == nil && rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator))) {
		return "", invalid("select one project, not a filesystem root or the whole home directory")
	}
	volume := filepath.VolumeName(project)
	current := volume + string(filepath.Separator)
	for _, part := range strings.Split(strings.TrimPrefix(project, current), string(filepath.Separator)) {
		if part == "" {
			continue
		}
		current = filepath.Join(current, part)
		info, err := os.Lstat(current)
		if err != nil {
			return "", invalid("cannot open project directory: %v", err)
		}
		if info.Mode()&os.ModeSymlink != 0 || !info.IsDir() {
			return "", invalid("project path must contain only real directories")
		}
	}
	return project, nil
}

func allowedPart(name string) bool {
	name = strings.ToLower(name)
	if strings.HasPrefix(name, ".") {
		return false
	}
	switch name {
	case "node_modules", "vendor", "bower_components", "__pycache__", "venv", "dist", "build", "target", "coverage":
		return false
	}
	stem := strings.TrimSuffix(name, filepath.Ext(name))
	switch stem {
	case "secret", "secrets", "credential", "credentials", "token", "tokens", "private_key", "id_rsa", "id_ed25519":
		return false
	}
	switch filepath.Ext(name) {
	case ".pem", ".key", ".p12", ".pfx", ".keystore":
		return false
	}
	return true
}

func editableName(name string) bool {
	name = strings.ToLower(name)
	switch name {
	case "makefile", "dockerfile", "containerfile", "readme", "license", "licence", "copying", "notice", "procfile", "gemfile", "rakefile", "go.mod", "go.sum", "cargo.lock":
		return true
	}
	switch filepath.Ext(name) {
	case ".go", ".py", ".pyi", ".js", ".mjs", ".cjs", ".jsx", ".ts", ".tsx", ".html", ".htm", ".css", ".scss", ".sass", ".less", ".json", ".jsonc", ".yaml", ".yml", ".toml", ".ini", ".cfg", ".conf", ".xml", ".svg", ".md", ".mdx", ".rst", ".txt", ".csv", ".tsv", ".tex", ".bib", ".sh", ".bash", ".zsh", ".fish", ".c", ".h", ".cc", ".cpp", ".hpp", ".rs", ".swift", ".m", ".mm", ".java", ".kt", ".kts", ".gradle", ".rb", ".php", ".lua", ".sql", ".graphql", ".gql", ".proto", ".vue", ".svelte", ".ex", ".exs", ".erl", ".hs", ".clj", ".cljs", ".r", ".jl", ".dart", ".cs", ".fs", ".vb", ".ipynb", ".lock":
		return true
	}
	return false
}

func cleanPath(path string) (string, error) {
	if path == "" || filepath.IsAbs(path) || strings.ContainsAny(path, "\\\x00\r\n") {
		return "", invalid("file path must be relative to the selected project")
	}
	for _, part := range strings.Split(path, "/") {
		if part == "" || part == "." || part == ".." || !allowedPart(part) {
			return "", invalid("file path contains a hidden, excluded or unsafe component")
		}
	}
	if !editableName(filepath.Base(path)) {
		return "", invalid("unsupported text file type")
	}
	return path, nil
}

func openProject(project string) (*os.Root, string, error) {
	canonical, err := Validate(project)
	if err != nil {
		return nil, "", err
	}
	root, err := openDirectoryNoLinks(canonical)
	if err != nil {
		return nil, "", err
	}
	info, err := root.Stat(".")
	current, checkErr := os.Lstat(canonical)
	if err != nil || checkErr != nil || current.Mode()&os.ModeSymlink != 0 || !os.SameFile(info, current) {
		root.Close()
		return nil, "", invalid("project directory changed while opening")
	}
	return root, canonical, nil
}

// Pin each directory using O_NOFOLLOW before constructing its os.Root. Merely
// Lstat-ing an absolute project and then OpenRoot-ing it would leave a race in
// which an ancestor could be replaced by a symlink between those operations.
func openDirectoryNoLinks(absolute string) (*os.Root, error) {
	current, err := os.OpenRoot(string(filepath.Separator))
	if err != nil {
		return nil, err
	}
	for _, part := range strings.Split(strings.TrimPrefix(absolute, string(filepath.Separator)), string(filepath.Separator)) {
		if part == "" {
			continue
		}
		pinned, err := current.OpenFile(part, os.O_RDONLY|syscall.O_DIRECTORY|syscall.O_NOFOLLOW, 0)
		if err != nil {
			current.Close()
			return nil, invalid("project directory changed or contains a symbolic link: %v", err)
		}
		pinnedInfo, pinErr := pinned.Stat()
		next, openErr := current.OpenRoot(part)
		if pinErr != nil || openErr != nil {
			pinned.Close()
			current.Close()
			if next != nil {
				next.Close()
			}
			return nil, invalid("cannot pin project directory")
		}
		nextInfo, statErr := next.Stat(".")
		entryInfo, entryErr := current.Lstat(part)
		pinned.Close()
		current.Close()
		if statErr != nil || entryErr != nil || entryInfo.Mode()&os.ModeSymlink != 0 || !os.SameFile(pinnedInfo, nextInfo) || !os.SameFile(pinnedInfo, entryInfo) {
			next.Close()
			return nil, invalid("project directory changed while opening")
		}
		current = next
	}
	return current, nil
}

// checkPath rejects symlinks at every component, including links staying inside
// the project. os.Root additionally prevents escapes if names change concurrently.
func checkPath(root *os.Root, path string, allowMissing bool) error {
	parts := strings.Split(path, "/")
	for i := range parts {
		info, err := root.Lstat(strings.Join(parts[:i+1], "/"))
		if errors.Is(err, fs.ErrNotExist) && allowMissing && i == len(parts)-1 {
			return nil
		}
		if err != nil {
			return invalid("cannot access file path: %v", err)
		}
		if info.Mode()&os.ModeSymlink != 0 {
			return invalid("symbolic links are not editable")
		}
		if i < len(parts)-1 && !info.IsDir() {
			return invalid("file parent is not a directory")
		}
		if i == len(parts)-1 && !info.Mode().IsRegular() {
			return invalid("only regular text files are editable")
		}
	}
	return nil
}

func validText(data []byte) bool {
	if len(data) > MaxFileBytes || !utf8.Valid(data) {
		return false
	}
	for _, b := range data {
		if b == 0 || (b < 32 && b != '\t' && b != '\n' && b != '\r' && b != '\f') || b == 127 {
			return false
		}
	}
	return true
}

func version(data []byte) string {
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}

func readAt(root *os.Root, path string) (File, fs.FileMode, error) {
	result := File{Path: path, Version: MissingVersion}
	if err := checkPath(root, path, true); err != nil {
		return result, 0, err
	}
	f, err := root.OpenFile(path, os.O_RDONLY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK, 0)
	if errors.Is(err, fs.ErrNotExist) {
		return result, 0644, nil
	}
	if err != nil {
		return result, 0, invalid("cannot read file: %v", err)
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil {
		return result, 0, err
	}
	if !info.Mode().IsRegular() || info.Size() > MaxFileBytes {
		return result, 0, invalid("file is not regular UTF-8 text within the 2 MiB limit")
	}
	data, err := io.ReadAll(io.LimitReader(f, MaxFileBytes+1))
	if err != nil {
		return result, 0, err
	}
	if !validText(data) {
		return result, 0, invalid("file is binary, invalid UTF-8 or exceeds 2 MiB")
	}
	after, err := f.Stat()
	if err != nil {
		return result, 0, err
	}
	current, err := root.Lstat(path)
	if err != nil || current.Mode()&os.ModeSymlink != 0 || !os.SameFile(info, current) || info.Size() != after.Size() || !info.ModTime().Equal(after.ModTime()) {
		return result, 0, fmt.Errorf("%w: file changed while reading", ErrConflict)
	}
	if err := checkPath(root, path, false); err != nil {
		return result, 0, err
	}
	result.Text, result.Version = string(data), version(data)
	return result, info.Mode().Perm(), nil
}

func Read(project, path string) (File, error) {
	path, err := cleanPath(path)
	if err != nil {
		return File{}, err
	}
	root, _, err := openProject(project)
	if err != nil {
		return File{}, err
	}
	defer root.Close()
	file, _, err := readAt(root, path)
	return file, err
}

func Catalog(project string) ([]string, error) {
	root, _, err := openProject(project)
	if err != nil {
		return nil, err
	}
	defer root.Close()
	files := make([]string, 0)
	visited := 0
	err = fs.WalkDir(root.FS(), ".", func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if path == "." {
			return nil
		}
		visited++
		if visited > 50000 {
			return invalid("project catalog exceeds 50000 entries; select a smaller directory")
		}
		if !allowedPart(entry.Name()) || entry.Type()&os.ModeSymlink != 0 {
			if entry.IsDir() {
				return fs.SkipDir
			}
			return nil
		}
		if entry.IsDir() {
			return nil
		}
		if !editableName(entry.Name()) {
			return nil
		}
		file, _, readErr := readAt(root, path)
		if readErr != nil || file.Version == MissingVersion {
			return nil
		}
		files = append(files, path)
		if len(files) > MaxCatalogFiles {
			return invalid("project contains more than %d editable files", MaxCatalogFiles)
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	sort.Strings(files)
	return files, nil
}

// lockProject serializes cooperating writers across goroutines and processes.
// External editors do not take this lock: their changes are checked again after
// staging, immediately before rename. No portable filesystem API can atomically
// compare arbitrary external writes and rename; an external write in that final
// tiny interval remains outside this optimistic-concurrency guarantee.
func lockProject(project string) (func(), error) {
	value, _ := projectLocks.LoadOrStore(project, &sync.Mutex{})
	mu := value.(*sync.Mutex)
	mu.Lock()
	directory := filepath.Join(os.TempDir(), fmt.Sprintf("roundtable-workspace-locks-%d", os.Getuid()))
	if err := os.Mkdir(directory, 0700); err != nil && !errors.Is(err, fs.ErrExist) {
		mu.Unlock()
		return nil, err
	}
	info, err := os.Lstat(directory)
	if err != nil || !info.IsDir() || info.Mode().Perm() != 0700 {
		mu.Unlock()
		return nil, invalid("workspace lock directory is unsafe")
	}
	if stat, ok := info.Sys().(*syscall.Stat_t); !ok || stat.Uid != uint32(os.Getuid()) {
		mu.Unlock()
		return nil, invalid("workspace lock directory has an unexpected owner")
	}
	sum := sha256.Sum256([]byte(project))
	f, err := os.OpenFile(filepath.Join(directory, hex.EncodeToString(sum[:])+".lock"), os.O_CREATE|os.O_RDWR|syscall.O_NOFOLLOW, 0600)
	if err != nil {
		mu.Unlock()
		return nil, err
	}
	if err = syscall.Flock(int(f.Fd()), syscall.LOCK_EX); err != nil {
		f.Close()
		mu.Unlock()
		return nil, err
	}
	return func() { syscall.Flock(int(f.Fd()), syscall.LOCK_UN); f.Close(); mu.Unlock() }, nil
}

// Write atomically replaces a file only if its current SHA256 version matches.
// New files require expectedVersion="missing" and an already existing parent.
func Write(project, path, text, expectedVersion string) (Change, error) {
	path, err := cleanPath(path)
	if err != nil {
		return Change{}, err
	}
	if !validText([]byte(text)) {
		return Change{}, invalid("new contents must be UTF-8 text within 2 MiB")
	}
	if expectedVersion != MissingVersion {
		decoded, decodeErr := hex.DecodeString(expectedVersion)
		if decodeErr != nil || len(decoded) != sha256.Size {
			return Change{}, invalid("expected version must be the version returned by Read")
		}
	}
	root, canonical, err := openProject(project)
	if err != nil {
		return Change{}, err
	}
	defer root.Close()
	unlock, err := lockProject(canonical)
	if err != nil {
		return Change{}, err
	}
	defer unlock()
	before, mode, err := readAt(root, path)
	if err != nil {
		return Change{}, err
	}
	if before.Version != expectedVersion {
		return Change{}, fmt.Errorf("%w: %s changed; reload it before saving", ErrConflict, path)
	}
	afterVersion := version([]byte(text))
	if before.Version == afterVersion {
		return Change{Path: path, Before: before.Version, After: afterVersion}, nil
	}
	patch, err := unifiedDiff(path, before.Text, text)
	if err != nil {
		return Change{}, err
	}
	change := Change{Path: path, Before: before.Version, After: afterVersion, Diff: patch}
	parentName := filepath.Dir(path)
	parentInfo, err := root.Lstat(parentName)
	if err != nil {
		return Change{}, invalid("new files require an existing parent directory")
	}
	parent, err := root.OpenRoot(parentName)
	if err != nil {
		return Change{}, err
	}
	defer parent.Close()
	openedInfo, err := parent.Stat(".")
	if err != nil || parentInfo.Mode()&os.ModeSymlink != 0 || !os.SameFile(parentInfo, openedInfo) {
		return Change{}, invalid("file parent changed while opening")
	}
	var random [16]byte
	if _, err = rand.Read(random[:]); err != nil {
		return Change{}, err
	}
	tempName := ".roundtable-" + hex.EncodeToString(random[:]) + ".tmp"
	staged, err := parent.OpenFile(tempName, os.O_WRONLY|os.O_CREATE|os.O_EXCL|syscall.O_NOFOLLOW, 0600)
	if err != nil {
		return Change{}, err
	}
	defer parent.Remove(tempName)
	if _, err = io.WriteString(staged, text); err == nil {
		err = staged.Chmod(mode)
	}
	if err == nil {
		err = staged.Sync()
	}
	closeErr := staged.Close()
	if err != nil {
		return Change{}, err
	}
	if closeErr != nil {
		return Change{}, closeErr
	}
	current, _, err := readAt(root, path)
	if err != nil {
		return Change{}, err
	}
	if current.Version != before.Version {
		return Change{}, fmt.Errorf("%w: file changed before save", ErrConflict)
	}
	currentParent, err := root.Lstat(parentName)
	if err != nil || currentParent.Mode()&os.ModeSymlink != 0 || !os.SameFile(parentInfo, currentParent) {
		return Change{}, fmt.Errorf("%w: file parent changed before save", ErrConflict)
	}
	currentProject, err := os.Lstat(canonical)
	openedProject, statErr := root.Stat(".")
	if err != nil || statErr != nil || currentProject.Mode()&os.ModeSymlink != 0 || !os.SameFile(currentProject, openedProject) {
		return Change{}, fmt.Errorf("%w: selected project changed before save", ErrConflict)
	}
	if err = parent.Rename(tempName, filepath.Base(path)); err != nil {
		return Change{}, err
	}
	// A successful rename is the commit. Directory fsync is best effort because
	// some filesystems do not support it; a post-commit failure must not look like
	// an uncommitted write to callers.
	if directory, openErr := parent.Open("."); openErr == nil {
		directory.Sync()
		directory.Close()
	}
	return change, nil
}
