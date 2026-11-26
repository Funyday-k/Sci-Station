package research

import (
	"crypto/sha256"
	"fmt"
	"html"
	"net/url"
	"path"
	"regexp"
	"slices"
	"strings"
	"unicode"
	"unicode/utf8"
)

const maxPaperFigures = 512

var (
	markdownImage       = regexp.MustCompile(`!\[((?:\\.|[^\\\]])*)\]\([ \t]*(?:<([^>]+)>|((?:\\.|[^\s\\()]|\([^()\s]*\))+))(?:[ \t]+(?:"[^"]*"|'[^']*'|\([^()]*\)))?[ \t]*\)`)
	htmlImage           = regexp.MustCompile("(?i)<img\\b(?:[^<>\"']|\"[^\"]*\"|'[^']*')*>")
	htmlAttribute       = regexp.MustCompile(`(?i)[^\s="'<>/]+` + "(?:\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s\"'=<>\x60]+)))?")
	figureCaption       = regexp.MustCompile(`(?i)^(?:(?:extended data )?(?:figure|fig\.?)[ \t]*[a-z]?[0-9]+[a-z]?\b|图[ \t]*[a-z]?[0-9]+[a-z]?)`)
	htmlCaption         = regexp.MustCompile(`(?i)^<figcaption\b[^>]*>(.*?)</figcaption\s*>$`)
	markdownEscapedPath = regexp.MustCompile(`\\([[:punct:]])`)
)

type BodyFigure struct {
	localReference string
	Reference      string `json:"reference"`
	AssetID        string `json:"assetId,omitempty"`
	Label          string `json:"label,omitempty"`
	Line           int    `json:"line"`
	Offset         int    `json:"offset"`
	End            int    `json:"end"`
	CiteStart      int    `json:"citeStart"`
	CiteEnd        int    `json:"citeEnd"`
}

type BodyQuality struct {
	Engine            string       `json:"engine"`
	HasAbstract       bool         `json:"hasAbstract"`
	HasDisplayMath    bool         `json:"hasDisplayMath"`
	MissingFigures    int          `json:"missingFigures"`
	Figures           []BodyFigure `json:"figures,omitempty"`
	FigureListLimited bool         `json:"figureListLimited,omitempty"`
	AssetCheckFailed  bool         `json:"assetCheckFailed,omitempty"`
}

type figureReference struct {
	source string
	alt    string
	start  int
	end    int
}

func imageReferences(line string) []figureReference {
	var refs []figureReference
	if strings.Contains(line, "![") {
		for _, m := range markdownImage.FindAllStringSubmatchIndex(line, maxPaperFigures+1) {
			if markdownPunctuationEscaped(line, m[0]) {
				continue
			}
			start, end := m[4], m[5]
			if start == -1 {
				start, end = m[6], m[7]
			}
			src := markdownEscapedPath.ReplaceAllString(line[start:end], "$1")
			refs = append(refs, figureReference{src, line[m[2]:m[3]], m[0], m[1]})
		}
	}
	if strings.Contains(strings.ToLower(line), "<img") {
		for _, m := range htmlImage.FindAllStringIndex(line, maxPaperFigures+1) {
			if markdownPunctuationEscaped(line, m[0]) {
				continue
			}
			src, alt := "", ""
			for _, attr := range htmlAttribute.FindAllStringSubmatch(line[m[0]+4:m[1]-1], -1) {
				key, _, _ := strings.Cut(attr[0], "=")
				value := attr[1] + attr[2] + attr[3]
				switch strings.ToLower(strings.TrimSpace(key)) {
				case "src":
					if src == "" {
						src = value
					}
				case "alt":
					if alt == "" {
						alt = value
					}
				}
			}
			if src != "" {
				refs = append(refs, figureReference{src, alt, m[0], m[1]})
			}
		}
	}
	slices.SortFunc(refs, func(a, b figureReference) int { return a.start - b.start })
	return refs
}

func markdownPunctuationEscaped(s string, i int) bool {
	start := i
	for start > 0 && s[start-1] == '\\' {
		start--
	}
	return (i-start)%2 == 1
}

// Return a package-relative name. Parent segments in a relative reference are
// allowed only when the Markdown entry's own directory keeps it inside the ZIP.
func paperFigureReference(raw string) string {
	raw = strings.TrimSpace(html.UnescapeString(raw))
	if len(raw) == 0 || len(raw) > 1024 || strings.HasPrefix(raw, "/") {
		return ""
	}
	u, err := url.Parse(raw)
	if err != nil || u.IsAbs() || u.Host != "" || u.User != nil || u.Opaque != "" || u.ForceQuery || u.RawQuery != "" || u.Fragment != "" {
		return ""
	}
	if u.Path == "" || strings.HasPrefix(u.Path, "/") || strings.ContainsAny(u.Path, "\\:") ||
		strings.IndexFunc(u.Path, unicode.IsControl) >= 0 {
		return ""
	}
	return path.Clean(u.Path)
}

func figureAssetID(relative string) string {
	return fmt.Sprintf("%x", sha256.Sum256([]byte(relative)))
}

func figureText(s string, size int) string {
	for i := range s {
		if size == 0 {
			return s[:i]
		}
		size--
	}
	return s
}

type captionLocation struct {
	text   string
	line   int
	offset int
	end    int
}

func (c captionLocation) apply(f *BodyFigure) {
	f.Label, f.CiteStart, f.CiteEnd = c.text, c.offset, c.end
}

