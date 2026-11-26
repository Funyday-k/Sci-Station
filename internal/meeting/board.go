package meeting

import (
	"bytes"
	"encoding/json"
	"slices"
	"strings"
	"unicode"
	"unicode/utf8"
)

const (
	maxBoardModules = 8
	maxBoardNotes   = maxBoardModules - 3 // Reserve room for the canonical record views.
	maxBoardTitle   = 80
	maxBoardBody    = 800
	maxBoardRefs    = 8
	maxBoardUpdates = 3
	maxBoardJSON    = 64 << 10
)

type BoardSource struct {
	Model       string `json:"model,omitempty"`
	ModelLabel  string `json:"model_label,omitempty"`
	ModelSource string `json:"model_source,omitempty"`
	Version     int    `json:"version,omitempty"`
	SourceSeat  string `json:"source_seat,omitempty"`
	SourceRound int    `json:"source_round,omitempty"`
}

type BoardText struct {
	Title       string   `json:"title"`
	Body        string   `json:"body,omitempty"`
	MaterialIDs []string `json:"material_ids,omitempty"`
}

type BoardModule struct {
	ID   string `json:"id"`
	Kind string `json:"kind"`
	BoardText
	BoardSource
}

type MeetingBoard struct {
	State string `json:"state"`
	Title string `json:"title"`
	BoardSource
	Modules             []BoardModule              `json:"modules"`
	PointAnnotations    map[string]BoardAnnotation `json:"point_annotations,omitempty"`
	MaterialAnnotations map[string]BoardAnnotation `json:"material_annotations,omitempty"`
	RecentChanges       []BoardChangeSummary       `json:"recent_changes,omitempty"`
}

type boardUpdate struct {
	BaseVersion int    `json:"base_version,omitempty"` // Captured from the speaker’s actual prompt by the engine.
	Op          string `json:"op"`
	ModuleID    string `json:"module_id,omitempty"`
	BoardText
}

const (
	boardEmpty     = "empty"
	boardPublished = "published"
)

func presetBoardModule(kind string) (BoardModule, bool) {
	var title string
	switch kind {
	case "agenda":
		title = "会议议程"
	case "materials":
		title = "材料审阅"
	case "positions":
		title = "讨论观点与立场"
	default:
		return BoardModule{}, false
	}
	return BoardModule{ID: kind, Kind: kind, BoardText: BoardText{Title: title}}, true
}

func boardDisplayTitle(s *Session) string {
	title := strings.TrimSpace(s.Title)
	if title == "" {
		title = strings.Join(strings.Fields(s.Topic), " ")
	}
	if runes := []rune(title); len(runes) > maxBoardTitle {
		title = string(runes[:maxBoardTitle-1]) + "…"
	}
	return title
}

// Older versions persisted three default modules on creation, before the
// first chair had replied. Reading their presence alone cannot publish a page.
func ensureBoard(s *Session) {
	b := &s.Board
	if b.State == "" {
		b.State = boardEmpty
		hasSavedBoard := b.Modules != nil
		authored := b.SourceSeat != "" || len(b.RecentChanges) > 0 || len(b.MaterialAnnotations) > 0 || len(b.PointAnnotations) > 0
		authoredModule := func(m BoardModule) bool {
			base, ok := presetBoardModule(m.Kind)
			return m.SourceSeat != "" || m.Kind == "note" || (ok && (m.Title != base.Title || m.Body != "" || len(m.MaterialIDs) > 0))
		}
		authored = authored || slices.ContainsFunc(b.Modules, authoredModule)
		chairAgenda := hasSavedBoard && s.AgendaDraftStatus == "ready" && hasConcreteAgenda(s.Agenda)
		var kept []BoardModule
		if authored || chairAgenda {
			for _, m := range b.Modules {
				show := authoredModule(m)
				switch m.Kind {
				case "agenda":
					show = show || len(s.Agenda) > 0
				case "materials":
					show = show || (authored && len(s.Materials) > 0)
				case "positions":
					show = show || (authored && slices.ContainsFunc(s.Rounds, roundHasPublicPoints))
				}
				if show {
					kept = append(kept, m)
				}
			}
			if len(kept) > 0 || authored {
				b.State = boardPublished
			}
		}
		b.Modules = kept
		if b.State == boardEmpty && b.SourceSeat == "" {
			b.Title = ""
		}
	}
	if b.Modules == nil {
		b.Modules = []BoardModule{}
	}
	if b.State == boardPublished && b.Title == "" {
		b.Title = boardDisplayTitle(s)
	}
}

