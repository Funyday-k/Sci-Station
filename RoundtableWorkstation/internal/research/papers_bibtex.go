package research

import (
	"errors"
	"net/http"
	"net/url"
	"slices"
	"strconv"
	"strings"
	"unicode"
	"unicode/utf8"
)

func normalizeBibliography(m *PaperMetadata) error {
	for _, field := range []*string{&m.PublicationTitle, &m.Publisher, &m.Volume, &m.Issue, &m.Pages, &m.ItemType} {
		*field = strings.TrimSpace(*field)
		if *field != "" && !label(*field, 4096) {
			return errInvalidPaper
		}
	}
	if len(m.BibTeX) > 256<<10 {
		return errInvalidPaper
	}
	var err error
	m.Categories, err = paperListClean(m.Categories, 128, 128)
	return err
}

var bibField = strings.NewReplacer(
	"\\", `\textbackslash{}`, "{", `\{`, "}", `\}`, "&", `\&`, "%", `\%`,
	"#", `\#`, "_", `\_`, "$", `\$`, "^", `\^{}`, "~", `\~{}`,
)

func paperBibtex(p Paper) string {
	var notice string
	if source := strings.TrimSpace(p.BibTeX); source != "" {
		entry, err := replaceBibtexKey(source, p.Citekey)
		if err == nil {
			return entry + "\n"
		}
		notice = "% Sci-Station: " + err.Error() + "; generated from paper metadata.\n"
	}
	var fields []string
	add := func(key, value string) {
		if text := strings.Join(strings.Fields(value), " "); text != "" {
			fields = append(fields, "  "+key+" = {"+bibField.Replace(text)+"}")
		}
	}
	add("title", p.Title)
	add("author", strings.Join(p.Authors, " and "))
	if p.Year > 0 {
		add("year", strconv.Itoa(p.Year))
	}
	itemType := strings.ToLower(p.ItemType)
	entryType, publicationField := "misc", "journal"
	switch {
	case strings.Contains(itemType, "book"):
		entryType = "book"
	case strings.Contains(itemType, "proceedings") || strings.Contains(itemType, "conference"):
		entryType, publicationField = "inproceedings", "booktitle"
	case strings.Contains(itemType, "thesis") || strings.Contains(itemType, "dissertation"):
		entryType = "phdthesis"
	case strings.Contains(itemType, "article") || p.PublicationTitle != "":
		entryType = "article"
	}
	add(publicationField, p.PublicationTitle)
	add("publisher", p.Publisher)
	add("volume", p.Volume)
	add("number", p.Issue)
	add("pages", p.Pages)
	add("doi", p.DOI)
	add("url", p.URL)
	if p.Arxiv != "" {
		add("eprint", p.Arxiv)
		add("archivePrefix", "arXiv")
		if len(p.Categories) > 0 {
			add("primaryClass", p.Categories[0])
		}
	}
	return notice + "@" + entryType + "{" + p.Citekey + ",\n" + strings.Join(fields, ",\n") + "\n}\n"
}

func libraryBibtex(papers []Paper) string {
	slices.SortFunc(papers, func(a, b Paper) int {
		return strings.Compare(strings.ToLower(a.Citekey), strings.ToLower(b.Citekey))
	})
	var out strings.Builder
	for i, paper := range papers {
		if i > 0 {
			out.WriteByte('\n')
		}
		out.WriteString(paperBibtex(paper))
	}
	return out.String()
}

func sendBibtex(w http.ResponseWriter, papers []Paper) {
	w.Header().Set("Content-Type", "application/x-bibtex; charset=utf-8")
	w.Header().Set("Content-Disposition", `attachment; filename="references.bib"`)
	_, _ = w.Write([]byte(libraryBibtex(papers)))
}

