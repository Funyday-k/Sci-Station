package meeting

import (
	"archive/zip"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestNativeMaterialExcerptTextAndDOCX(t *testing.T) {
	dir := t.TempDir()
	txt := filepath.Join(dir, "note.txt")
	if err := os.WriteFile(txt, []byte("Local text preview"), 0600); err != nil {
		t.Fatal(err)
	}
	got, err := nativeMaterialExcerpt(txt, "text/plain", "note.txt")
	if err != nil || got != "Local text preview" {
		t.Fatalf("text: %q, %v", got, err)
	}
	docx := filepath.Join(dir, "note.docx")
	f, err := os.Create(docx)
	if err != nil {
		t.Fatal(err)
	}
	z := zip.NewWriter(f)
	w, err := z.Create("word/document.xml")
	if err != nil {
		t.Fatal(err)
	}
	_, err = w.Write([]byte(`<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:r><w:t>你好 document</w:t></w:r></w:p></w:body></w:document>`))
	if err != nil {
		t.Fatal(err)
	}
	if err = z.Close(); err != nil {
		t.Fatal(err)
	}
	if err = f.Close(); err != nil {
		t.Fatal(err)
	}
	got, err = nativeMaterialExcerpt(docx, "application/vnd.openxmlformats-officedocument.wordprocessingml.document", "note.docx")
	if err != nil || !strings.Contains(got, "你好 document") {
		t.Fatalf("docx: %q, %v", got, err)
	}
}

func TestNativeMaterialExcerptUnsupportedDoesNotClaimRead(t *testing.T) {
	p := filepath.Join(t.TempDir(), "x.bin")
	_ = os.WriteFile(p, []byte("opaque"), 0600)
	got, err := nativeMaterialExcerpt(p, "application/octet-stream", "x.bin")
	if err == nil || got != "" {
		t.Fatalf("got %q, %v", got, err)
	}
}