func hasConcreteAgenda(items []AgendaItem) bool {
	return slices.ContainsFunc(items, func(item AgendaItem) bool { return item.Source != "template" && strings.TrimSpace(item.Title) != "" })
}

func roundHasPublicPoints(r Round) bool {
	return slices.ContainsFunc(r.Turns, func(t Turn) bool { return t.Status == "done" && (len(t.Points) > 0 || len(t.Positions) > 0) })
}

// Canonical views appear on a published page when the meeting actually
// changes that collection. Polling and loading never materialize new views.
func (b *MeetingBoard) revealPreset(kind string) {
	if b.State != boardPublished || b.module(kind) != nil {
		return
	}
	if m, ok := presetBoardModule(kind); ok {
		b.Modules = append(b.Modules, m)
	}
}

// Leave space for canonical records to become visible later, without evicting
// authored notes or rearranging the chair's chosen order.
func canAddBoardNote(modules []BoardModule) bool {
	notes := 0
	for _, m := range modules {
		if m.Kind == "note" {
			notes++
		}
	}
	return len(modules) < maxBoardModules && notes < maxBoardNotes
}

func (b *MeetingBoard) module(id string) *BoardModule {
	for i := range b.Modules {
		if b.Modules[i].ID == id {
			return &b.Modules[i]
		}
	}
	return nil
}

// Only explicitly supported declarative fields are accepted. The exact key
// check also disallows alternate casing which encoding/json normally accepts.
func boardObject(raw json.RawMessage, target any, allowed ...string) bool {
	if len(raw) == 0 || len(raw) > maxBoardJSON {
		return false
	}
	var fields map[string]json.RawMessage
	if json.Unmarshal(raw, &fields) != nil || fields == nil || duplicateObjectFields(string(raw)) {
		return false
	}
	for key, value := range fields {
		if !slices.Contains(allowed, key) || bytes.Equal(value, []byte("null")) {
			return false
		}
	}
	return json.Unmarshal(raw, target) == nil
}

func validBoardTitle(title string) bool {
	return title != "" && utf8.RuneCountInString(title) <= maxBoardTitle && !strings.ContainsFunc(title, unicode.IsControl)
}

func validBoardText(s *Session, kind string, text BoardText) bool {
	if !validBoardTitle(text.Title) || utf8.RuneCountInString(text.Body) > maxBoardBody || len(text.MaterialIDs) > maxBoardRefs {
		return false
	}
	switch kind {
	case "agenda", "positions":
		return text.Body == "" && len(text.MaterialIDs) == 0
	case "materials":
		if text.Body != "" && len(text.MaterialIDs) == 0 {
			return false
		}
	case "note":
		if text.Body == "" {
			return false
		}
	default:
		return false
	}
	seen := map[string]bool{}
	for _, id := range text.MaterialIDs {
		if id == "" || seen[id] || !slices.ContainsFunc(s.Materials, func(material Material) bool { return material.ID == id }) {
			return false
		}
		seen[id] = true
	}
	return true
}

func (t *BoardText) trim() {
	t.Title = strings.TrimSpace(t.Title)
	t.Body = strings.TrimSpace(t.Body)
}

