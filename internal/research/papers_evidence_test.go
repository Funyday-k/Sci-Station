package research

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestPDFQuoteRangeUsesUTF16(t *testing.T) {
	start, end := 12, 20
	text := "🔎 Evidence Evidence"
	e := Evidence{Quote: "Evidence", SelectionStart: &start, SelectionEnd: &end}
	if !validPDFSelectionRange(e.SelectionStart, e.SelectionEnd) || !matchesPDFQuote(text, e) {
		t.Fatal("UTF-16 range did not resolve the second evidence occurrence")
	}
	start = 11
	if matchesPDFQuote(text, e) {
		t.Fatal("accepted a range in rune instead of UTF-16 coordinates")
	}
	if validPDFSelectionRange(&start, nil) {
		t.Fatal("accepted an open-ended source range")
	}
}

func TestAnnotationMergePreservesExistingExtensions(t *testing.T) {
	book := []byte(`{"annotations":[{"id":"a","note":"old","extension":{"engine":2}}],"future":true}`)
	before := []byte(`{"annotations":[{"id":"a","note":"old"}]}`)
	after := []byte(`{"annotations":[{"id":"a","note":"edited"},{"id":"b","note":"new"}]}`)
	data := mergeRecordFields(book, before, after)
	if !json.Valid(data) || !strings.Contains(string(data), `"extension":{"engine":2}`) ||
		!strings.Contains(string(data), `"future":true`) || !strings.Contains(string(data), `"note":"edited"`) {
		t.Fatalf("failed to preserve extended record: %s", data)
	}
}
