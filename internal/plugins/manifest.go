package plugins

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"regexp"
	"slices"
	"strings"
	"unicode"
	"unicode/utf8"
)

const (
	MaxPackageBytes  = 1 << 20
	MaxModuleBytes   = 512 << 10
	maxGuidanceBytes = 8 << 10

	CapRoundGuidance  = "round.guidance"
	CapReportGuidance = "report.guidance"
	CapPublicTurns    = "meeting.public_turns"
	CapReport         = "meeting.report"
	CapCodeExecute    = "code.execute"
)

type Manifest struct {
	SchemaVersion int           `json:"schema_version"`
	ID            string        `json:"id"`
	Version       string        `json:"version"`
	Name          string        `json:"name"`
	Author        string        `json:"author"`
	Description   string        `json:"description"`
	Contributions Contributions `json:"contributions"`
	Module        []byte        `json:"module,omitempty"`
}

type Contributions struct {
	RoundGuidance  string   `json:"round_guidance,omitempty"`
	ReportGuidance string   `json:"report_guidance,omitempty"`
	Actions        []Action `json:"actions,omitempty"`
}

type Action struct {
	ID     string `json:"id"`
	Label  string `json:"label"`
	Input  string `json:"input"`
	Format string `json:"format"`
}

var (
	pluginIDPattern = regexp.MustCompile(`^[a-z](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$`)
	versionPattern  = regexp.MustCompile(`^(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})$`)
	actionIDPattern = regexp.MustCompile(`^[a-z][a-z0-9_-]{0,63}$`)
	jsonKeyPattern  = regexp.MustCompile(`^[a-z][a-z0-9_]*$`)
)

func ValidPluginID(id string) bool {
	return len(id) <= 253 && pluginIDPattern.MatchString(id)
}

func ValidVersion(version string) bool {
	return versionPattern.MatchString(version)
}

func ValidateMetadata(id, version, name, author, description string) error {
	if !ValidPluginID(id) {
		return errors.New("plugin id must be a lowercase reverse-domain identifier")
	}
	if !ValidVersion(version) {
		return errors.New("plugin version must use MAJOR.MINOR.PATCH")
	}
	for _, field := range []struct {
		name, value string
		limit       int
	}{{"name", name, 128}, {"author", author, 128}, {"description", description, 1024}} {
		if !validText(field.value, field.limit, false) {
			return fmt.Errorf("plugin %s must be single-line text of at most %d bytes", field.name, field.limit)
		}
	}
	return nil
}

func validText(text string, maxBytes int, multiline bool) bool {
	if len(text) > maxBytes || strings.TrimSpace(text) == "" || !utf8.ValidString(text) {
		return false
	}
	for _, char := range text {
		if multiline && (char == '\n' || char == '\r' || char == '\t') {
			continue
		}
		if unicode.IsControl(char) || (!multiline && (char == '\u2028' || char == '\u2029')) {
			return false
		}
	}
	return true
}

// ParsePackage validates metadata, contributions, and the optional module ABI.
// Validation compiles the module without instantiating it or calling guest code.
func ParsePackage(data []byte) (Manifest, error) {
	var manifest Manifest
	if len(data) > MaxPackageBytes {
		return manifest, fmt.Errorf("plugin package exceeds %d bytes", MaxPackageBytes)
	}
	if !utf8.Valid(data) {
		return manifest, errors.New("plugin package must use UTF-8 JSON")
	}
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.UseNumber()
	if err := checkJSONValue(decoder, 0); err != nil {
		return manifest, fmt.Errorf("invalid plugin package: %w", err)
	}
	if _, err := decoder.Token(); err != io.EOF {
		return manifest, errors.New("plugin package must contain one JSON object")
	}
	decoder = json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&manifest); err != nil {
		return Manifest{}, fmt.Errorf("invalid plugin package: %w", err)
	}
	if err := manifest.validate(); err != nil {
		return Manifest{}, err
	}
	return manifest, nil
}

// Reject duplicate keys before unmarshaling because encoding/json accepts them.
func checkJSONValue(decoder *json.Decoder, depth int) error {
	if depth > 4 {
		return errors.New("JSON nesting exceeds the plugin package schema")
	}
	token, err := decoder.Token()
	if err != nil {
		return err
	}
	switch token {
	case json.Delim('{'):
		seen := make(map[string]bool)
		for decoder.More() {
			keyToken, err := decoder.Token()
			if err != nil {
				return err
			}
			key, ok := keyToken.(string)
			if !ok || len(key) > 64 || !jsonKeyPattern.MatchString(key) {
				return errors.New("invalid plugin package field name")
			}
			if seen[key] {
				return fmt.Errorf("duplicate field %q", key)
			}
			seen[key] = true
			if err := checkJSONValue(decoder, depth+1); err != nil {
				return err
			}
		}
	case json.Delim('['):
		for decoder.More() {
			if err := checkJSONValue(decoder, depth+1); err != nil {
				return err
			}
		}
	case nil:
		return errors.New("null fields are outside the plugin package schema")
	default:
		return nil
	}
	_, err = decoder.Token()
	return err
}