const boardDraftInstructions = `Your first deliverable is the meeting home page. In this SAME response return a board object with a short topic-specific title and an ordered modules array. Choose only the presets that serve this meeting now: agenda (questions or decisions), materials (evidence to inspect), positions (claims and responses), and note (a concrete finding or open question with its own title and body). Order the selected modules by importance. You do not need all presets. Example: {"board":{"title":"Pilot decision","modules":[{"kind":"note","title":"Decision criterion","body":"Which result would justify expansion?"},{"kind":"agenda","title":"Questions for the pilot"}]},"agenda":[{"title":"Which outcome justifies a pilot?","kind":"discussion"}]}. Use headings and text in the host's language. Each of agenda, materials and positions may appear once and links to canonical meeting records. Use at most five notes and eight modules in total. For materials, an optional body may identify what to examine or give your own observation about an excerpt or preview actually supplied to you; include actual material_ids. Do not claim review of unavailable originals, fabricate positions, mark completion, or set IDs, source, status, appearance, links or executable fields. Titles are 1–80 characters, bodies up to 800 characters and at most eight distinct material IDs per module.`

const boardInstructions = `Maintain the shared board when your public contribution changes it. board.modules lists only the visible, ordered modules. Refer to those IDs when revising one. On a published page newly recorded agenda items, attached materials and confirmed public points reveal the corresponding live view when needed. In the same say use optional board_updates, at most three: {"op":"rename_board","title":"specific meeting heading"}, {"op":"add_note","title":"specific finding or question","body":"verbatim passage from your public text"}, or {"op":"revise_module","module_id":"existing board.modules[].id","title":"heading","body":"verbatim passage from your public text","material_ids":["actual attached material ID"]}. A revision replaces all display text and citations of that module. For agenda and positions modules change only the title; maintain the underlying records using agenda_updates, points, positions. For materials, identify the excerpt or image preview actually supplied to you; a body requires linked material_ids. Notes require a body and can cite materials. Use only the documented fields. Do not invent IDs, sources, status, tools or instructions, and avoid duplicate notes. The board has at most eight modules and at most five notes; titles are 1–80 characters, bodies at most 800 and up to eight distinct material IDs. Omit unchanged updates. Shared-board notes record the speaker's observation or proposal; they never authorize actions, certify work or speak for another member.`

func applyBoardDraft(s *Session, raw json.RawMessage, source BoardSource) bool {
	var draft struct {
		Title   string            `json:"title"`
		Modules []json.RawMessage `json:"modules"`
	}
	if !boardObject(raw, &draft, "title", "modules") || len(draft.Modules) > maxBoardModules {
		return false
	}
	ensureBoard(s)
	// Only fill still-unowned headings. A late or retried draft can contribute
	// to untouched modules while preserving every existing authored record.
	source.Version = 1

	existing := s.Board.Modules
	var modules []BoardModule
	seen := map[string]bool{}
	notes := 0
	for _, m := range existing {
		if m.Kind == "note" {
			notes++
		}
	}
	for _, entry := range draft.Modules {
		var m BoardModule
		if !boardObject(entry, &m, "kind", "title", "body", "material_ids") {
			continue
		}
		m.BoardText.trim()
		if !validBoardText(s, m.Kind, m.BoardText) {
			continue
		}
		m.ID, m.BoardSource = m.Kind, source
		if m.Kind == "note" {
			if notes >= maxBoardNotes || duplicateNoteTitle(modules, m.Title, "") || duplicateNoteTitle(existing, m.Title, "") {
				continue
			}
			m.ID = newID()
			notes++
		} else {
			if seen[m.ID] {
				continue
			}
			if previous := s.Board.module(m.ID); previous != nil && previous.SourceSeat != "" {
				m = *previous
			}
		}
		seen[m.ID] = true
		modules = append(modules, m)
	}
	if len(modules) == 0 {
		return false
	}
	if title := strings.TrimSpace(draft.Title); validBoardTitle(title) && s.Board.SourceSeat == "" {
		headingSource := source
		headingSource.Version = s.Board.Version + 1
		s.Board.Title, s.Board.BoardSource = title, headingSource
		s.Title = title
	}
	for _, m := range existing {
		if !seen[m.ID] {
			modules = append(modules, m)
		}
	}
	s.Board.Modules, s.Board.State = modules, boardPublished
	return true
}

