package research

import (
	"regexp"
	"strings"
	"unicode/utf8"
)

const maxPaperPassageRunes = 1000

type paperSelector struct{ kind, value string }

func (i paperQuestionIntent) selectors() []paperSelector {
	var selectors []paperSelector
	for _, label := range i.figures {
		selectors = append(selectors, paperSelector{"figure", label})
	}
	for _, label := range i.equations {
		selectors = append(selectors, paperSelector{"equation", label})
	}
	if len(selectors) != 0 {
		return selectors
	}
	if i.formula {
		return []paperSelector{{"equation", ""}}
	}
	if i.section != "" {
		return []paperSelector{{"section", i.section}}
	}
	return []paperSelector{{"body", ""}}
}

func (m paperSelector) label() string {
	switch m.kind {
	case "figure":
		return "图 " + m.value + " 的图注"
	case "equation":
		if m.value != "" {
			return "编号为 " + m.value + " 的公式"
		}
		return "与问题匹配的公式及其出处"
	case "section":
		return "与 " + m.value + " 对应的章节"
	default:
		return "可引用的正文"
	}
}

type paperBodyLine struct {
	text, heading string
	offset, line  int
	available     bool
}

func paperBodyLines(input []string) []paperBodyLine {
	lines := make([]paperBodyLine, len(input))
	var offset int
	var heading, fence string
	var frontmatter, comment bool
	for index, raw := range input {
		left := strings.TrimLeft(raw, " \t\uFEFF")
		text := strings.TrimRight(left, " \t")
		lineOffset := offset + utf8.RuneCountInString(raw[:len(raw)-len(left)])
		offset += utf8.RuneCountInString(raw) + 1
		available := text != ""
		switch {
		case index == 0 && text == "---":
			frontmatter, available = true, false
		case frontmatter:
			frontmatter, available = text != "---" && text != "...", false
		case comment || strings.HasPrefix(text, "<!--"):
			comment, available = !strings.Contains(text, "-->"), false
		default:
			wasFenced := fence != ""
			if title := markdownLineHeading(raw, &fence); title != "" {
				heading, available = title, false
			} else if wasFenced || fence != "" {
				available = false
			}
		}
		lines[index] = paperBodyLine{text, heading, lineOffset, index + 1, available}
	}
	return lines
}

type paperMatch struct {
	quote, heading      string
	line, offset, score int
}

var captionPrefix = regexp.MustCompile(`(?i)^(?:fig(?:ure)?\.?[\s\x{00a0}]*|图[\s\x{00a0}]*)([0-9]+[a-z]?)(?:[.)）:：–—-]|[*_]|$)`)

func captionLine(text string) (id, description string) {
	if strings.HasPrefix(text, "![") {
		// Image references are not captions. A separately printed caption
		// supplies its own text without including an asset's local path.
		return "", ""
	}
	text = strings.TrimLeft(text, "*_")
	label := captionPrefix.FindStringSubmatchIndex(text)
	if label == nil {
		return "", ""
	}
	return strings.ToLower(text[label[2]:label[3]]), strings.TrimLeft(text[label[1]:], "*_ .:：)）–—-")
}

func equationRange(lines []paperBodyLine, index int) (int, bool) {
	text := lines[index].text
	var opener, closer string
	switch {
	case equationEnvironment.MatchString(text):
		env := equationEnvironment.FindStringSubmatch(text)[1]
		opener, closer = "\\begin{"+env+"}", "\\end{"+env+"}"
	case strings.Contains(text, "$$"):
		opener, closer = "$$", "$$"
	case strings.Contains(text, "\\["):
		opener, closer = "\\[", "\\]"
	}
	if opener == "" {
		for _, span := range inlineEquation.FindAllString(text, -1) {
			if equationRelation.MatchString(span) {
				return index, true
			}
		}
		return 0, false
	}
	_, rest, _ := strings.Cut(text, opener)
	if strings.Contains(rest, closer) {
		return index, true
	}
	for end := index + 1; end < min(index+24, len(lines)); end++ {
		next := lines[end]
		if (!next.available && next.text != "") || lines[index].heading != next.heading {
			break
		}
		if strings.Contains(next.text, closer) {
			if end+1 < len(lines) && next.text == closer && equationTag.MatchString(lines[end+1].text) &&
				strings.HasPrefix(lines[end+1].text, "(") {
				end++
			}
			return end, true
		}
	}
	return 0, false
}

func hasEquationLabel(quote, value string) bool {
	for _, tag := range equationTag.FindAllStringSubmatch(quote, -1) {
		if tag[1] == value || tag[2] == value {
			return true
		}
	}
	return false
}

func sectionLabel(text string) string {
	switch strings.ToLower(sectionQuestion.FindString(text)) {
	case "abstract", "摘要":
		return "abstract"
	case "introduction", "引言", "介绍":
		return "introduction"
	case "methods", "method", "方法":
		return "method"
	case "results", "result", "结果":
		return "result"
	case "conclusions", "conclusion", "结论":
		return "conclusion"
	case "discussion", "讨论":
		return "discussion"
	case "limitations", "limitation", "局限":
		return "limitation"
	default:
		return ""
	}
}

