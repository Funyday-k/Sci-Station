//go:build darwin && cgo

package research

import (
	"context"
	"crypto/sha256"
	"fmt"
	"os"
	"strings"
	"testing"
)

func TestLabPaperEvidenceUsesCurrentProjectPageAndOriginalDigest(t *testing.T) {
	s := newResearch(t, t.TempDir())
	p, q := createResearchProject(t, s, "Evidence"), createResearchProject(t, s, "Other")
	b, err := os.ReadFile(readerFixture(t))
	if err != nil {
		t.Fatal(err)
	}
	rec := uploadTestPDF(t, s.papers, string(b), fmt.Sprintf(`{"title":"Rotated fixture","project_ids":[%q]}`, p.ID))
	loc := SourceLocation{Kind: "paper", ID: rec.ID, Page: 2}
	hits, err := s.FindWorkflowSource(context.Background(), p.ID, loc, "sample")
	if err != nil || len(hits.Items) != 2 {
		t.Fatal(hits, err)
	}
	for i, hit := range hits.Items {
		if hit.Page != i+1 || hit.Offset != 9 || !strings.Contains(hit.Text, "Evidence sample") {
			t.Fatal(hit)
		}
	}
	src, err := s.WorkflowSource(context.Background(), p.ID, loc)
	if err != nil || !strings.Contains(src.Text, "Evidence sample") || src.Hash != fmt.Sprintf("%x", sha256.Sum256(b)) || src.Page != 2 {
		t.Fatal(src, err)
	}
	if _, err = s.WorkflowSource(context.Background(), q.ID, loc); err == nil {
		t.Fatal("unlinked project accessed paper")
	}
	loc.Page = 3
	if _, err = s.WorkflowSource(context.Background(), p.ID, loc); err == nil {
		t.Fatal("missing page accepted")
	}
	loc.Page = 1
	path, err := s.papers.PDFPath(rec.ID)
	if err != nil {
		t.Fatal(err)
	}
	if err = os.WriteFile(path, append(b, byte(' ')), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err = s.WorkflowSource(context.Background(), p.ID, loc); err == nil {
		t.Fatal("accepted modified bytes despite recorded PDF fingerprint")
	}

}

func TestLabPDFSelectionReplaysUTF16AcrossLineEndings(t *testing.T) {
	s := WorkflowSource{rawText: "😀\r\n Method\r\nline", SourceLocation: SourceLocation{Offset: 3}}
	quote, start, end := s.PDFSelection("Method\nline")
	if quote != "Method\r\nline" || start != 5 || end != 17 {
		t.Fatalf("quote %q at [%d,%d)", quote, start, end)
	}
}
