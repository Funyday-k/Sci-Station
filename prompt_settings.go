package main

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"slices"
	"strings"
	"unicode/utf8"

	"scistation.local/desktop/internal/credentials"
	"scistation.local/desktop/internal/meeting"
)

type promptTemplate struct {
	meeting.PromptOverride
	Title       string `json:"title"`
	Description string `json:"description,omitempty"`
	Enabled     bool   `json:"enabled"`
	Active      bool   `json:"active"`
}

type promptLibrary struct {
	SchemaVersion int              `json:"schema_version"`
	Revision      int              `json:"revision"`
	Templates     []promptTemplate `json:"templates"`
}

func (l *promptLibrary) snapshot() promptLibrary {
	if l == nil {
		return promptLibrary{SchemaVersion: 1, Templates: []promptTemplate{}}
	}
	out := *l
	out.Templates = append([]promptTemplate{}, l.Templates...)
	return out
}

func (l *promptLibrary) activeOverrides() map[meeting.PromptSurface]*meeting.PromptOverride {
	if l == nil {
		return nil
	}
	resolved := map[meeting.PromptSurface]*meeting.PromptOverride{}
	for _, t := range l.Templates {
		if t.Enabled && t.Active {
			override := t.PromptOverride
			resolved[t.Surface] = &override
		}
	}
	return resolved
}

func (t *promptTemplate) normalize() {
	t.Title = strings.TrimSpace(t.Title)
	t.Description = strings.TrimSpace(t.Description)
	t.System = strings.TrimSpace(strings.ReplaceAll(t.System, "\r\n", "\n"))
	t.Body = strings.TrimSpace(strings.ReplaceAll(t.Body, "\r\n", "\n"))
}

func (t promptTemplate) validate() error {
	if !t.Surface.Valid() || t.Title == "" || t.Body == "" || (t.Active && !t.Enabled) {
		return errors.New("提示词需要有效的用途、名称和正文，启用后才能设为当前模板")
	}
	for _, field := range []struct {
		text  string
		limit int
	}{
		{t.Title, 80}, {t.Description, 1000}, {t.System, 4000}, {t.Body, 6500},
	} {
		if strings.ContainsRune(field.text, 0) || !utf8.ValidString(field.text) || utf8.RuneCountInString(field.text) > field.limit {
			return errors.New("提示词内容过长或包含无效字符")
		}
		if credentials.ContainsSecret(field.text) {
			return credentials.ErrSecretInPrompt
		}
	}
	return nil
}

func (t promptTemplate) digest() string {
	data, _ := json.Marshal([]string{t.ID, string(t.Surface), t.Title, t.Description, t.System, t.Body})
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}

func (l *promptLibrary) validate() error {
	if l == nil {
		return nil
	}
	if l.SchemaVersion != 1 || l.Revision < 1 || len(l.Templates) > 32 {
		return errors.New("工作区提示词库版本或模板数量无效")
	}
	ids := map[string]bool{}
	active := map[meeting.PromptSurface]bool{}
	for _, t := range l.Templates {
		if err := t.validate(); err != nil {
			return err
		}
		if t.ID == "" || ids[t.ID] || t.Version < 1 || t.Digest != t.digest() || (t.Active && active[t.Surface]) {
			return errors.New("工作区提示词库包含无效或重复的模板")
		}
		ids[t.ID] = true
		active[t.Surface] = active[t.Surface] || t.Active
	}
	return nil
}

type promptPatchInput struct {
	Revision int            `json:"revision"`
	Action   string         `json:"action"`
	Template promptTemplate `json:"template"`
}

type promptPatchReview struct {
	ID        string                `json:"id"`
	Surface   meeting.PromptSurface `json:"surface"`
	Source    string                `json:"source"`
	Rationale string                `json:"rationale"`
	Changes   []promptPatchChange   `json:"changes"`
	next      promptLibrary
}

type promptPatchChange struct {
	Before *promptTemplate `json:"before"`
	After  *promptTemplate `json:"after"`
}

