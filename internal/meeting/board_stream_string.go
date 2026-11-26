package meeting

import (
	"unicode/utf16"
	"unicode/utf8"
)

// A JSON string can be divided inside a UTF-8 sequence, escape or surrogate
// pair. Only a whole decoded rune is made available to the preview.
type boardStreamString struct {
	text      []byte
	runes     int
	escape    bool
	hexLeft   int
	hexValue  uint16
	surrogate uint16
	pending   [utf8.UTFMax]byte
	pendingN  int
}

func (s *boardStreamString) append(r rune) {
	s.text = utf8.AppendRune(s.text, r)
	s.runes++
}

func (s *boardStreamString) read(b byte) (closed, valid bool) {
	if s.hexLeft > 0 {
		digit, ok := boardHexDigit(b)
		if !ok {
			return false, false
		}
		s.hexValue = s.hexValue<<4 | digit
		s.hexLeft--
		if s.hexLeft > 0 {
			return false, true
		}
		r := rune(s.hexValue)
		switch {
		case s.surrogate != 0:
			if r < 0xdc00 || r > 0xdfff {
				return false, false
			}
			s.append(utf16.DecodeRune(rune(s.surrogate), r))
			s.surrogate = 0
		case r >= 0xd800 && r <= 0xdbff:
			s.surrogate = s.hexValue
		case r >= 0xdc00 && r <= 0xdfff:
			return false, false
		default:
			s.append(r)
		}
		return false, true
	}
	if s.escape {
		s.escape = false
		if b == 'u' {
			s.hexLeft, s.hexValue = 4, 0
			return false, true
		}
		if s.surrogate != 0 {
			return false, false
		}
		var r rune
		switch b {
		case '"', '\\', '/':
			r = rune(b)
		case 'b':
			r = '\b'
		case 'f':
			r = '\f'
		case 'n':
			r = '\n'
		case 'r':
			r = '\r'
		case 't':
			r = '\t'
		default:
			return false, false
		}
		s.append(r)
		return false, true
	}
	if s.pendingN > 0 || b >= utf8.RuneSelf {
		if s.surrogate != 0 {
			return false, false
		}
		s.pending[s.pendingN] = b
		s.pendingN++
		pending := s.pending[:s.pendingN]
		if !utf8.FullRune(pending) {
			return false, true
		}
		r, size := utf8.DecodeRune(pending)
		if r == utf8.RuneError && size == 1 {
			return false, false
		}
		s.pendingN = 0
		s.append(r)
		return false, true
	}
	if b == '\\' {
		s.escape = true
		return false, true
	}
	if s.surrogate != 0 || b < 0x20 {
		return false, false
	}
	if b == '"' {
		return true, true
	}
	s.append(rune(b))
	return false, true
}

func boardHexDigit(b byte) (uint16, bool) {
	switch {
	case b >= '0' && b <= '9':
		return uint16(b - '0'), true
	case b >= 'a' && b <= 'f':
		return uint16(b-'a') + 10, true
	case b >= 'A' && b <= 'F':
		return uint16(b-'A') + 10, true
	default:
		return 0, false
	}
}