func (m Manifest) validate() error {
	if m.SchemaVersion != 1 {
		return errors.New("plugin package schema_version must be 1")
	}
	if err := ValidateMetadata(m.ID, m.Version, m.Name, m.Author, m.Description); err != nil {
		return err
	}
	contributions := m.Contributions
	for _, guidance := range []struct{ name, text string }{
		{"round_guidance", contributions.RoundGuidance}, {"report_guidance", contributions.ReportGuidance},
	} {
		if guidance.text == "" {
			continue
		}
		if !validText(guidance.text, maxGuidanceBytes, true) {
			return fmt.Errorf("plugin %s must be text of at most %d bytes", guidance.name, maxGuidanceBytes)
		}
		if guidanceSize(m.ID, m.Version, m.Name, guidance.name, guidance.text)+2 > maxGuidanceBytes {
			return fmt.Errorf("plugin %s with metadata exceeds the %d KiB meeting guidance limit", guidance.name, maxGuidanceBytes>>10)
		}
	}
	if len(contributions.Actions) > 16 {
		return errors.New("a plugin can have at most 16 actions")
	}
	if len(contributions.Actions) == 0 {
		if m.Module != nil {
			return errors.New("a plugin module requires an action")
		}
		if contributions.RoundGuidance == "" && contributions.ReportGuidance == "" {
			return errors.New("a plugin must contribute guidance or an action")
		}
		return nil
	}
	seen := make(map[string]bool, len(contributions.Actions))
	for _, action := range contributions.Actions {
		if !actionIDPattern.MatchString(action.ID) {
			return errors.New("action id must be a lowercase identifier of at most 64 bytes")
		}
		if seen[action.ID] {
			return fmt.Errorf("duplicate action id %q", action.ID)
		}
		seen[action.ID] = true
		if !validText(action.Label, 128, false) {
			return fmt.Errorf("action %q label must be single-line text of at most 128 bytes", action.ID)
		}
		if action.Input != "public_turns" && action.Input != "report" {
			return fmt.Errorf("action %q input must be public_turns or report", action.ID)
		}
		if action.Format != "markdown" && action.Format != "text" {
			return fmt.Errorf("action %q format must be markdown or text", action.ID)
		}
	}
	if len(m.Module) == 0 {
		return errors.New("plugin actions require a WebAssembly module")
	}
	_, err := executeModule(context.Background(), m.Module, nil, true)
	return err
}

// Each item reserves one byte for a list separator. The caller adds two bytes
// for the surrounding array to match the aggregate meeting budget.
func guidanceSize(id, version, name, key, text string) int {
	encoded, _ := json.Marshal(map[string]string{"id": id, "version": version, "name": name, key: text})
	return len(encoded) + 1
}

func (m Manifest) Capabilities() []string {
	var capabilities []string
	contributions := m.Contributions
	if contributions.RoundGuidance != "" {
		capabilities = append(capabilities, CapRoundGuidance)
	}
	if contributions.ReportGuidance != "" {
		capabilities = append(capabilities, CapReportGuidance)
	}
	if len(contributions.Actions) > 0 {
		capabilities = append(capabilities, CapCodeExecute)
	}
	for _, action := range contributions.Actions {
		switch action.Input {
		case "public_turns":
			capabilities = append(capabilities, CapPublicTurns)
		case "report":
			capabilities = append(capabilities, CapReport)
		}
	}
	slices.Sort(capabilities)
	return slices.Compact(capabilities)
}

// CompareVersions orders valid MAJOR.MINOR.PATCH versions numerically.
func CompareVersions(a, b string) int {
	if !ValidVersion(a) || !ValidVersion(b) {
		return strings.Compare(a, b)
	}
	left, right := strings.Split(a, "."), strings.Split(b, ".")
	for index, part := range left {
		other := right[index]
		if len(part) != len(other) {
			if len(part) < len(other) {
				return -1
			}
			return 1
		}
		if comparison := strings.Compare(part, other); comparison != 0 {
			return comparison
		}
	}
	return 0
}
