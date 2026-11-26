package meeting

import (
	"encoding/json"
	"errors"
	"unicode/utf8"

	"scistation.local/desktop/internal/workspace"
)

const (
	statementTextBudget    = 32 << 10
	statementExcerptBudget = 8 << 10
	statementFullLimit     = 8 << 10
	statementExcerptLimit  = 400
	projectEvidenceBudget  = 32 << 10
	projectFileLimit       = 8 << 10
	projectDiffLimit       = 4 << 10
)

// fitsPromptText accounts for JSON quoting and escaping without allocating an encoded
// copy of a string already larger than the remaining budget.
func fitsPromptText(text string, remaining *int) bool {
	if len(text) > *remaining {
		return false
	}
	encoded, _ := json.Marshal(text)
	if len(encoded) > *remaining {
		return false
	}
	*remaining -= len(encoded)
	return true
}

func prefixBytes(text string, limit int) string {
	if len(text) <= limit {
		return text
	}
	for limit > 0 && !utf8.RuneStart(text[limit]) {
		limit--
	}
	return text[:limit]
}

// Keep chronological provenance and the point/position records in every
// entry. Only public statement bodies and their excerpts share this budget.
func compactStatements(prior []publicStatement) []publicStatement {
	remaining := statementTextBudget
	for _, statement := range prior {
		if !fitsPromptText(statement.Text, &remaining) {
			return excerptStatements(prior)
		}
	}
	return prior
}

func excerptStatements(prior []publicStatement) []publicStatement {
	packed := append([]publicStatement(nil), prior...)
	full := statementTextBudget - statementExcerptBudget
	excerpts := statementExcerptBudget
	for i := len(packed) - 1; i >= 0; i-- {
		statement := &packed[i]
		if len(statement.Text) <= statementFullLimit && fitsPromptText(statement.Text, &full) {
			continue
		}
		if excerpt := prefixBytes(statement.Text, statementExcerptLimit); fitsPromptText(excerpt, &excerpts) {
			statement.TextExcerpt = excerpt
		}
		statement.Text, statement.TextOmitted = "", true
	}
	return packed
}

type statementRef struct {
	round int
	seat  string
}

type statementReader struct {
	originals map[statementRef]publicStatement
	seen      map[statementRef]bool
}

func newStatementReader(originals, inline []publicStatement) statementReader {
	reader := statementReader{
		originals: make(map[statementRef]publicStatement, len(originals)),
		seen:      make(map[statementRef]bool, len(inline)),
	}
	for _, statement := range originals {
		reader.originals[statementRef{statement.Round, statement.Seat}] = statement
	}
	for _, statement := range inline {
		if !statement.TextOmitted {
			reader.seen[statementRef{statement.Round, statement.Seat}] = true
		}
	}
	return reader
}

func (r statementReader) read(a action) (any, error) {
	ref := statementRef{a.Round, a.Seat}
	statement, ok := r.originals[ref]
	if !ok {
		return nil, errors.New("no completed public statement is visible for that round and seat")
	}
	if r.seen[ref] {
		return map[string]any{"round": statement.Round, "seat": statement.Seat, "model": statement.Model, "already_read": true}, nil
	}
	r.seen[ref] = true
	return statement, nil
}

type promptFile struct {
	workspace.File
	TextOmitted   bool `json:"text_omitted,omitempty"`
	TextElsewhere bool `json:"text_elsewhere,omitempty"`
}

type promptChange struct {
	workspace.Change
	DiffOmitted bool `json:"diff_omitted,omitempty"`
}

type promptUserChange struct {
	At     string       `json:"at"`
	Change promptChange `json:"change"`
}

// File versions and change metadata stay visible even when the initial
// prompt budget requires an explicit read of the current project file.
type projectEvidence struct {
	remaining int
	files     map[string]projectFileEvidence
}

type projectFileEvidence struct {
	view promptFile
	err  error
}

func newProjectEvidence() *projectEvidence {
	return &projectEvidence{
		remaining: projectEvidenceBudget,
		files:     make(map[string]projectFileEvidence),
	}
}

func (e *projectEvidence) read(project, path string) (promptFile, error) {
	if previous, ok := e.files[path]; ok {
		view := previous.view
		if view.Text != "" {
			view.Text, view.TextElsewhere = "", true
		}
		return view, previous.err
	}
	f, err := readFile(project, path)
	view := e.file(f)
	e.files[path] = projectFileEvidence{view: view, err: err}
	return view, err
}

func (e *projectEvidence) file(f workspace.File) promptFile {
	view := promptFile{File: f}
	if f.Text == "" {
		return view
	}
	if len(f.Text) > projectFileLimit || !fitsPromptText(f.Text, &e.remaining) {
		view.Text, view.TextOmitted = "", true
	}
	return view
}

func (e *projectEvidence) change(change workspace.Change) promptChange {
	view := promptChange{Change: change}
	if change.Diff == "" {
		return view
	}
	prefix := prefixBytes(change.Diff, projectDiffLimit)
	if !fitsPromptText(prefix, &e.remaining) {
		prefix = ""
	}
	view.Diff, view.DiffOmitted = prefix, len(prefix) != len(change.Diff)
	return view
}

func alreadyReadFile(f workspace.File) map[string]any {
	return map[string]any{
		"file":         map[string]string{"path": f.Path, "version": f.Version},
		"already_read": true,
		"next_step":    "Use the unchanged content already available in this turn's input.",
	}
}