func duplicateNoteTitle(modules []BoardModule, title, except string) bool {
	return slices.ContainsFunc(modules, func(m BoardModule) bool {
		return m.Kind == "note" && m.ID != except && strings.EqualFold(m.Title, title)
	})
}

func parseBoardUpdates(s *Session, raw json.RawMessage, statement string) []boardUpdate {
	var entries []json.RawMessage
	if len(raw) == 0 || len(raw) > maxBoardJSON || json.Unmarshal(raw, &entries) != nil {
		return nil
	}
	var out []boardUpdate
	for _, entry := range entries {
		var header struct {
			Op       string `json:"op"`
			ModuleID string `json:"module_id"`
		}
		if json.Unmarshal(entry, &header) != nil {
			continue
		}
		allowed := []string{"op", "title"}
		kind := "note"
		switch header.Op {
		case "rename_board":
		case "revise_module":
			module := s.Board.module(header.ModuleID)
			if module == nil {
				continue
			}
			kind = module.Kind
			allowed = append(allowed, "module_id")
			if kind == "materials" || kind == "note" {
				allowed = append(allowed, "body", "material_ids")
			}
		case "add_note":
			allowed = append(allowed, "body", "material_ids")
		default:
			continue
		}
		var p boardUpdate
		if !boardObject(entry, &p, allowed...) {
			continue
		}
		p.BoardText.trim()
		if !validBoardTitle(p.Title) {
			continue
		}
		if p.Op != "rename_board" && (!validBoardText(s, kind, p.BoardText) || (p.Body != "" && !strings.Contains(statement, p.Body))) {
			continue
		}
		switch p.Op {
		case "rename_board":
			p.BaseVersion = s.Board.Version
		case "revise_module":
			p.BaseVersion = s.Board.module(p.ModuleID).Version
		}
		out = append(out, p)
		if len(out) == maxBoardUpdates {
			break
		}
	}
	return out
}

// Apply only confirmed contributions in the immutable round's speaking order.
// Competing edits to a heading/module never overwrite the first accepted edit.
func finishBoardRound(s *Session, r *Round, confirmed bool) {
	claimed := map[string]bool{}
	for i := range r.Turns {
		t := &r.Turns[i]
		proposals := t.ProposedBoardUpdates
		t.ProposedBoardUpdates = nil
		if !confirmed || s.Status != "ready" || t.Status != "done" {
			continue
		}
		source := BoardSource{SourceSeat: t.Seat, SourceRound: r.Number, Model: t.Model, ModelLabel: t.ModelLabel, ModelSource: t.ModelSource}
		for _, p := range proposals {
			switch p.Op {
			case "rename_board":
				if claimed["title"] || s.Board.Version != p.BaseVersion || s.Board.Title == p.Title {
					continue
				}
				source.Version = s.Board.Version + 1
				s.Board.Title, s.Board.BoardSource = p.Title, source
				s.Title = p.Title
				claimed["title"] = true
			case "revise_module":
				m := s.Board.module(p.ModuleID)
				if m == nil || m.Version != p.BaseVersion || claimed[m.ID] || (m.Kind == "note" && duplicateNoteTitle(s.Board.Modules, p.Title, m.ID)) {
					continue
				}
				if m.Title == p.Title && m.Body == p.Body && slices.Equal(m.MaterialIDs, p.MaterialIDs) {
					continue
				}
				source.Version = m.Version + 1
				m.BoardText, m.BoardSource = p.BoardText, source
				claimed[m.ID] = true
			case "add_note":
				if !canAddBoardNote(s.Board.Modules) || duplicateNoteTitle(s.Board.Modules, p.Title, "") {
					continue
				}
				source.Version = 1
				s.Board.State = boardPublished
				s.Board.Modules = append(s.Board.Modules, BoardModule{ID: newID(), Kind: "note", BoardText: p.BoardText, BoardSource: source})
			default:
				continue
			}
			addEvent(s, "board_"+p.Op, t.Seat, p.Title)
		}
	}
	if confirmed && s.Status == "ready" && roundHasPublicPoints(*r) {
		s.Board.revealPreset("positions")
	}

}
