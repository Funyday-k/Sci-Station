package meeting

import (
	"strings"
	"unicode/utf8"
)

// continuousQuoteOptions returns short, verbatim candidates from visible text.
// It splits at lines and sentence punctuation, keeping punctuation in each
// candidate. Long clauses are sampled from their beginning and end without
// cutting a UTF-8 rune.
func continuousQuoteOptions(text string) []string {
	const maxRunes = 180
	text = strings.ReplaceAll(text, "[… middle omitted …]", "\n")
	text = strings.ReplaceAll(text, "[... middle omitted ...]", "\n")
	var segments []string
	start := 0
	runes := []rune(text)
	for i, r := range runes {
		isBoundary := r == '\n' || r == '\r' || strings.ContainsRune("。！？!?；;", r)
		if r == '.' {
			prevDigit := i > 0 && runes[i-1] >= '0' && runes[i-1] <= '9'
			nextDigit := i+1 < len(runes) && runes[i+1] >= '0' && runes[i+1] <= '9'
			nextSpaceOrEnd := i+1 == len(runes) || runes[i+1] == ' ' || runes[i+1] == '\t' || runes[i+1] == '\n' || runes[i+1] == '\r'
			previousToken := ""
			if i > 0 {
				j := i - 1
				for j >= 0 && runes[j] != ' ' && runes[j] != '\t' && runes[j] != '\n' && runes[j] != '\r' {
					j--
				}
				previousToken = string(runes[j+1 : i])
			}
			// A period after a path/filename token is internal punctuation;
			// common title abbreviations and single-letter initials are too.
			abbreviation := strings.Contains(" Dr Mr Mrs Ms Prof e.g i.e etc vs Fig Eq Ref No St ", " "+previousToken+" ") || len([]rune(previousToken)) == 1
			isBoundary = nextSpaceOrEnd && !(prevDigit && nextDigit) && !abbreviation
		}
		if isBoundary {
			if candidate := strings.TrimSpace(string(runes[start : i+1])); candidate != "" {
				segments = append(segments, candidate)
			}
			start = i + 1
		}
	}
	if candidate := strings.TrimSpace(string(runes[start:])); candidate != "" {
		segments = append(segments, candidate)
	}
	var options []string
	seen := make(map[string]bool)
	var eligible []string
	for _, segment := range segments {
		if strings.Contains(segment, "middle omitted") || strings.Contains(segment, "中间内容已省略") {
			continue
		}
		eligible = append(eligible, segment)
	}
	if len(eligible) == 0 {
		return nil
	}
	indices := []int{0}
	if len(eligible) > 2 {
		indices = append(indices, len(eligible)/2)
	}
	if len(eligible) > 1 {
		indices = append(indices, len(eligible)-1)
	}
	for _, index := range indices {
		part := eligible[index]
		if utf8.RuneCountInString(part) > maxRunes {
			part = string([]rune(part)[:maxRunes])
		}
		part = strings.TrimSpace(part)
		if part == "" || seen[part] {
			continue
		}
		seen[part] = true
		options = append(options, part)
	}
	return options
}
