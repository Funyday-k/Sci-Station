package research

import (
	"net/http"
	"regexp"
	"strings"
	"unicode"
	"unicode/utf8"
)

var wikiNamespacePrefix = regexp.MustCompile(`^[A-Za-z][A-Za-z0-9_-]*:`)
var wikiFence = regexp.MustCompile("^[ ]{0,3}(`{3,}|~{3,})(.*)$")
var wikiLink = regexp.MustCompile(`\[\[([^\[\]\n|#]+)(?:#[^\[\]|]*)?(?:\|[^\[\]]*)?\]\]`)

func validWikiPath(path string) bool {
	if !label(path, 500) || strings.ContainsAny(path, "\\[]|#:") {
		return false
	}
	for _, part := range strings.Split(path, "/") {
		if strings.TrimSpace(part) != part || part == "" || part == "." || part == ".." {
			return false
		}
	}
	return true
}

func wikiPath(n Note) string {
	if n.Namespace == "" {
		return n.Title
	}
	return n.Namespace + "/" + n.Title
}

func wikiNames(n Note) []string {
	names := []string{wikiPath(n)}
	for _, alias := range n.Aliases {
		if n.Namespace != "" && !strings.Contains(alias, "/") {
			names = append(names, n.Namespace+"/"+alias)
		} else {
			names = append(names, alias)
		}
	}
	return append(names, n.PreviousPaths...)
}

func retainMovedWikiPaths(n *Note, previous Note) {
	if strings.EqualFold(wikiPath(*n), wikiPath(previous)) {
		return
	}
	// Keep the previous canonical path and the previous namespace of aliases
	// that are still present. An explicitly removed alias stays removed.
	currentAliases := map[string]bool{}
	for _, alias := range n.Aliases {
		currentAliases[strings.ToLower(alias)] = true
	}
	oldPath := previous
	oldPath.Aliases = nil
	for _, alias := range previous.Aliases {
		if currentAliases[strings.ToLower(alias)] {
			oldPath.Aliases = append(oldPath.Aliases, alias)
		}
	}
	oldPath.PreviousPaths = nil
	keys := map[string]bool{}
	for _, path := range wikiNames(*n) {
		keys[strings.ToLower(path)] = true
	}
	var retained []string
	for _, path := range wikiNames(oldPath) {
		key := strings.ToLower(path)
		if !keys[key] {
			retained = append(retained, path)
			keys[key] = true
		}
	}
	if len(retained) > 0 {
		n.PreviousPaths = append(append([]string(nil), n.PreviousPaths...), retained...)
	}
}

func wikiNameTaken(d projectData, n Note) bool {
	wanted := map[string]bool{}
	for _, name := range wikiNames(n) {
		wanted[strings.ToLower(name)] = true
	}
	for id, other := range d.Notes {
		if id == n.ID {
			continue
		}
		for _, name := range wikiNames(other) {
			if wanted[strings.ToLower(name)] {
				return true
			}
		}
	}
	return false
}

type wikiIndex struct {
	exact, normalized, leaves map[string]string
	archived                  map[string]bool
}

func wikiLinkIndex(d projectData) wikiIndex {
	idx := wikiIndex{map[string]string{}, map[string]string{}, map[string]string{}, map[string]bool{}}
	for id, note := range d.Notes {
		idx.archived[id] = note.Archived
		for _, name := range wikiNames(note) {
			key := strings.ToLower(name)
			claimWikiName(idx.exact, key, id)
			normalized := normalizeWikiKey(key)
			claimWikiName(idx.normalized, normalized, id)
			if at := strings.LastIndexByte(normalized, '/'); at >= 0 {
				claimWikiName(idx.leaves, normalized[at+1:], id)
			}
		}
	}
	return idx
}

func claimWikiName(index map[string]string, key, id string) {
	if key == "" {
		return
	}
	if previous, exists := index[key]; exists && previous != id {
		index[key] = ""
	} else {
		index[key] = id
	}
}

func normalizeWikiKey(name string) string {
	parts := strings.Split(strings.ToLower(name), "/")
	for i, part := range parts {
		part = strings.TrimSuffix(part, ".md")
		part = strings.Map(func(r rune) rune {
			switch {
			case unicode.IsLetter(r), unicode.IsNumber(r), unicode.IsSpace(r):
				return r
			case r == '-' || r == '_':
				return ' '
			default:
				return -1
			}
		}, part)
		parts[i] = strings.Join(strings.Fields(part), " ")
	}
	if len(parts) > 1 {
		switch parts[0] {
		case "concepts", "methods", "papers", "projects", "authors", "datasets", "gaps", "notes":
			parts[0] = strings.TrimSuffix(parts[0], "s")
		}
	}
	return strings.Join(parts, "/")
}

