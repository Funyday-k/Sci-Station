package research

import (
	"crypto/sha256"
	"math"
	"strings"
	"unicode"
	"unicode/utf8"
)

const (
	retrievalDimensions  = 32
	retrievalChunkLines  = 80
	retrievalChunkRunes  = 4000
	retrievalChunkLimit  = 4096
	retrievalResultLimit = 12
)

// Match the Swift deterministic fallback's signed hash buckets. The
// workstation stores counts and calculates cosine on demand.
type retrievalVector [retrievalDimensions]int32

func retrievalTokens(text string) []string {
	return strings.FieldsFunc(strings.ToLower(text), func(r rune) bool {
		return !unicode.IsLetter(r) && !unicode.IsNumber(r) && !unicode.IsMark(r)
	})
}

func vectorForRetrieval(terms []string) retrievalVector {
	var vector retrievalVector
	for _, term := range terms {
		digest := sha256.Sum256([]byte(term))
		delta := int32(1)
		if digest[1]%2 != 0 {
			delta = -1
		}
		vector[int(digest[0])%len(vector)] += delta
	}
	return vector
}

func (v retrievalVector) cosine(other retrievalVector) float64 {
	var dot, a2, b2 float64
	for i, n := range v {
		a, b := float64(n), float64(other[i])
		dot += a * b
		a2 += a * a
		b2 += b * b
	}
	if a2 == 0 || b2 == 0 {
		return 0
	}
	return dot / math.Sqrt(a2*b2)
}

type retrievalChunk struct {
	offset   int
	line     int
	lastLine int
	heading  string
	text     string
}

// Keep exact normalized line endings and spacing for the preview locator.
// Split unusually long lines as well as headings and 80-line blocks.
func workflowRetrievalChunks(text string, markdown bool) ([]retrievalChunk, bool) {
	chunks := make([]retrievalChunk, 0, 16)
	byteAt, charAt, line, segment := 0, 0, 1, 0
	heading, fence := "", ""
	current := retrievalChunk{line: 1}
	flush := func(end int) {
		current.text = strings.TrimRight(text[segment:end], "\n")
		if strings.TrimSpace(current.text) != "" {
			current.lastLine = current.line + strings.Count(current.text, "\n")
			chunks = append(chunks, current)
		}
	}
	begin := func(start int) {
		segment = start
		current = retrievalChunk{offset: charAt, line: line, heading: heading}
	}
	for raw := range strings.SplitSeq(text, "\n") {
		if len(chunks) == retrievalChunkLimit {
			return chunks, true
		}
		if markdown {
			if title := markdownLineHeading(raw, &fence); title != "" {
				flush(byteAt)
				heading = title
				begin(byteAt)
			}
		}
		for i := range raw {
			if charAt-current.offset >= retrievalChunkRunes {
				flush(byteAt + i)
				if len(chunks) == retrievalChunkLimit {
					return chunks, true
				}
				begin(byteAt + i)
			}
			charAt++
		}
		byteAt += len(raw)
		if byteAt == len(text) {
			flush(byteAt)
			break
		}
		byteAt++
		charAt++
		if line-current.line+1 >= retrievalChunkLines {
			flush(byteAt)
			line++
			begin(byteAt)
		} else {
			line++
		}
	}
	return chunks, false
}

func lexicalRetrievalScore(query string, queryTokens, terms []string, text string) (float64, int) {
	folded := strings.ToLower(text)
	if at := strings.Index(folded, query); at >= 0 {
		return 1, utf8.RuneCountInString(folded[:at])
	}
	matched := 0
	first := len(folded)
	available := make(map[string]bool, len(terms))
	for _, term := range terms {
		available[term] = true
	}
	for _, term := range queryTokens {
		if available[term] {
			matched++
			first = min(first, strings.Index(folded, term))
		}
	}
	if matched == 0 {
		return 0, 0
	}
	return float64(matched) / float64(len(queryTokens)), utf8.RuneCountInString(folded[:first])
}
