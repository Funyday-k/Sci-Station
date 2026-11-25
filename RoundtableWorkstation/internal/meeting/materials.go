package meeting

import (
	"archive/zip"
	"bytes"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"mime"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"unicode/utf8"

	"scistation.local/desktop/internal/workspace"
)

var ErrMaterialTooLarge = errors.New("material exceeds 12 MiB")

const (
	MaxMaterialBytes        = 12 << 20
	maxMaterialExcerptRunes = 4000
)

type Material struct {
	AddedRound int    `json:"added_round,omitempty"` // 0 denotes a material provided when the meeting was created.
	ID         string `json:"id"`
	Name       string `json:"name"`
	MIME       string `json:"mime"`
	Excerpt    string `json:"excerpt"`
	Size       int64  `json:"size"`
	ReadStatus string `json:"read_status,omitempty"`
}

const (
	MaterialReadText     = "text"
	MaterialReadFailed   = "failed"
	MaterialReadOriginal = "original_only"
	MaterialReadNoText   = "no_extractable_text"
)

// StoreMaterial retains an original attachment and bounded, searchable metadata.
func (e *Engine) StoreMaterial(name string, src io.Reader) (Material, error) {
	if src == nil {
		return Material{}, errors.New("material reader is required")
	}
	data, err := io.ReadAll(io.LimitReader(src, MaxMaterialBytes+1))
	if err != nil {
		return Material{}, err
	}
	if len(data) > MaxMaterialBytes {
		return Material{}, ErrMaterialTooLarge
	}
	name = materialName(name)
	contentType := http.DetectContentType(data)
	if strings.EqualFold(filepath.Ext(name), ".docx") && isDOCXPackage(data) {
		contentType = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
	} else if contentType == "application/octet-stream" && len(data) > 0 {
		if ext := strings.ToLower(filepath.Ext(name)); ext == ".txt" || ext == ".md" || ext == ".csv" || ext == ".log" {
			contentType = mime.TypeByExtension(ext)
			if contentType == "" {
				contentType = "text/plain"
			}
		}
	}
	contentType = strings.TrimSpace(strings.Split(contentType, ";")[0])
	m := Material{ID: newMaterialID(), Name: name, MIME: contentType, Size: int64(len(data)), ReadStatus: MaterialReadOriginal}
	root := filepath.Join(e.dir, "materials")
	if err := workspace.ManagedMkdirAll(root, 0700); err != nil {
		return Material{}, err
	}
	dir := filepath.Join(root, m.ID)
	if err := workspace.ManagedMkdir(dir, 0700); err != nil {
		return Material{}, err
	}
	ok := false
	defer func() {
		if !ok {
			_ = workspace.ManagedRemoveAll(dir)
		}
	}()
	if err := workspace.ManagedAtomicWrite(filepath.Join(dir, "original"), data); err != nil {
		return Material{}, err
	}
	if isNativeMaterialType(contentType, name) {
		excerpt, extractErr := nativeMaterialExcerpt(filepath.Join(dir, "original"), contentType, name)
		if extractErr != nil {
			m.ReadStatus = MaterialReadFailed
		} else if strings.TrimSpace(excerpt) == "" {
			m.ReadStatus = MaterialReadNoText
		} else {
			m.Excerpt, m.ReadStatus = boundedExcerpt(excerpt), MaterialReadText
		}
	} else if strings.HasPrefix(contentType, "text/") && utf8.Valid(data) && plainText(data) {
		m.Excerpt = boundedExcerpt(strings.TrimPrefix(string(data), "\ufeff"))
		if m.Excerpt == "" {
			m.ReadStatus = MaterialReadNoText
		} else {
			m.ReadStatus = MaterialReadText
		}
	} else {
		m.ReadStatus = MaterialReadOriginal
	}
	meta, err := json.Marshal(m)
	if err != nil {
		return Material{}, err
	}
	if err := workspace.ManagedAtomicWrite(filepath.Join(dir, "metadata.json"), meta); err != nil {
		return Material{}, err
	}
	ok = true
	return m, nil
}

func (e *Engine) FindMaterial(id string) (Material, error) {
	if !validMaterialID(id) {
		return Material{}, os.ErrNotExist
	}
	b, err := workspace.ManagedReadFile(filepath.Join(e.dir, "materials", id, "metadata.json"))
	if err != nil {
		return Material{}, err
	}
	var m Material
	if err := json.Unmarshal(b, &m); err != nil {
		return Material{}, err
	}
	if m.ID != id {
		return Material{}, os.ErrNotExist
	}
	return m, nil
}

func (e *Engine) OpenMaterial(id string) (*os.File, error) {
	if _, err := e.FindMaterial(id); err != nil {
		return nil, err
	}
	return workspace.ManagedOpenFile(filepath.Join(e.dir, "materials", id, "original"), os.O_RDONLY, 0)
}

func materialName(name string) string {
	name = strings.ReplaceAll(name, "\\", "/")
	name = filepath.Base(strings.TrimSpace(name))
	name = strings.Map(func(r rune) rune {
		if r < 32 || r == 127 {
			return -1
		}
		return r
	}, name)
	name = strings.Trim(name, ". ")
	if name == "" || name == "/" {
		return "attachment"
	}
	if utf8.RuneCountInString(name) > 180 {
		name = string([]rune(name)[:180])
	}
	return name
}

func plainText(data []byte) bool {
	for _, b := range data {
		if b == 0 {
			return false
		}
	}
	return true
}

func boundedExcerpt(s string) string {
	s = strings.TrimSpace(s)
	if len(s) == 0 {
		return ""
	}
	count, offset := 0, 0
	for offset < len(s) && count < maxMaterialExcerptRunes {
		_, size := utf8.DecodeRuneInString(s[offset:])
		offset += size
		count++
	}
	if offset < len(s) {
		s = s[:offset]
	}
	return s
}

func isNativeMaterialType(contentType, name string) bool {
	ext := strings.ToLower(filepath.Ext(name))
	return strings.HasPrefix(contentType, "image/") || contentType == "application/pdf" || strings.Contains(contentType, "officedocument") || strings.Contains(contentType, "msword") || strings.Contains(contentType, "ms-excel") || strings.Contains(contentType, "ms-powerpoint") || ext == ".pages" || ext == ".numbers" || ext == ".key"
}

func isDOCXPackage(data []byte) bool {
	z, err := zip.NewReader(bytes.NewReader(data), int64(len(data)))
	if err != nil {
		return false
	}
	for _, f := range z.File {
		if f.Name == "word/document.xml" {
			return true
		}
	}
	return false
}

func newMaterialID() string {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		panic(err)
	}
	return hex.EncodeToString(b[:])
}

func validMaterialID(id string) bool {
	if len(id) != 32 {
		return false
	}
	b, err := hex.DecodeString(id)
	return err == nil && len(b) == 16
}
