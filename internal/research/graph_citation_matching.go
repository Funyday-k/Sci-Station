package research

import (
	"regexp"
	"sort"
	"strconv"
	"strings"
	"unicode"
)

var quotedCitationTitle = regexp.MustCompile(`"([^"\n]+)"|“([^”\n]+)”`)
var publicationYearText = regexp.MustCompile(`\b(18|19|20)[0-9]{2}\b`)

type graphCitationMatch struct {
	ID       string `json:"id"`
	Title    string `json:"title"`
	Distance int    `json:"distance"`
}

type citationTitle struct {
	ID, label, author string
	title             []rune
	year              int
}

type citationTitles map[int][]citationTitle

func citationAuthor(value string) string {
	if surname, _, ok := strings.Cut(value, ","); ok {
		return strings.ToLower(strings.TrimSpace(surname))
	}
	words := strings.Fields(value)
	if len(words) > 0 {
		return strings.ToLower(words[len(words)-1])
	}
	return ""
}

func normalizedCitationTitle(value string) []rune {
	var result []rune
	space := false
	for _, char := range value {
		switch {
		case unicode.IsLetter(char) || unicode.IsNumber(char):
			if space && len(result) > 0 {
				result = append(result, ' ')
			}
			result = append(result, unicode.ToLower(char))
			space = false
		case unicode.IsSpace(char) || char == '-' || char == '–':
			space = true
		}
		if len(result) > 512 {
			return nil
		}
	}
	return result
}

func indexCitationTitles(papers []Paper) citationTitles {
	result := citationTitles{}
	for _, p := range papers {
		title := normalizedCitationTitle(p.Title)
		if len(title) == 0 {
			continue
		}
		entry := citationTitle{ID: p.ID, label: p.Title, year: p.Year, title: title}
		if len(p.Authors) > 0 {
			entry.author = citationAuthor(p.Authors[0])
		}
		result[len(title)] = append(result[len(title)], entry)
	}
	return result
}

func citationTitleParts(raw string) (title []rune, author string, year int) {
	if matched := quotedCitationTitle.FindStringSubmatchIndex(raw); matched != nil {
		from, to := matched[2], matched[3]
		if from < 0 {
			from, to = matched[4], matched[5]
		}
		prefix := strings.TrimSpace(strings.TrimRight(strings.TrimSpace(raw[:matched[0]]), ",."))
		if prefix != "" {
			// First author in a quoted bibliographic reference may be given
			// as Lastname, Firstname or followed by an author list.
			if lead, _, ok := strings.Cut(prefix, " et al"); ok {
				prefix = lead
			}
			author = citationAuthor(prefix)
		}
		year, _ = strconv.Atoi(publicationYearText.FindString(raw[matched[1]:]))
		return normalizedCitationTitle(raw[from:to]), author, year
	}
	return normalizedCitationTitle(raw), "", 0
}

// Returns equally supported best candidates. A title inferred from free text
// never promotes a near match to a verified citation.
func (titles citationTitles) match(raw, source string) []graphCitationMatch {
	title, author, year := citationTitleParts(raw)
	if len(title) == 0 {
		return nil
	}
	radius := 0
	if len(title) > 15 {
		radius = 2
	}
	best := radius + 1
	var matches []graphCitationMatch
	for length := len(title) - radius; length <= len(title)+radius; length++ {
		for _, candidate := range titles[length] {
			if candidate.ID == source ||
				author != "" && candidate.author != "" && candidate.author != author ||
				year != 0 && candidate.year != 0 && candidate.year != year {
				continue
			}
			distance := citationTitleDistance(title, candidate.title, radius)
			if distance > radius || distance > best {
				continue
			}
			if distance < best {
				matches = nil
				best = distance
			}
			matches = append(matches, graphCitationMatch{ID: candidate.ID, Title: candidate.label, Distance: distance})
		}
	}
	sort.Slice(matches, func(i, j int) bool { return matches[i].ID < matches[j].ID })
	if len(matches) > 8 {
		matches = matches[:8]
	}
	return matches
}

// Edit distance constrained to a two-character band. Citation title lengths
// are checked before indexing, so work scales with the band and title length.
func citationTitleDistance(a, b []rune, limit int) int {
	if limit == 0 {
		if string(a) == string(b) {
			return 0
		}
		return 1
	}
	var column [513]int
	for i := range column[:len(b)+1] {
		column[i] = i
	}
	for i := 1; i <= len(a); i++ {
		first, last := max(1, i-limit), min(len(b), i+limit)
		diagonal := column[first-1]
		column[first-1] = limit + 1
		if first == 1 {
			column[0] = i
		}
		for j := first; j <= last; j++ {
			prior := column[j]
			cost := 0
			if a[i-1] != b[j-1] {
				cost = 1
			}
			column[j] = min(column[j-1]+1, prior+1, diagonal+cost)
			diagonal = prior
		}
		if last < len(b) {
			column[last+1] = limit + 1
		}
	}
	return column[len(b)]
}