// LibraryBibtex resolves the same filtered records for the desktop save panel
// and for the offline browser download.
func (s *Service) LibraryBibtex(query url.Values) (string, error) {
	papers, err := s.papers.libraryPapers(query)
	if err != nil {
		return "", err
	}
	return libraryBibtex(papers), nil
}

var errMalformedBibtex = errors.New("Malformed BibTeX entry boundaries or citation key")

// Replace only the bibliographic key. Field values, custom fields, quoted
// content, and directives retain their exact source text.
func replaceBibtexKey(source, key string) (string, error) {
	if !paperCitekeyPattern.MatchString(key) {
		return "", errors.New("Invalid application citation key")
	}
	first, last, count := 0, 0, 0
	for cursor := 0; cursor < len(source); {
		switch source[cursor] {
		case '%':
			cursor = skipBibtexComment(source, cursor)
		case '@':
			cursor++
			start := cursor
			for cursor < len(source) && ((source[cursor] >= 'a' && source[cursor] <= 'z') ||
				(source[cursor] >= 'A' && source[cursor] <= 'Z')) {
				cursor++
			}
			entryType := strings.ToLower(source[start:cursor])
			cursor = skipBibtexTrivia(source, cursor)
			if entryType == "" || cursor == len(source) || (source[cursor] != '{' && source[cursor] != '(') {
				return "", errMalformedBibtex
			}
			end, err := bibtexBlockEnd(source, cursor, entryType == "comment")
			if err != nil {
				return "", err
			}
			switch entryType {
			case "comment", "string", "preamble":
				// A directive is allowed but does not have a bibliographic key.
			default:
				first = skipBibtexTrivia(source, cursor+1)
				last = first
				for last < end {
					r, n := utf8.DecodeRuneInString(source[last:])
					if unicode.IsSpace(r) || strings.ContainsRune(`{}(),="#%\@`, r) {
						break
					}
					last += n
				}
				comma := skipBibtexTrivia(source, last)
				if first == last || comma >= end || source[comma] != ',' {
					return "", errMalformedBibtex
				}
				count++
			}
			cursor = end
		default:
			cursor++
		}
	}
	switch count {
	case 0:
		return "", errors.New("No bibliographic entry in provider BibTeX")
	case 1:
		return source[:first] + key + source[last:], nil
	default:
		return "", errors.New("Multiple bibliographic entries in provider BibTeX")
	}
}

func skipBibtexComment(source string, start int) int {
	for start < len(source) && source[start] != '\n' && source[start] != '\r' {
		start++
	}
	return start
}

func skipBibtexTrivia(source string, start int) int {
	for start < len(source) {
		if source[start] == '%' {
			start = skipBibtexComment(source, start)
			continue
		}
		r, count := utf8.DecodeRuneInString(source[start:])
		if !unicode.IsSpace(r) {
			break
		}
		start += count
	}
	return start
}

func bibtexBlockEnd(source string, start int, comment bool) (int, error) {
	braced := source[start] == '{'
	outerBraceDepth, parentheses := 0, 1
	if braced {
		outerBraceDepth, parentheses = 1, 0
	}
	braces, quoted := outerBraceDepth, false
	for i := start + 1; i < len(source); i++ {
		c := source[i]
		if c == '\\' {
			i++
			continue
		}
		if quoted {
			if c == '"' {
				quoted = false
			}
			continue
		}
		switch {
		case c == '"' && braces == outerBraceDepth && !comment:
			quoted = true
		case c == '%' && braces == outerBraceDepth && !comment:
			i = skipBibtexComment(source, i) - 1
		case c == '{':
			braces++
		case c == '}':
			braces--
			if braced && braces == 0 {
				return i + 1, nil
			}
			if braces < 0 {
				return 0, errMalformedBibtex
			}
		case !braced && braces == 0 && c == '(':
			parentheses++
		case !braced && braces == 0 && c == ')':
			parentheses--
			if parentheses == 0 {
				return i + 1, nil
			}
		}
	}
	return 0, errMalformedBibtex
}
