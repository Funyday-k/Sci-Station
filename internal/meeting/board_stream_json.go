package meeting

import (
	"encoding/json"
	"slices"
	"strings"
)

type boardStreamRole uint8

const (
	boardRoleIgnored boardStreamRole = iota
	boardRoleRoot
	boardRoleUpdates
	boardRoleProposal
	boardRoleReferences
)

type boardStreamState uint8

const (
	boardObjectKeyOrEnd boardStreamState = iota
	boardObjectKey
	boardObjectColon
	boardObjectValue
	boardObjectNext
	boardArrayValueOrEnd
	boardArrayValue
	boardArrayNext
)

type boardStreamFrame struct {
	role  boardStreamRole
	state boardStreamState
	index int
	key   string
	keys  map[string]bool
}

func boardJSONSpace(b byte) bool {
	return b == ' ' || b == '\t' || b == '\r' || b == '\n'
}

func (s *boardStream) consume(b byte) bool {
	if s.boardBytes > 0 {
		s.boardBytes++
		if s.boardBytes > maxBoardJSON {
			return false
		}
	}
	return s.consumeToken(b)
}

func (s *boardStream) consumeToken(b byte) bool {
	if s.stringToken != nil {
		return s.consumeString(b)
	}
	if len(s.atom) > 0 {
		switch {
		case boardJSONSpace(b) || b == ',' || b == ']' || b == '}':
			if !json.Valid(s.atom) {
				return false
			}
			s.atom = nil
		case len(s.atom) >= 128:
			return false
		default:
			s.atom = append(s.atom, b)
			return true
		}
	}
	if boardJSONSpace(b) {
		return true
	}
	if s.finished {
		return false
	}
	if !s.started {
		if b != '{' {
			return false
		}
		s.started = true
		s.stack = append(s.stack, boardStreamFrame{role: boardRoleRoot, state: boardObjectKeyOrEnd, keys: map[string]bool{}})
		return true
	}
	frame := &s.stack[len(s.stack)-1]
	switch frame.state {
	case boardObjectKeyOrEnd, boardObjectKey:
		if b == '}' && frame.state == boardObjectKeyOrEnd {
			return s.endFrame()
		}
		if b == '"' {
			s.stringToken = &boardStreamString{}
			return true
		}
	case boardObjectColon:
		if b == ':' {
			frame.state = boardObjectValue
			return true
		}
	case boardObjectValue, boardArrayValueOrEnd, boardArrayValue:
		if b == ']' && frame.state == boardArrayValueOrEnd {
			return s.endFrame()
		}
		return s.startValue(frame, b)
	case boardObjectNext:
		if b == '}' {
			return s.endFrame()
		}
		if b == ',' {
			frame.state = boardObjectKey
			return true
		}
	case boardArrayNext:
		if b == ']' {
			return s.endFrame()
		}
		if b == ',' {
			frame.state = boardArrayValue
			return true
		}
	}
	return false
}

func (f *boardStreamFrame) advanceValue() {
	if f.state == boardObjectValue {
		f.state = boardObjectNext
	} else {
		f.state = boardArrayNext
	}
}

func (s *boardStream) startValue(frame *boardStreamFrame, b byte) bool {
	role := boardRoleIgnored
	index := frame.index
	var keys map[string]bool
	switch frame.role {
	case boardRoleRoot:
		switch frame.key {
		case "action", "text":
			if b != '"' {
				return false
			}
		case "board_updates":
			if b != '[' {
				return false
			}
			s.boardBytes, role = 1, boardRoleUpdates
		default:
			if b != '[' && b != 'n' {
				return false
			}
		}
	case boardRoleUpdates:
		if b != '{' || len(s.proposals) >= maxBoardUpdates {
			return false
		}
		role, index, keys = boardRoleProposal, len(s.proposals), map[string]bool{}
		s.proposals = append(s.proposals, boardStreamProposal{keys: keys})
	case boardRoleProposal:
		if frame.key == "material_ids" {
			if b != '[' {
				return false
			}
			role = boardRoleReferences
		} else if b != '"' {
			return false
		}
	case boardRoleReferences:
		if b != '"' || len(s.proposals[index].references) >= maxBoardRefs {
			return false
		}
	}
	switch b {
	case '"':
		s.stringToken = &boardStreamString{}
		return true
	case '{', '[':
		if len(s.stack) >= maxBoardStreamDepth {
			return false
		}
		state := boardObjectKeyOrEnd
		if b == '[' {
			state = boardArrayValueOrEnd
		}
		frame.advanceValue()
		s.stack = append(s.stack, boardStreamFrame{role: role, state: state, index: index, keys: keys})
		return true
	case 't', 'f', 'n', '-', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9':
		frame.advanceValue()
		s.atom = append(s.atom, b)
		return true
	default:
		return false
	}
}