func inspectPaperBody(text, origin string) BodyQuality {
	out := BodyQuality{Engine: origin}
	var lastCaption captionLocation
	var waiting []int
	var waitingLine int
	fence := ""
	front, comment := false, false
	displayOpen := false
	offset, line := 0, 0
	for raw := range strings.SplitSeq(text, "\n") {
		start := offset
		offset += utf8.RuneCountInString(raw) + 1
		line++
		v := strings.TrimSpace(strings.TrimPrefix(raw, "\ufeff"))
		if line == 1 && v == "---" {
			front = true
			continue
		}
		if front {
			if v == "---" || v == "..." {
				front = false
			} else if key, value, ok := strings.Cut(v, ":"); origin == "import" && ok && strings.EqualFold(strings.TrimSpace(key), "extraction_engine") {
				switch strings.ToLower(strings.Trim(strings.TrimSpace(value), "\"'")) {
				case "pdfkit_fallback", "pdfkit":
					out.Engine = "pdfkit"
				case "mineru_api", "mineru_cli", "mineru":
					out.Engine = "mineru"
				}
			}
			continue
		}
		if comment || strings.HasPrefix(v, "<!--") {
			comment = !strings.Contains(v, "-->")
			continue
		}
		previousFence := fence
		heading := markdownLineHeading(raw, &fence)
		if previousFence != "" || fence != "" {
			continue
		}
		if heading != "" {
			lastCaption, waiting = captionLocation{}, nil
			out.HasAbstract = out.HasAbstract || strings.EqualFold(heading, "abstract") || heading == "摘要"
		}
		if !out.HasDisplayMath {
			for i := 0; i+1 < len(raw); i++ {
				switch raw[i : i+2] {
				case "$$":
					if !markdownPunctuationEscaped(raw, i) {
						out.HasDisplayMath = out.HasDisplayMath || displayOpen
						displayOpen = !displayOpen
						i++
					}
				case "\\[":
					if !markdownPunctuationEscaped(raw, i) {
						displayOpen = true
						i++
					}
				case "\\]":
					if !markdownPunctuationEscaped(raw, i) {
						out.HasDisplayMath = out.HasDisplayMath || displayOpen
						displayOpen = false
						i++
					}
				}
			}
		}
		if v == "" {
			continue
		}
		if len(out.Figures) >= maxPaperFigures {
			if strings.Contains(raw, "![") || strings.Contains(strings.ToLower(raw), "<img") {
				out.FigureListLimited = true
			}
		} else if refs := imageReferences(raw); len(refs) > 0 {
			waiting, waitingLine = nil, line
			bytePos, runePos := 0, start
			for _, ref := range refs {
				if ref.start < bytePos {
					continue
				}
				if len(out.Figures) == maxPaperFigures {
					out.FigureListLimited = true
					break
				}
				runePos += utf8.RuneCountInString(raw[bytePos:ref.start])
				end := runePos + utf8.RuneCountInString(raw[ref.start:ref.end])
				f := BodyFigure{Reference: figureText(ref.source, 300), Label: figureText(html.UnescapeString(ref.alt), 300),
					Line: line, Offset: runePos, End: end, CiteStart: runePos, CiteEnd: end}
				f.localReference = paperFigureReference(ref.source)
				if f.localReference != "" {
					f.Reference = html.UnescapeString(ref.source)
				}
				if lastCaption.text != "" && line-lastCaption.line <= 3 && lastCaption.end-lastCaption.offset <= maxProjectEvidenceRunes {
					lastCaption.apply(&f)
				} else {
					waiting = append(waiting, len(out.Figures))
				}
				out.Figures = append(out.Figures, f)
				bytePos, runePos = ref.end, end
			}
			lastCaption = captionLocation{}
			continue
		}
		label := strings.TrimLeft(v, "*_")
		if matches := htmlCaption.FindStringSubmatch(v); matches != nil {
			label = matches[1]
		} else if !figureCaption.MatchString(label) {
			lastCaption, waiting = captionLocation{}, nil
			continue
		}
		left := strings.Index(raw, v)
		begin := start + utf8.RuneCountInString(raw[:left])
		label = strings.TrimSpace(strings.TrimRight(label, "*_"))
		lastCaption = captionLocation{figureText(html.UnescapeString(label), 300), line, begin, begin + utf8.RuneCountInString(v)}
		if len(waiting) > 0 && line-waitingLine <= 3 && lastCaption.end-lastCaption.offset <= maxProjectEvidenceRunes {
			for _, index := range waiting {
				lastCaption.apply(&out.Figures[index])
			}
			lastCaption = captionLocation{}
		}
		waiting = nil
	}
	return out
}

func (q *BodyQuality) attachAssets(assets map[string]paperAsset) {
	for i := range q.Figures {
		f := &q.Figures[i]
		id := figureAssetID(f.localReference)
		if _, ok := assets[id]; ok {
			f.AssetID = id
		} else {
			q.MissingFigures++
		}
	}
}

func nearbyBodyFigures(figures []BodyFigure, start, end, firstLine, lastLine int) []BodyFigure {
	nearby := make([]BodyFigure, 0, min(len(figures), 20))
	for _, figure := range figures {
		if figure.Line >= firstLine-4 && figure.Line <= lastLine+4 || figure.Offset < end && figure.End > start ||
			figure.CiteStart < end && figure.CiteEnd > start {
			nearby = append(nearby, figure)
			if len(nearby) == cap(nearby) {
				break
			}
		}
	}
	return nearby
}