// Resolve exact paths first, then legacy separator spelling. An unqualified
// link may name a unique leaf. Archived names remain reserved so links cannot
// silently change destinations during archive or restore.
func (idx wikiIndex) resolve(target string) string {
	key := strings.ToLower(strings.TrimSpace(target))
	if id, exists := idx.exact[key]; exists {
		return idx.activeID(id)
	}
	if prefix := wikiNamespacePrefix.FindString(key); prefix != "" {
		key = prefix[:len(prefix)-1] + "/" + strings.TrimSpace(key[len(prefix):])
		if id, exists := idx.exact[key]; exists {
			return idx.activeID(id)
		}
	}
	key = normalizeWikiKey(key)
	if id, exists := idx.normalized[key]; exists {
		return idx.activeID(id)
	}
	if strings.HasPrefix(key, "wiki/") {
		key = strings.TrimPrefix(key, "wiki/")
		if id, exists := idx.normalized[key]; exists {
			return idx.activeID(id)
		}
	}
	if strings.Contains(key, "/") {
		// Legacy notes in the default namespace were addressable through
		// qualified aliases before pages had an explicit directory.
		if _, target, _ := strings.Cut(key, "/"); !strings.Contains(target, "/") {
			return idx.activeID(idx.normalized[target])
		}
		return ""
	}
	return idx.activeID(idx.leaves[key])
}

func (idx wikiIndex) activeID(id string) string {
	if idx.archived[id] {
		return ""
	}
	return id
}

type wikiLinkOccurrence struct {
	Target  string
	Text    string
	Line    int
	Column  int
	Excerpt string
}

func wikiLinks(body string) []wikiLinkOccurrence {
	body = strings.ReplaceAll(strings.ReplaceAll(body, "\r\n", "\n"), "\r", "\n")
	lines := strings.Split(body, "\n")
	start := wikiBodyStart(lines)
	var links []wikiLinkOccurrence
	var fence string
	for i := start; i < len(lines); i++ {
		line := lines[i]
		if match := wikiFence.FindStringSubmatch(line); match != nil {
			if fence == "" {
				fence = match[1]
				continue
			}
			if match[1][0] == fence[0] && len(match[1]) >= len(fence) && strings.TrimSpace(match[2]) == "" {
				fence = ""
				continue
			}
		}
		if fence != "" {
			continue
		}
		search := maskInlineCode(line)
		column, from := 1, 0
		for _, match := range wikiLink.FindAllStringSubmatchIndex(search, -1) {
			column += utf8.RuneCountInString(line[from:match[0]])
			from = match[0]
			target := strings.TrimSpace(line[match[2]:match[3]])
			if target == "" || wikiLinkEscaped(line, match[0]) {
				continue
			}
			links = append(links, wikiLinkOccurrence{Target: target, Text: line[match[0]:match[1]], Line: i + 1, Column: column, Excerpt: line})
		}
	}
	return links
}

func wikiBodyStart(lines []string) int {
	if len(lines) == 0 || strings.TrimPrefix(lines[0], "\uFEFF") != "---" {
		return 0
	}
	for i, line := range lines[1:] {
		if delimiter := strings.TrimRight(line, " \t"); delimiter == "---" || delimiter == "..." {
			return i + 2
		}
	}
	return 0
}

var wikiBackticks = regexp.MustCompile("`+")

func maskInlineCode(line string) string {
	runs := wikiBackticks.FindAllStringIndex(line, -1)
	if len(runs) < 2 {
		return line
	}
	next := make([]int, len(runs))
	byLength := make(map[int]int)
	for i := len(runs) - 1; i >= 0; i-- {
		length := runs[i][1] - runs[i][0]
		next[i] = byLength[length] - 1
		byLength[length] = i + 1
	}
	masked := []byte(line)
	for i := 0; i < len(runs); i++ {
		end := next[i]
		if end < 0 || wikiLinkEscaped(line, runs[i][0]) {
			continue
		}
		for j := runs[i][0]; j < runs[end][1]; j++ {
			masked[j] = ' '
		}
		i = end
	}
	return string(masked)
}

func wikiLinkEscaped(line string, start int) bool {
	i := start
	for i > 0 && line[i-1] == '\\' {
		i--
	}
	return (start-i)%2 != 0
}

func (s *Service) noteLinks(w http.ResponseWriter, r *http.Request) {
	s.mu.RLock()
	d, ok := s.loadProject(w, r.PathValue("project"))
	s.mu.RUnlock()
	if !ok {
		return
	}
	n, exists := d.Notes[r.PathValue("note")]
	if !found(w, exists && !n.Archived) {
		return
	}
	if r.URL.Query().Has("revision") && !revisionOK(w, n.Revision, queryRevision(r.URL.Query())) {
		return
	}
	index := wikiLinkIndex(d)
	out := map[string]string{}
	for _, link := range wikiLinks(n.Body) {
		if id := index.resolve(link.Target); id != "" {
			out[link.Target] = id
		}
	}
	jsonReply(w, 200, out)
}
