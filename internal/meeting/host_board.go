package meeting

import (
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"strings"
	"unicode/utf8"
)

// Each title, module, agenda item and annotation has its own revision. Older
// saved sessions start at revision zero and acquire revisions as they change.
type BoardAnnotation struct {
	Body string `json:"body"`
	BoardSource
}

type BoardChangeSummary struct {
	Op         string `json:"op"`
	TargetID   string `json:"target_id"`
	Before     string `json:"before"`
	After      string `json:"after"`
	SourceSeat string `json:"source_seat"`
	Version    int    `json:"version"`
}

type HostBoardChange struct {
	Op              string    `json:"op"`
	ModuleID        string    `json:"module_id,omitempty"`
	ItemID          string    `json:"item_id,omitempty"`
	PointID         string    `json:"point_id,omitempty"`
	MaterialID      string    `json:"material_id,omitempty"`
	Title           *string   `json:"title,omitempty"`
	Body            *string   `json:"body,omitempty"`
	MaterialIDs     *[]string `json:"material_ids,omitempty"`
	ExpectedVersion *int      `json:"expected_version,omitempty"`
}

func (c *HostBoardChange) UnmarshalJSON(raw []byte) error {
	type plain HostBoardChange
	var header struct{ Op string }
	if err := json.Unmarshal(raw, &header); err != nil {
		return err
	}
	fields := []string{"op", "expected_version"}
	switch header.Op {
	case "rename_board":
		fields = append(fields, "title")
	case "add_note", "revise_module":
		fields = append(fields, "module_id", "title", "body", "material_ids")
	case "edit_agenda":
		fields = append(fields, "item_id", "title")
	case "annotate_point":
		fields = append(fields, "point_id", "body")
	case "annotate_material":
		fields = append(fields, "material_id", "body")
	default:
		return errors.New("不支持这个议题板操作")
	}
	if !boardObject(raw, (*plain)(c), fields...) {
		return errors.New("议题板操作含无效字段")
	}
	return nil
}

func (e *Engine) ChangeBoard(id string, c HostBoardChange) (*Session, error) {
	var result *Session
	err := e.locked(func() error {
		s, err := e.load(id)
		if err != nil {
			return err
		}
		if err = e.recover(s); err != nil {
			return err
		}
		result = s // Also return the matching current value on conflicts.
		if err = s.requireOpen(); err != nil {
			return err
		}
		if c.Op != "add_note" && (c.ExpectedVersion == nil || *c.ExpectedVersion < 0) {
			return errors.New("请携带当前编辑项的版本")
		}
		summary, err := c.apply(s)
		if err != nil || summary == nil {
			return err
		}
		s.Board.rememberChange(*summary)
		return e.save(s)
	})
	return result, err
}

func (c HostBoardChange) checkVersion(current int) error {
	if c.ExpectedVersion == nil || *c.ExpectedVersion != current {
		return fmt.Errorf("%w: 此项内容已有更新，请核对最新版本后再保存", ErrConflict)
	}
	return nil
}

func (c HostBoardChange) summary(id, before, after string, version int) *BoardChangeSummary {
	// Keep the actual difference visible when only the end of a long review
	// changes. The full values remain available on the corresponding entity.
	oldText, newText := []rune(before), []rune(after)
	common := 0
	for common < len(oldText) && common < len(newText) && oldText[common] == newText[common] {
		common++
	}
	const limit = 180
	excerpt := func(value []rune) string {
		if len(value) <= limit {
			return string(value)
		}
		start := max(0, min(common-40, len(value)-limit+1))
		if start == 0 {
			return string(value[:limit-1]) + "…"
		}
		return "…" + shorten(string(value[start:]), limit-2)
	}
	return &BoardChangeSummary{Op: c.Op, TargetID: id, Before: excerpt(oldText), After: excerpt(newText), SourceSeat: "user", Version: version}
}

