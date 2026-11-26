package research

import (
	"encoding/hex"
	"regexp"
	"strings"
)

const defaultProjectColor = "#4F7CAC"
const defaultProjectSymbol = "folder"

func newProject() Project {
	return Project{Entity: fresh(), ColorHex: defaultProjectColor, IconName: defaultProjectSymbol}
}

var symbolName = regexp.MustCompile(`^[a-zA-Z0-9][a-zA-Z0-9.-]{0,79}$`)

func updateAppearance(p *Project, in projectInput) bool {
	if in.ColorHex != nil {
		color := strings.ToUpper(strings.TrimSpace(*in.ColorHex))
		if color == "" {
			color = defaultProjectColor
		}
		if len(color) != 7 || color[0] != '#' {
			return false
		}
		if _, err := hex.DecodeString(color[1:]); err != nil {
			return false
		}
		p.ColorHex = color
	}
	if in.IconName != nil {
		name := strings.TrimSpace(*in.IconName)
		if name == "" {
			name = defaultProjectSymbol
		}
		if !symbolName.MatchString(name) {
			return false
		}
		p.IconName = name
	}
	return true
}
