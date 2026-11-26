package meeting

import (
	"archive/zip"
	"bytes"
	"io"
	"strings"
	"testing"
)

func TestStoreFindAndOpenMaterial(t *testing.T) {
	e := &Engine{dir: t.TempDir()}
	m, err := e.StoreMaterial("../notes.txt", strings.NewReader("hello, material\n"))
	if err != nil {
		t.Fatal(err)
	}
	if m.Name != "notes.txt" || m.MIME != "text/plain" || m.Size != int64(len("hello, material\n")) || m.Excerpt != "hello, material" || m.ReadStatus != MaterialReadText {
		t.Fatalf("unexpected stored material: %#v", m)
	}
	found, err := e.FindMaterial(m.ID)
	if err != nil || found != m {
		t.Fatalf("FindMaterial = %#v, %v", found, err)
	}
	f, err := e.OpenMaterial(m.ID)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	got, err := io.ReadAll(f)
	if err != nil || string(got) != "hello, material\n" {
		t.Fatalf("original = %q, %v", got, err)
	}
}

func TestStoreMaterialRejectsOversizeAndInvalidIDs(t *testing.T) {
	e := &Engine{dir: t.TempDir()}
	if _, err := e.StoreMaterial("x.bin", bytes.NewReader(make([]byte, MaxMaterialBytes+1))); err == nil {
		t.Fatal("oversize material accepted")
	}
	for _, id := range []string{"../" + strings.Repeat("a", 29), strings.Repeat("z", 32), strings.Repeat("a", 31)} {
		if _, err := e.FindMaterial(id); err == nil {
			t.Fatalf("invalid id %q accepted", id)
		}
		if _, err := e.OpenMaterial(id); err == nil {
			t.Fatalf("invalid id %q opened", id)
		}
	}
}

func TestStoreMaterialBoundsExcerptAndDetectsBinary(t *testing.T) {
	e := &Engine{dir: t.TempDir()}
	long := strings.Repeat("界", maxMaterialExcerptRunes+10)
	m, err := e.StoreMaterial("long.txt", strings.NewReader(long))
	if err != nil {
		t.Fatal(err)
	}
	if len([]rune(m.Excerpt)) != maxMaterialExcerptRunes {
		t.Fatalf("excerpt rune count = %d", len([]rune(m.Excerpt)))
	}
	b, err := e.StoreMaterial("opaque.bin", bytes.NewReader([]byte{0, 1, 2}))
	if err != nil {
		t.Fatal(err)
	}
	if b.MIME != "application/octet-stream" || b.Excerpt != "" || b.ReadStatus != MaterialReadOriginal {
		t.Fatalf("unexpected binary metadata: %#v", b)
	}
}

func TestStoreMaterialDOCXPDFWhitespaceAndUnknown(t *testing.T) {
	e := &Engine{dir: t.TempDir()}
	var data bytes.Buffer
	zw := zip.NewWriter(&data)
	w, err := zw.Create("word/document.xml")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := w.Write([]byte(`<w:document xmlns:w="urn:w"><w:body><w:p><w:r><w:t>DOCX note</w:t></w:r></w:p></w:body></w:document>`)); err != nil {
		t.Fatal(err)
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	doc, err := e.StoreMaterial("report.docx", bytes.NewReader(data.Bytes()))
	if err != nil {
		t.Fatal(err)
	}
	if doc.MIME != "application/vnd.openxmlformats-officedocument.wordprocessingml.document" || !strings.Contains(doc.Excerpt, "DOCX note") || doc.ReadStatus != MaterialReadText {
		t.Fatalf("DOCX was not extracted: %#v", doc)
	}

	pdf, err := e.StoreMaterial("scan.pdf", bytes.NewReader([]byte("%PDF-1.4\n%%EOF")))
	if err != nil {
		t.Fatal(err)
	}
	if pdf.MIME != "application/pdf" || pdf.ReadStatus == MaterialReadOriginal {
		t.Fatalf("PDF sniff/extraction status incorrect: %#v", pdf)
	}

	empty, err := e.StoreMaterial("empty.txt", strings.NewReader("  \n\t"))
	if err != nil {
		t.Fatal(err)
	}
	if empty.ReadStatus == MaterialReadText || empty.Excerpt != "" {
		t.Fatalf("whitespace-only text marked readable: %#v", empty)
	}

	unknown, err := e.StoreMaterial("blob.dat", bytes.NewReader([]byte{0x00, 0xfe, 0x81}))
	if err != nil {
		t.Fatal(err)
	}
	if unknown.ReadStatus != MaterialReadOriginal || unknown.Excerpt != "" {
		t.Fatalf("unknown data status incorrect: %#v", unknown)
	}
}