func (b *MeetingBoard) rememberChange(change BoardChangeSummary) {
	const limit = 12
	for i, prev := range b.RecentChanges {
		sameModule := (prev.Op == "add_note" || prev.Op == "revise_module") && change.Op == "revise_module"
		if prev.TargetID == change.TargetID && (prev.Op == change.Op || sameModule) {
			if prev.Version+1 == change.Version && prev.Before != change.After {
				change.Before = prev.Before
			}
			b.RecentChanges = slices.Delete(b.RecentChanges, i, i+1)
			break
		}
	}
	b.RecentChanges = append(b.RecentChanges, change)
	if len(b.RecentChanges) > limit {
		b.RecentChanges = b.RecentChanges[len(b.RecentChanges)-limit:]
	}
}

func (c HostBoardChange) apply(s *Session) (*BoardChangeSummary, error) {
	switch c.Op {
	case "rename_board":
		if c.Title == nil || !validBoardTitle(strings.TrimSpace(*c.Title)) {
			return nil, fmt.Errorf("标题须为 1 至 %d 个字符", maxBoardTitle)
		}
		title := strings.TrimSpace(*c.Title)
		if title == s.Board.Title {
			return nil, nil
		}
		if err := c.checkVersion(s.Board.Version); err != nil {
			return nil, err
		}
		change := c.summary("board", s.Board.Title, title, s.Board.Version+1)
		s.Board.Title, s.Title = title, title
		s.Board.BoardSource = BoardSource{SourceSeat: "user", Version: change.Version}
		return change, nil
	case "add_note", "revise_module":
		return c.editModule(s)
	case "edit_agenda":
		return c.editAgenda(s)
	case "annotate_material", "annotate_point":
		return c.annotate(s)
	default:
		return nil, errors.New("不支持这个议题板操作")
	}
}

func (t BoardText) summary() string {
	var parts []string
	for _, value := range []string{t.Title, t.Body, strings.Join(t.MaterialIDs, ", ")} {
		if value != "" {
			parts = append(parts, value)
		}
	}
	return strings.Join(parts, "\n")
}

func validNoteID(id string) bool {
	if len(id) == 36 && id[8] == '-' && id[13] == '-' && id[18] == '-' && id[23] == '-' {
		id = strings.ReplaceAll(id, "-", "")
	}
	if len(id) != 32 {
		return false
	}
	_, err := hex.DecodeString(id)
	return err == nil
}

func (c HostBoardChange) editModule(s *Session) (*BoardChangeSummary, error) {
	module := s.Board.module(c.ModuleID)
	create := c.Op == "add_note"
	newPreset := false
	if !create && module == nil {
		// A client that opened a former default layout may still explicitly
		// author one of its preset modules while the chair is drafting.
		if preset, ok := presetBoardModule(c.ModuleID); ok {
			module, newPreset = &preset, true
		}
	}
	if create && (!validNoteID(c.ModuleID) || c.Title == nil || c.Body == nil) {
		return nil, errors.New("新增笔记需要有效编号、标题及正文")
	}
	if !create && (module == nil || (c.Title == nil && c.Body == nil && c.MaterialIDs == nil)) {
		return nil, errors.New("请指定现有模块及要保存的内容")
	}
	kind := "note"
	var next BoardText
	if !create {
		kind, next = module.Kind, module.BoardText
	}
	if c.Title != nil {
		next.Title = strings.TrimSpace(*c.Title)
	}
	if c.Body != nil {
		next.Body = strings.TrimSpace(*c.Body)
	}
	if c.MaterialIDs != nil {
		next.MaterialIDs = slices.Clone(*c.MaterialIDs)
	}
	if module != nil && module.Kind == kind && module.Title == next.Title && module.Body == next.Body && slices.Equal(module.MaterialIDs, next.MaterialIDs) {
		return nil, nil
	}
	if create && module != nil {
		return nil, fmt.Errorf("%w: 这条笔记已存在且内容不同", ErrConflict)
	}
	if !create {
		if err := c.checkVersion(module.Version); err != nil {
			return nil, err
		}
	}
	if !validBoardText(s, kind, next) {
		return nil, errors.New("请检查模块标题、正文长度及材料引用")
	}
	if kind == "note" && duplicateNoteTitle(s.Board.Modules, next.Title, c.ModuleID) {
		return nil, errors.New("已有同名笔记")
	}
	if create {
		if !canAddBoardNote(s.Board.Modules) {
			return nil, errors.New("议题板模块已满")
		}
		module = &BoardModule{ID: c.ModuleID, Kind: "note"}
	}
	change := c.summary(c.ModuleID, module.BoardText.summary(), next.summary(), module.Version+1)
	module.BoardText, module.BoardSource = next, BoardSource{SourceSeat: "user", Version: change.Version}
	if create || newPreset {
		s.Board.State = boardPublished
		s.Board.Modules = append(s.Board.Modules, *module)
	}
	return change, nil
}

