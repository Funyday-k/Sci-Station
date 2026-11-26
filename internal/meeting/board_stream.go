package meeting

import (
	"slices"
	"strings"
)

const (
	maxBoardStreamBytes = 256 << 10
	maxBoardStreamDepth = 48
)

// A zero edit withdraws the current request's preview. Index is the position
// within board_updates, so add_note has a stable identity before it is saved.
type boardStreamEdit struct {
	Op, ModuleID, Field, Text string
	Index                     int
	Complete                  bool
}

type boardStreamField struct {
	text     string
	complete bool
}

type boardStreamProposal struct {
	op, moduleID     string
	title, body      string
	references       []string
	keys             map[string]bool
	bodyClosed       bool
	referencesClosed bool
	closed           bool
	shown            map[string]boardStreamField
	bodyMatch        int
}

// Only the direct public action protocol is previewable. Full responses still
// go through decodeAction and parseBoardUpdates, including legacy envelopes.
type boardStream struct {
	session *Session
	emit    func(boardStreamEdit)

	size, boardBytes  int
	started, finished bool
	failed, emitted   bool
	stack             []boardStreamFrame
	stringToken       *boardStreamString
	atom              []byte
	dirty             bool

	action, statement string
	proposals         []boardStreamProposal
}

func newBoardStream(s *Session, emit func(boardStreamEdit)) *boardStream {
	return &boardStream{session: s, emit: emit}
}

func (s *boardStream) Write(delta string) {
	if s.failed || s.emit == nil {
		return
	}
	s.size += len(delta)
	if s.size > maxBoardStreamBytes {
		s.invalidate()
		return
	}
	for i := range len(delta) {
		if !s.consume(delta[i]) {
			s.invalidate()
			return
		}
	}
	if s.dirty {
		s.dirty = false
		s.preview()
	}
}

func (s *boardStream) invalidate() {
	s.failed = true
	if s.emitted {
		s.emit(boardStreamEdit{})
	}
	s.stack, s.atom, s.proposals = nil, nil, nil
	s.stringToken = nil
	s.statement = ""
}

func (s *boardStream) proposalKind(p *boardStreamProposal) (string, bool) {
	switch p.op {
	case "rename_board", "add_note":
		return "note", true
	case "revise_module":
		if module := s.session.Board.module(p.moduleID); module != nil {
			return module.Kind, true
		}
	}
	return "", false
}

func (s *boardStream) allowedProposalKeys(p *boardStreamProposal) bool {
	if p.op == "" {
		return true
	}
	kind, ready := s.proposalKind(p)
	if !ready && p.op == "revise_module" && p.moduleID == "" {
		return true // A later field may identify the target.
	}
	if !ready || p.op != "revise_module" && p.keys["module_id"] {
		return false
	}
	return !(p.keys["body"] || p.keys["material_ids"]) ||
		p.op != "rename_board" && (kind == "note" || kind == "materials")
}

func (s *boardStream) closeProposal(p *boardStreamProposal) bool {
	p.closed = true
	kind, ready := s.proposalKind(p)
	if !ready || !s.allowedProposalKeys(p) {
		return false
	}
	if p.op == "rename_board" {
		return validBoardTitle(strings.TrimSpace(p.title))
	}
	text := BoardText{Title: p.title, Body: p.body, MaterialIDs: p.references}
	text.trim()
	return validBoardText(s.session, kind, text)
}

func (s *boardStream) preview() {
	if s.action != "say" || s.statement == "" {
		return
	}
	activeIndex, activeKey, activeText := -1, "", ""
	if s.stringToken != nil {
		frame := s.stack[len(s.stack)-1]
		if frame.role == boardRoleProposal && frame.state == boardObjectValue {
			switch frame.key {
			case "title", "body":
				activeIndex, activeKey = frame.index, frame.key
				activeText = string(s.stringToken.text)
			}
		}
	}
	claimed := map[string]bool{}
	modules := slices.Clone(s.session.Board.Modules)
	for index := range s.proposals {
		p := &s.proposals[index]
		kind, ready := s.proposalKind(p)
		if !ready {
			continue
		}
		title, body := strings.TrimSpace(p.title), strings.TrimSpace(p.body)
		if activeIndex == index {
			if activeKey == "title" {
				title = strings.TrimSpace(activeText)
			} else {
				body = strings.TrimSpace(activeText)
			}
		}
		completeTitle := activeIndex != index || activeKey != "title"
		completeBody := activeIndex != index || activeKey != "body"
		if title != "" && !validBoardTitle(title) ||
			hasBoardStreamDataURI(title) || hasBoardStreamDataURI(body) {
			s.invalidate()
			return
		}
		if body != "" && !s.bodyMatches(p, body) {
			s.invalidate()
			return
		}
		target := p.moduleID
		if p.op == "rename_board" {
			target = "board"
		}
		if target != "" && claimed[target] {
			continue
		}
		switch p.op {
		case "rename_board":
			if completeTitle && title == s.session.Board.Title {
				if len(p.shown) > 0 {
					s.previewField(index, p, "title", title, true)
				}
				continue
			}
		case "revise_module", "add_note":
			if p.op == "revise_module" && p.closed {
				module := s.session.Board.module(target)
				if module.Title == title && module.Body == body && slices.Equal(module.MaterialIDs, p.references) {
					continue
				}
			}
			duplicate := kind == "note" && completeTitle && duplicateNoteTitle(modules, title, p.moduleID)
			exceedsCapacity := p.op == "add_note" && !canAddBoardNote(modules)
			if duplicate || exceedsCapacity {
				if len(p.shown) > 0 {
					s.invalidate()
					return
				}
				continue
			}
			if p.closed {
				if p.op == "add_note" {
					modules = append(modules, BoardModule{Kind: "note", BoardText: BoardText{Title: title}})
				} else {
					for i := range modules {
						if modules[i].ID == target {
							modules[i].Title = title
							break
						}
					}
				}
			}
		}
		if p.closed && target != "" {
			claimed[target] = true
		}
		s.previewField(index, p, "title", title, completeTitle)
		if title == "" {
			continue
		}
		if kind == "materials" && p.bodyClosed && body == "" {
			if module := s.session.Board.module(p.moduleID); module != nil && module.Body != "" {
				s.previewField(index, p, "body", "", true)
			}
		} else if body != "" && (kind != "materials" || p.referencesClosed && len(p.references) > 0) {
			s.previewField(index, p, "body", body, completeBody)
		}
	}
}

func (s *boardStream) bodyMatches(p *boardStreamProposal, body string) bool {
	if p.bodyMatch < 0 {
		return false
	}
	if strings.HasPrefix(s.statement[p.bodyMatch:], body) {
		return true
	}
	// The next visible candidate only extends the previous prefix. Search
	// later occurrences and never rescan the already rejected source prefix.
	if next := strings.Index(s.statement[p.bodyMatch:], body); next >= 0 {
		p.bodyMatch += next
		return true
	}
	p.bodyMatch = -1
	return false
}

func hasBoardStreamDataURI(text string) bool {
	return strings.Contains(strings.ToLower(text), "data:")
}

func (s *boardStream) previewField(index int, p *boardStreamProposal, field, text string, complete bool) {
	value := boardStreamField{text: text, complete: complete}
	if text == "" && (field != "body" || !complete) || p.shown[field] == value {
		return
	}
	if p.shown == nil {
		p.shown = make(map[string]boardStreamField, 2)
	}
	p.shown[field] = value
	s.emitted = true
	s.emit(boardStreamEdit{Op: p.op, ModuleID: p.moduleID, Field: field, Text: text, Index: index, Complete: complete})
}