func (s *boardStream) endFrame() bool {
	index := len(s.stack) - 1
	frame := s.stack[index]
	s.stack = s.stack[:index]
	switch frame.role {
	case boardRoleRoot:
		s.finished = true
		return s.action == "say" && s.statement != ""
	case boardRoleUpdates:
		s.boardBytes = 0
	case boardRoleProposal:
		s.dirty = true
		return s.closeProposal(&s.proposals[frame.index])
	case boardRoleReferences:
		s.proposals[frame.index].referencesClosed = true
		s.dirty = true
	}
	return true
}

func (s *boardStream) consumeString(b byte) bool {
	frame := &s.stack[len(s.stack)-1]
	token := s.stringToken
	count := token.runes
	closed, valid := token.read(b)
	if !valid {
		return false
	}
	if frame.role == boardRoleProposal && frame.state == boardObjectValue && token.runes > count {
		switch frame.key {
		case "title":
			if token.runes > maxBoardTitle {
				return false
			}
			s.dirty = true
		case "body":
			if token.runes > maxBoardBody {
				return false
			}
			s.dirty = true
		}
	}
	if !closed {
		return true
	}
	s.stringToken = nil
	value := string(token.text)
	if frame.state == boardObjectKeyOrEnd || frame.state == boardObjectKey {
		return s.setKey(frame, value)
	}
	if !s.setString(frame, value) {
		return false
	}
	frame.advanceValue()
	return true
}

func (s *boardStream) setKey(frame *boardStreamFrame, key string) bool {
	switch frame.role {
	case boardRoleRoot:
		switch key {
		case "action", "text", "board_updates", "points", "positions", "agenda_updates", "followups":
		default:
			return false
		}
	case boardRoleProposal:
		switch key {
		case "op", "title", "body", "module_id", "material_ids":
		default:
			return false
		}
	}
	if frame.keys != nil {
		if frame.keys[key] {
			return false
		}
		frame.keys[key] = true
	}
	frame.key, frame.state = key, boardObjectColon
	return frame.role != boardRoleProposal || s.allowedProposalKeys(&s.proposals[frame.index])
}

func (s *boardStream) setString(frame *boardStreamFrame, value string) bool {
	switch frame.role {
	case boardRoleRoot:
		switch frame.key {
		case "action":
			if value != "say" {
				return false
			}
			s.action, s.dirty = value, true
		case "text":
			s.statement, s.dirty = value, true
			if strings.TrimSpace(value) == "" {
				return false
			}
		}
	case boardRoleProposal:
		p := &s.proposals[frame.index]
		switch frame.key {
		case "op":
			if value != "rename_board" && value != "revise_module" && value != "add_note" {
				return false
			}
			p.op = value
		case "module_id":
			if value == "" || s.session.Board.module(value) == nil {
				return false
			}
			p.moduleID = value
		case "title":
			p.title = value
		case "body":
			p.body, p.bodyClosed = value, true
		}
		s.dirty = true
		return s.allowedProposalKeys(p)
	case boardRoleReferences:
		p := &s.proposals[frame.index]
		if value == "" || slices.Contains(p.references, value) || !slices.ContainsFunc(s.session.Materials, func(m Material) bool { return m.ID == value }) {
			return false
		}
		p.references = append(p.references, value)
	}
	return true
}