func paperCandidate(lines []paperBodyLine, input []string, start, end int) *paperMatch {
	var quote string
	if start == end {
		quote = lines[start].text
	} else {
		quote = strings.TrimRight(strings.Join(input[start:end+1], "\n"), " \t")
		quote = strings.TrimLeft(quote, " \t\uFEFF")
	}
	if utf8.RuneCountInString(quote) > maxPaperPassageRunes || !realMarkdownBody([]byte(quote)) {
		return nil
	}
	line := lines[start]
	return &paperMatch{quote: quote, heading: line.heading, line: line.line, offset: line.offset}
}

func (m paperSelector) find(text, heading string) *paperMatch {
	input := strings.Split(normalizeWorkflowText(text), "\n")
	lines := paperBodyLines(input)
	for i := range lines {
		if lines[i].heading == "" {
			lines[i].heading = heading
		}
	}
	return m.choose(lines, input, nil)
}

var equationExplanation = regexp.MustCompile(`(?i)^where\b|^with\b|^in which\b|^其中|^式中`)

func equationContext(lines []paperBodyLine, input []string, from, to int, candidate *paperMatch, terms []string) *paperMatch {
	heading := candidate.heading
	context := []string{heading, candidate.quote}
	start, end := from, to
	if prev := from - 1; prev >= 0 && lines[prev].available && lines[prev].heading == heading {
		context = append(context, lines[prev].text)
		if paperTermScore(lines[prev].text, terms) != 0 {
			start = prev
		}
	}
	if next := to + 1; next < len(lines) && lines[next].available && lines[next].heading == heading {
		context = append(context, lines[next].text)
		if equationExplanation.MatchString(lines[next].text) {
			end = next
		}
	}
	score := paperTermScore(strings.Join(context, "\n"), terms)
	if start != from || end != to {
		if expanded := paperCandidate(lines, input, start, end); expanded != nil {
			candidate = expanded
		}
	}
	candidate.score = score
	return candidate
}

func (m paperSelector) choose(lines []paperBodyLine, input, terms []string) *paperMatch {
	var chosen *paperMatch
	bestCount := 0
	for index := 0; index < len(lines); index++ {
		line := lines[index]
		if !line.available {
			continue
		}
		last := index
		switch m.kind {
		case "figure":
			id, description := captionLine(line.text)
			if id != m.value {
				continue
			}
			if description == "" {
				if index+1 >= len(lines) || !lines[index+1].available || lines[index+1].heading != line.heading ||
					strings.HasPrefix(lines[index+1].text, "!") {
					continue
				}
				last++
			}
		case "equation":
			end, ok := equationRange(lines, index)
			if !ok {
				continue
			}
			last = end
		case "section":
			if sectionLabel(line.heading) != sectionLabel(m.value) {
				continue
			}
			for last+1 < len(lines) && lines[last+1].available && lines[last+1].heading == line.heading &&
				utf8.RuneCountInString(strings.Join(input[index:last+2], "\n")) <= maxPaperPassageRunes {
				last++
			}
		default:
			if sectionLabel(line.heading) == "abstract" {
				for last+1 < len(lines) && lines[last+1].available && lines[last+1].heading == line.heading &&
					utf8.RuneCountInString(strings.Join(input[index:last+2], "\n")) <= maxPaperPassageRunes {
					last++
				}
			}
		}
		candidate := paperCandidate(lines, input, index, last)
		if candidate != nil {
			if m.kind == "equation" {
				if m.value != "" && !hasEquationLabel(candidate.quote, m.value) {
					index = last
					continue
				}
				candidate = equationContext(lines, input, index, last, candidate, terms)
				if m.value == "" && len(terms) != 0 && candidate.score == 0 {
					index = last
					continue
				}
			}
			if m.kind == "body" {
				candidate.score = paperTermScore(line.heading+"\n"+candidate.quote, terms) * 2
				if sectionLabel(line.heading) == "abstract" {
					candidate.score++
				}
			}
			switch {
			case chosen == nil || candidate.score > chosen.score:
				chosen, bestCount = candidate, 1
			case candidate.score == chosen.score:
				bestCount++
			}
		}
		index = last
	}
	if (m.kind == "equation" || m.kind == "figure") && bestCount > 1 {
		return nil
	}
	return chosen
}

func paperTermScore(text string, terms []string) int {
	text = strings.ToLower(text)
	score := 0
	for _, term := range terms {
		if strings.Contains(text, term) {
			score++
			continue
		}
		for _, pair := range [][2]string{{"蒸发率", "evaporation rate"}, {"湮灭率", "annihilation rate"}, {"捕获率", "capture rate"}} {
			if (term == pair[0] && strings.Contains(text, pair[1])) ||
				(strings.Contains(pair[1], term) && len(term) >= 4 && strings.Contains(text, pair[0])) {
				score++
			}
		}
	}
	return score
}
