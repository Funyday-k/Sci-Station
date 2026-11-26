//go:build darwin && cgo

package research

import (
	"fmt"
	"net/http"
	"os"
	"strconv"
	"strings"
	"testing"
)

func TestPDFImportPreviewReadsEmbeddedTitleAndAuthors(t *testing.T) {
	data, err := os.ReadFile(readerFixture(t))
	if err != nil {
		t.Fatal(err)
	}
	_, trailer, _ := strings.Cut(string(data), "startxref\n")
	fields := strings.Fields(trailer)
	previous, err := strconv.Atoi(fields[0])
	if err != nil {
		t.Fatal(err)
	}
	// Add the PDF Info object with an incremental update, leaving the
	// independently generated two-page fixture and its original xref intact.
	offset := len(data)
	data = fmt.Appendf(data, "7 0 obj\n<< /Title (Notes on Solar Capture) /Author (Ada Ng and Jane Li) >>\nendobj\n")
	xref := len(data)
	data = fmt.Appendf(data, "xref\n7 1\n%010d 00000 n \ntrailer\n<< /Size 8 /Root 1 0 R /Info 7 0 R /Prev %d >>\nstartxref\n%d\n%%%%EOF\n", offset, previous, xref)
	lib := testPaperLib(t)
	res := paperPDFRequest(t, lib, "/preview", "different-filename.pdf", data)
	preview := decodeResearch[paperImportPreview](t, res.Body.Bytes())
	if res.Code != http.StatusOK || preview.Title != "Notes on Solar Capture" ||
		strings.Join(preview.Authors, ",") != "Ada Ng,Jane Li" || len(lib.all()) != 0 {
		t.Fatalf("PDF metadata preview %d %+v", res.Code, preview)
	}
}