func (c HostBoardChange) editAgenda(s *Session) (*BoardChangeSummary, error) {
	item := s.findAgenda(c.ItemID)
	if item == nil || c.Title == nil {
		return nil, errors.New("请指定议程事项和标题")
	}
	input, err := cleanAgendaInput(AgendaInput{Title: *c.Title, Kind: item.Kind}, defaultKind(s.Preset))
	if err != nil {
		return nil, err
	}
	if item.Title == input.Title {
		return nil, nil
	}
	if err := c.checkVersion(item.Version); err != nil {
		return nil, err
	}
	for _, other := range s.Agenda {
		if other.ID != item.ID && strings.EqualFold(other.Title, input.Title) {
			return nil, errors.New("议程中已有同名事项")
		}
	}
	change := c.summary(item.ID, item.Title, input.Title, item.Version+1)
	// Record one host revision for successive autosaves in the same round.
	if n := len(item.Revisions); n == 0 || item.Revisions[n-1].Seat != "user" || item.Revisions[n-1].Round != len(s.Rounds) {
		item.Revisions = append(item.Revisions, AgendaRevision{len(s.Rounds), "user", item.Title, item.Kind, "主持人编辑"})
	}
	item.Title, item.Version, item.EditedBy = input.Title, change.Version, "user"
	s.Board.revealPreset("agenda")
	s.AgendaVersion++
	return change, nil
}

func hasPublicPoint(s *Session, id string) bool {
	for i := len(s.Rounds) - 1; i >= 0; i-- {
		for _, turn := range s.Rounds[i].Turns {
			if turn.Status == "done" && slices.ContainsFunc(turn.Points, func(p DiscussionPoint) bool { return p.ID == id }) {
				return true
			}
		}
	}
	return false
}

func (c HostBoardChange) annotate(s *Session) (*BoardChangeSummary, error) {
	id, annotations := c.MaterialID, &s.Board.MaterialAnnotations
	if c.Op == "annotate_point" {
		id, annotations = c.PointID, &s.Board.PointAnnotations
		if id == "" || !hasPublicPoint(s, id) {
			return nil, errors.New("未找到该公开观点")
		}
	} else if !slices.ContainsFunc(s.Materials, func(m Material) bool { return m.ID == id }) {
		return nil, errors.New("未找到本场会议的附件")
	}
	if c.Body == nil || utf8.RuneCountInString(strings.TrimSpace(*c.Body)) > maxBoardBody {
		return nil, fmt.Errorf("请提交不超过 %d 个字符的主持人批注", maxBoardBody)
	}
	body := strings.TrimSpace(*c.Body)
	existing := (*annotations)[id]
	if body == existing.Body {
		return nil, nil
	}
	if err := c.checkVersion(existing.Version); err != nil {
		return nil, err
	}
	change := c.summary(id, existing.Body, body, existing.Version+1)
	if *annotations == nil {
		*annotations = map[string]BoardAnnotation{}
	}
	// Keep the revision when clearing an annotation to reject stale retries.
	if c.Op == "annotate_material" {
		s.Board.revealPreset("materials")
	} else if s.Status != "running" {
		// Revealing a new point view during a blind round could disclose that
		// a peer has already made a proposition. Closure reveals it instead.
		s.Board.revealPreset("positions")
	}
	(*annotations)[id] = BoardAnnotation{Body: body, BoardSource: BoardSource{SourceSeat: "user", Version: change.Version}}
	return change, nil
}