func supportedPromptPatch(l promptLibrary, in promptPatchInput) (promptPatchReview, error) {
	review := promptPatchReview{ID: rand.Text(), Source: "工作区设置", Surface: in.Template.Surface}
	if in.Revision != l.Revision {
		return review, fmt.Errorf("%w: 提示词库已更新，请重新加载", meeting.ErrConflict)
	}
	previous := l.snapshot()
	draft := in.Template
	i := slices.IndexFunc(l.Templates, func(t promptTemplate) bool { return t.ID == draft.ID })
	switch in.Action {
	case "edit", "suggest":
		review.Rationale = "应用此模板草稿。"
		draft.normalize()
		if in.Action == "suggest" {
			review.Source = "内置证据指引"
			review.Rationale = "加入证据、范围与结果不确定性的说明。"
			for _, line := range []string{
				"Distinguish evidence in the supplied sources from assumptions, examples, and inference.",
				"Identify the evidence behind scientific claims and state which claims still require verification.",
				"Describe the target and the required user review for proposed writebacks.",
			} {
				if !strings.Contains(draft.Body, line) {
					draft.Body = strings.TrimSpace(draft.Body + "\n" + line)
				}
			}
		}
		if err := draft.validate(); err != nil {
			return review, err
		}
		if draft.ID == "" {
			draft.ID, draft.Version = rand.Text(), 1
		} else if i < 0 {
			return review, fmt.Errorf("%w: 找不到所选提示词", meeting.ErrConflict)
		} else if l.Templates[i].Surface != draft.Surface {
			return review, errors.New("已有模板的用途不能更改，请新建模板")
		} else {
			stored := l.Templates[i]
			draft.Version = stored.Version
			if stored.Digest != draft.digest() {
				draft.Version++
			}
		}
		draft.Digest = draft.digest()
		if draft.Active {
			for j := range l.Templates {
				if l.Templates[j].Surface == draft.Surface {
					l.Templates[j].Active = false
				}
			}
		}
		if i < 0 {
			l.Templates = append(l.Templates, draft)
		} else {
			l.Templates[i] = draft
		}
	case "restore":
		if !draft.Surface.Valid() {
			return review, errors.New("请选择提示词用途")
		}
		review.Rationale = "恢复此用途的内置提示词，已保存的模板可再次启用。"
		for j := range l.Templates {
			if l.Templates[j].Surface == draft.Surface {
				l.Templates[j].Active = false
			}
		}
	case "remove":
		if i < 0 || l.Templates[i].Surface != draft.Surface {
			return review, fmt.Errorf("%w: 找不到所选提示词", meeting.ErrConflict)
		}
		review.Rationale = "移除此模板。移除当前模板后将使用该用途的内置提示词。"
		l.Templates = slices.Delete(l.Templates, i, i+1)
	default:
		return review, errors.New("不支持此提示词操作")
	}
	for _, before := range previous.Templates {
		pos := slices.IndexFunc(l.Templates, func(t promptTemplate) bool { return t.ID == before.ID })
		if pos < 0 {
			review.Changes = append(review.Changes, promptPatchChange{Before: &before})
		} else if after := l.Templates[pos]; before != after {
			review.Changes = append(review.Changes, promptPatchChange{Before: &before, After: &after})
		}
	}
	if (in.Action == "edit" || in.Action == "suggest") && i < 0 {
		review.Changes = append(review.Changes, promptPatchChange{After: &draft})
	}
	if len(review.Changes) == 0 {
		return review, errors.New("提示词库没有修改")
	}
	l.Revision++
	review.next = l
	return review, l.validate()
}

func (a *apiServer) servePromptSettings(w http.ResponseWriter, r *http.Request, path string) {
	if a.prefs == nil {
		reject(w, 503, "未打开应用设置")
		return
	}
	if path == "prompt-settings" && r.Method == "GET" {
		reply(w, 200, a.prefs.get().PromptLibrary.snapshot())
		return
	}
	if r.Method != "POST" {
		reject(w, 405, "不支持此请求")
		return
	}
	s := a.prefs
	switch path {
	case "prompt-settings/preview":
		var in promptPatchInput
		if !jsonBody(w, r, &in) {
			return
		}
		s.mu.Lock()
		defer s.mu.Unlock()
		review, err := supportedPromptPatch(s.prefs.PromptLibrary.snapshot(), in)
		if err != nil {
			fail(w, err)
			return
		}
		s.promptPreview = &review
		reply(w, 200, review)
	case "prompt-settings/decision":
		var in struct {
			ID     string `json:"id"`
			Action string `json:"action"`
		}
		if !jsonBody(w, r, &in) {
			return
		}
		if in.Action != "apply" && in.Action != "discard" {
			reject(w, 400, "请选择应用或丢弃预览")
			return
		}
		s.mu.Lock()
		defer s.mu.Unlock()
		review := s.promptPreview
		if review == nil || review.ID != in.ID || review.next.Revision != s.prefs.PromptLibrary.snapshot().Revision+1 {
			reject(w, 409, "此预览已失效，请重新生成并核对")
			return
		}
		if in.Action == "apply" {
			next := s.prefs
			next.PromptLibrary = &review.next
			if err := s.writeLocked(next); err != nil {
				reject(w, 500, "提示词库保存失败，请重试")
				return
			}
		}
		s.promptPreview = nil
		reply(w, 200, s.prefs.PromptLibrary.snapshot())
	default:
		http.NotFound(w, r)
	}
}
