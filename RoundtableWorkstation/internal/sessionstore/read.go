package sessionstore

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

var validID = regexp.MustCompile(`^[0-9a-f]{32}$`)

func ValidID(id string) bool { return validID.MatchString(id) }

// Unreadable identifies a problem in a single stored session. Directory, lock,
// and I/O errors are kept separate so callers can report a storage failure.
type Unreadable struct {
	ID     string `json:"id"`
	Path   string `json:"path"`
	Reason string `json:"reason"`
}

func (e *Unreadable) Error() string {
	return fmt.Sprintf("无法读取圆桌 %s。请在侧栏的存档恢复中查看位置。", e.ID)
}

func UnreadableFile(dir, id, reason string) *Unreadable {
	return &Unreadable{ID: id, Path: filepath.Join(dir, id+".json"), Reason: reason}
}

func IDs(dir string) ([]string, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}
	var ids []string
	for _, entry := range entries {
		if id, ok := strings.CutSuffix(entry.Name(), ".json"); ok && ValidID(id) {
			ids = append(ids, id)
		}
	}
	return ids, nil
}

func Read(dir, id string, target any) error {
	if !ValidID(id) {
		return fmt.Errorf("invalid session ID: %w", os.ErrNotExist)
	}
	path := filepath.Join(dir, id+".json")
	info, err := os.Lstat(path)
	if err != nil {
		return err
	}
	if !info.Mode().IsRegular() {
		return UnreadableFile(dir, id, "存档位置应为普通文件。")
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	if err := json.Unmarshal(data, target); err != nil {
		return UnreadableFile(dir, id, "存档内容无法解析。")
	}
	return nil
}
