package workspace

import (
	"bytes"
	"errors"
	"io"
	"io/fs"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

const MaxMaterialTextBytes = 1_500_000
const maxMaterialEntries = 50000

var materialDirectories = []string{"code", "data", "figures", "outputs"}

type MaterialFile struct {
	Path     string    `json:"path"`
	Kind     string    `json:"kind"`
	Size     int64     `json:"size"`
	Modified time.Time `json:"modified"`
}

func materialPath(path string) bool {
	if filepath.IsAbs(path) || strings.ContainsAny(path, "\\\x00\r\n") {
		return false
	}
	group, _, ok := strings.Cut(path, "/")
	if !ok {
		return false
	}
	switch group {
	case "code", "data", "figures", "outputs":
	default:
		return false
	}
	for _, part := range strings.Split(path, "/") {
		if part == "" || !allowedPart(part) {
			return false
		}
	}
	return true
}

func materialInfo(path string, info fs.FileInfo) MaterialFile {
	kind := "other"
	switch strings.ToLower(filepath.Ext(path)) {
	case ".md", ".markdown":
		kind = "markdown"
	case ".py":
		kind = "python"
	case ".png", ".jpg", ".jpeg", ".gif", ".webp", ".tiff", ".tif", ".heic":
		kind = "image"
	case ".pdf":
		kind = "pdf"
	case ".npy", ".npz", ".h5", ".hdf5", ".parquet", ".feather", ".sqlite", ".db":
		kind = "data"
	default:
		if editableName(filepath.Base(path)) || strings.EqualFold(filepath.Ext(path), ".log") {
			kind = "text"
		}
	}
	return MaterialFile{Path: path, Kind: kind, Size: info.Size(), Modified: info.ModTime()}
}

// MaterialCatalog describes the real project collections without reading their
// contents. It shares the workspace exclusions and never follows symlinks.
func MaterialCatalog(project string) ([]MaterialFile, error) {
	root, _, err := openProject(project)
	if err != nil {
		return nil, err
	}
	defer root.Close()
	files := []MaterialFile{}
	visited := 0
	for _, group := range materialDirectories {
		info, err := root.Lstat(group)
		if errors.Is(err, fs.ErrNotExist) || err == nil && !info.IsDir() {
			continue
		}
		if err != nil {
			return nil, err
		}
		err = fs.WalkDir(root.FS(), group, func(path string, entry fs.DirEntry, err error) error {
			if err != nil || path == group {
				return err
			}
			visited++
			if visited > maxMaterialEntries {
				return invalid("project material catalog exceeds the file limit")
			}
			if !materialPath(path) {
				if entry.IsDir() {
					return fs.SkipDir
				}
				return nil
			}
			if !entry.Type().IsRegular() {
				return nil
			}
			info, err := entry.Info()
			if err != nil {
				return err
			}
			if !info.Mode().IsRegular() {
				return nil
			}
			if len(files) >= MaxCatalogFiles {
				return invalid("project material catalog exceeds the file limit")
			}
			files = append(files, materialInfo(path, info))
			return nil
		})
		if err != nil {
			return nil, err
		}
	}
	return files, nil
}

func openMaterial(project, path string) (*os.File, string, MaterialFile, error) {
	var item MaterialFile
	if !materialPath(path) {
		return nil, "", item, invalid("file is outside the project material collections")
	}
	root, canonical, err := openProject(project)
	if err != nil {
		return nil, "", item, err
	}
	defer root.Close()
	if err = checkPath(root, path, false); err != nil {
		return nil, "", item, err
	}
	f, err := root.OpenFile(path, os.O_RDONLY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK, 0)
	if err != nil {
		return nil, "", item, err
	}
	info, err := f.Stat()
	current, currentErr := root.Lstat(path)
	if err != nil || currentErr != nil || !info.Mode().IsRegular() || !os.SameFile(info, current) {
		f.Close()
		return nil, "", item, invalid("project file changed while opening")
	}
	if err = checkPath(root, path, false); err != nil {
		f.Close()
		return nil, "", item, err
	}
	return f, filepath.Join(canonical, path), materialInfo(path, info), nil
}

// MaterialPreview exposes only inert UTF-8, raster images and PDF bytes.
func MaterialPreview(project, path string) (*os.File, MaterialFile, string, error) {
	f, _, item, err := openMaterial(project, path)
	if err != nil {
		return nil, item, "", err
	}
	mediaType, err := materialPreviewType(f, item)
	if err != nil {
		f.Close()
		return nil, item, "", err
	}
	return f, item, mediaType, nil
}

func materialPreviewType(f *os.File, item MaterialFile) (string, error) {
	switch item.Kind {
	case "text", "markdown", "python":
		if item.Size > MaxMaterialTextBytes {
			return "", invalid("file exceeds the inline text limit")
		}
		data, err := io.ReadAll(io.NewSectionReader(f, 0, MaxMaterialTextBytes+1))
		if err != nil {
			return "", err
		}
		if len(data) > MaxMaterialTextBytes || !validText(data) {
			return "", invalid("file is not readable UTF-8 text")
		}
		return "text/plain; charset=utf-8", nil
	case "image", "pdf":
		header := make([]byte, 512)
		n, err := f.ReadAt(header, 0)
		if err != nil && err != io.EOF {
			return "", err
		}
		detected := materialMediaType(header[:n])
		switch detected {
		case "image/png", "image/jpeg", "image/gif", "image/webp", "image/tiff", "image/heic":
			if item.Kind == "image" {
				return detected, nil
			}
		case "application/pdf":
			if item.Kind == "pdf" {
				return detected, nil
			}
		}
	}
	return "", invalid("file type is unavailable for inline preview")
}

func materialMediaType(header []byte) string {
	switch {
	case bytes.HasPrefix(header, []byte("II*\x00")), bytes.HasPrefix(header, []byte("MM\x00*")):
		return "image/tiff"
	case len(header) >= 16 && string(header[4:8]) == "ftyp":
		switch string(header[8:12]) {
		case "heic", "heix", "hevc", "hevx":
			return "image/heic"
		}
	}
	return http.DetectContentType(header)
}

// MaterialLocation resolves a single regular file immediately before a
// user-initiated handoff to a desktop application.
func MaterialLocation(project, path string) (string, MaterialFile, error) {
	f, target, item, err := openMaterial(project, path)
	if err != nil {
		return "", item, err
	}
	defer f.Close()
	info, err := f.Stat()
	current, currentErr := os.Lstat(target)
	if err != nil || currentErr != nil || !os.SameFile(info, current) || current.Mode()&os.ModeSymlink != 0 {
		return "", item, invalid("project path changed before opening")
	}
	return target, item, nil
}
