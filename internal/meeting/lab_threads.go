package meeting

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"unicode/utf8"

	"scistation.local/desktop/internal/credentials"
	"scistation.local/desktop/internal/workspace"
)

// LabThread is optional presentation metadata on a single-seat session.
// Archiving a thread does not change its scheduler or report state.
type LabThread struct {
	Title      string `json:"title,omitempty"`
	ArchivedAt string `json:"archived_at,omitempty"`
	Revision   int    `json:"revision"`
}

type LabScope struct {
	ProjectID              string
	Global                 bool
	ConversationGeneration uint64
}

func (s LabScope) owns(room *Session) bool {
	if len(room.Seats) != 1 {
		return false
	}
	if s.Global {
		return s.ProjectID == "" && room.isGlobal()
	}
	return s.ProjectID != "" && room.ProjectID == s.ProjectID
}

func (e *Engine) scopedLabThread(scope LabScope, id string) (*Session, error) {
	s, err := e.load(id)
	if err != nil {
		return nil, err
	}
	if !scope.owns(s) {
		return nil, os.ErrNotExist
	}
	return s, nil
}

type LabThreadChange struct {
	Action   string `json:"action"`
	Title    string `json:"title"`
	Revision *int   `json:"revision"`
}

func (e *Engine) ChangeLabThread(scope LabScope, id string, change LabThreadChange) (*Session, error) {
	if change.Revision == nil || *change.Revision < 0 {
		return nil, errors.New("需要当前会话的版本")
	}
	change.Title = strings.Join(strings.Fields(change.Title), " ")
	if change.Action == "rename" {
		if change.Title == "" || utf8.RuneCountInString(change.Title) > 96 || strings.ContainsRune(change.Title, 0) {
			return nil, errors.New("会话名称须为 1 至 96 字")
		}
		if credentials.ContainsSecret(change.Title) {
			return nil, credentials.ErrSecretInPrompt
		}
	}
	var result *Session
	err := e.locked(func() error {
		s, err := e.scopedLabThread(scope, id)
		if err != nil {
			return err
		}
		var meta LabThread
		if s.LabThread != nil {
			meta = *s.LabThread
		}
		if *change.Revision != meta.Revision {
			return fmt.Errorf("%w: 会话名称或归档状态已更新", ErrConflict)
		}
		next := meta
		switch change.Action {
		case "rename":
			next.Title = change.Title
		case "archive":
			if next.ArchivedAt == "" {
				next.ArchivedAt = now()
			}
		case "restore":
			next.ArchivedAt = ""
		default:
			return errors.New("未知的会话操作")
		}
		if next != meta {
			next.Revision++
			s.LabThread = &next
			if err = e.save(s); err != nil {
				return err
			}
		}
		result = s
		return nil
	})
	return result, err
}

type LabDraft struct {
	Text     string `json:"text"`
	Revision int    `json:"revision"`
}

type labDraftRecord struct {
	SchemaVersion int `json:"schema_version"`
	LabDraft
}

func validLabDraftText(text string) bool {
	return utf8.ValidString(text) && utf8.RuneCountInString(text) <= 2500 && !strings.ContainsRune(text, 0)
}

func (e *Engine) labDraftPath(projectID, id string) string {
	digest := sha256.Sum256([]byte(projectID + "\x00" + id))
	return filepath.Join(e.dir, "lab-drafts", hex.EncodeToString(digest[:])+".json")
}

func readLabDraft(path string) (LabDraft, error) {
	data, err := workspace.ManagedReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return LabDraft{}, nil
	}
	if err != nil {
		return LabDraft{}, err
	}
	var record struct {
		SchemaVersion int     `json:"schema_version"`
		Text          *string `json:"text"`
		Revision      int     `json:"revision"`
	}
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	if !utf8.Valid(data) || decoder.Decode(&record) != nil || decoder.Decode(new(any)) != io.EOF ||
		record.SchemaVersion != 1 || record.Revision < 1 || record.Text == nil ||
		!validLabDraftText(*record.Text) || credentials.ContainsSecret(*record.Text) {
		return LabDraft{}, errors.New("本地草稿格式无效，请检查后重试")
	}
	return LabDraft{Text: *record.Text, Revision: record.Revision}, nil
}

// LabDraft keeps unsent text outside the session archive. Opening a thread,
// generating a model request or exporting a replay never consumes this file.
func (e *Engine) LabDraft(scope LabScope, id string, edit *LabDraft) (LabDraft, error) {
	if scope.Global != (scope.ProjectID == "") {
		return LabDraft{}, errors.New("草稿需要一个明确的会话范围")
	}
	if edit != nil {
		if !validLabDraftText(edit.Text) || edit.Revision < 0 {
			return LabDraft{}, errors.New("草稿须为不超过 2,500 字的文本，并携带版本")
		}
		if credentials.ContainsSecret(edit.Text) {
			return LabDraft{}, credentials.ErrSecretInPrompt
		}
	}
	var result LabDraft
	err := e.locked(func() error {
		if err := e.checkConversationGeneration(scope.ProjectID, scope.ConversationGeneration); err != nil {
			return err
		}
		if id != "" {
			if _, err := e.scopedLabThread(scope, id); err != nil {
				return err
			}
		}
		path := e.labDraftPath(scope.ProjectID, id)
		current, err := readLabDraft(path)
		if err != nil {
			return err
		}
		result = current
		if edit == nil {
			return nil
		}
		if edit.Revision != current.Revision {
			return fmt.Errorf("%w: 草稿已在另一处更新", ErrConflict)
		}
		if edit.Text == current.Text {
			return nil
		}
		result = LabDraft{Text: edit.Text, Revision: current.Revision + 1}
		data, err := json.Marshal(labDraftRecord{SchemaVersion: 1, LabDraft: result})
		if err != nil {
			return err
		}
		if err = workspace.ManagedMkdirAll(filepath.Dir(path), 0700); err != nil {
			return err
		}
		return workspace.ManagedAtomicWrite(path, append(data, '\n'))
	})
	return result, err
}
