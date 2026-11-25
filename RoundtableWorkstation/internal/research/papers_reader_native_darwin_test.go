//go:build darwin && cgo

package research

import (
	"bytes"
	"encoding/json"
	"fmt"
	"image/png"
	"mime/multipart"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// PDF numbered objects and xref positions are generated here so both rotation
// and a non-zero crop origin are known independently of PDFKit.
func readerFixture(t *testing.T) string {
	t.Helper()
	stream := "BT /F1 24 Tf 55 148 Td (Evidence sample) Tj ET\n"
	page := "/Type /Page /Parent 2 0 R /MediaBox [0 0 300 260] /CropBox [20 30 270 220] /Resources << /Font << /F1 5 0 R >> >> /Contents 6 0 R"
	objects := []string{
		"<< /Type /Catalog /Pages 2 0 R >>",
		"<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>",
		"<< " + page + " >>",
		"<< " + page + " /Rotate 90 >>",
		"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
		fmt.Sprintf("<< /Length %d >>\nstream\n%sendstream", len(stream), stream),
	}
	var pdf strings.Builder
	pdf.WriteString("%PDF-1.5\n")
	offsets := []int{0}
	for i, o := range objects {
		offsets = append(offsets, pdf.Len())
		fmt.Fprintf(&pdf, "%d 0 obj\n%s\nendobj\n", i+1, o)
	}
	start := pdf.Len()
	fmt.Fprintf(&pdf, "xref\n0 %d\n0000000000 65535 f \n", len(offsets))
	for _, pos := range offsets[1:] {
		fmt.Fprintf(&pdf, "%010d 00000 n \n", pos)
	}
	fmt.Fprintf(&pdf, "trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n", len(offsets), start)
	file := filepath.Join(t.TempDir(), "cropped-rotated.pdf")
	if err := os.WriteFile(file, []byte(pdf.String()), 0600); err != nil {
		t.Fatal(err)
	}
	return file
}

func TestReaderCropRotateSearchAndRasterAlignment(t *testing.T) {
	file := readerFixture(t)
	info, err := nativePDFPage(file, "info", 0, "")
	if err != nil || !bytes.Contains(info, []byte(`"pages":2`)) {
		t.Fatalf("info %q %v", info, err)
	}
	for page := 1; page <= 2; page++ {
		result, err := nativePDFPage(file, "page", page, "")
		if err != nil {
			t.Fatal(err)
		}
		var d struct {
			Width, Height float64
			Text          string
			Words         []struct {
				Text string
				Box  struct{ X, Y, Width, Height float64 }
			}
		}
		if err := json.Unmarshal(result, &d); err != nil {
			t.Fatal(err)
		}
		if !strings.Contains(d.Text, "Evidence") || len(d.Words) != 2 {
			t.Fatalf("unexpected text %s", result)
		}
		if page == 1 && (d.Width != 250 || d.Height != 190) || page == 2 && (d.Width != 190 || d.Height != 250) {
			t.Fatalf("wrong rotated size %+v", d)
		}
		rendered, err := nativePDFPage(file, "image", page, "")
		if err != nil {
			t.Fatal(err)
		}
		image, err := png.Decode(bytes.NewReader(rendered))
		if err != nil {
			t.Fatal(err)
		}
		for _, word := range d.Words {
			b := word.Box
			x := float64(image.Bounds().Dx())
			y := float64(image.Bounds().Dy())
			if b.X < 0 || b.Y < 0 || b.X+b.Width > 1.0001 || b.Y+b.Height > 1.0001 {
				t.Fatalf("out of page: %+v", b)
			}
			ink := 0
			for py := int(b.Y * y); py < int((b.Y+b.Height)*y); py++ {
				for px := int(b.X * x); px < int((b.X+b.Width)*x); px++ {
					r, _, _, _ := image.At(px, py).RGBA()
					if r < 12000 {
						ink++
					}
				}
			}
			if ink < 100 {
				minX, minY, maxX, maxY := image.Bounds().Dx(), image.Bounds().Dy(), 0, 0
				for yy := 0; yy < image.Bounds().Dy(); yy += 3 {
					for xx := 0; xx < image.Bounds().Dx(); xx += 3 {
						r, _, _, _ := image.At(xx, yy).RGBA()
						if r < 12000 {
							minX = min(minX, xx)
							minY = min(minY, yy)
							maxX = max(maxX, xx)
							maxY = max(maxY, yy)
						}
					}
				}
				t.Logf("image %v detected ink at %d %d %d %d", image.Bounds(), minX, minY, maxX, maxY)
				t.Fatalf("word %q page %d missing text at displayed position %+v; ink %d", word.Text, page, b, ink)
			}
		}
	}
	b, err := nativePDFPage(file, "search", 0, "evidence")
	if err != nil {
		t.Fatal(err)
	}
	var matches struct {
		Items []struct{ Page, Start, End int }
	}
	if err := json.Unmarshal(b, &matches); err != nil || len(matches.Items) != 2 || matches.Items[1].Page != 2 || matches.Items[0].End-matches.Items[0].Start != 8 {
		t.Fatalf("search %q %v", b, err)
	}
	if _, err := nativePDFPage(file, "page", 3, ""); err == nil {
		t.Fatal("accepted missing page")
	}
}

func TestReaderRoutesReopenAndLocateEvidence(t *testing.T) {
	directory := t.TempDir()
	library, err := NewPaperLibrary(directory)
	if err != nil {
		t.Fatal(err)
	}
	var upload bytes.Buffer
	form := multipart.NewWriter(&upload)
	part, err := form.CreateFormFile("file", "Evidence.pdf")
	if err != nil {
		t.Fatal(err)
	}
	pdf, err := os.ReadFile(readerFixture(t))
	if err != nil {
		t.Fatal(err)
	}
	if _, err = part.Write(pdf); err != nil {
		t.Fatal(err)
	}
	if err = form.Close(); err != nil {
		t.Fatal(err)
	}
	req := httptest.NewRequest("POST", "/api/research/papers", &upload)
	req.Header.Set("Content-Type", form.FormDataContentType())
	out := httptest.NewRecorder()
	library.ServeHTTP(out, req)
	if out.Code != 201 {
		t.Fatalf("import: %d %s", out.Code, out.Body.String())
	}
	var record Paper
	if err = json.Unmarshal(out.Body.Bytes(), &record); err != nil {
		t.Fatal(err)
	}
	base := "/api/research/papers/" + record.ID
	call := func(method, path, body string) *httptest.ResponseRecorder {
		r := httptest.NewRequest(method, base+path, strings.NewReader(body))
		w := httptest.NewRecorder()
		library.ServeHTTP(w, r)
		return w
	}
	out = call("GET", "/pages/2", "")
	if out.Code != 200 || !strings.Contains(out.Body.String(), "Evidence") {
		t.Fatalf("page: %d %s", out.Code, out.Body.String())
	}
	out = call("GET", "/pages/2/image", "")
	if out.Code != 200 || out.Header().Get("Content-Type") != "image/png" {
		t.Fatalf("raster: %d", out.Code)
	}
	out = call("GET", "/pages/search?q=Evidence", "")
	if out.Code != 200 || !strings.Contains(out.Body.String(), `"page":2`) {
		t.Fatalf("search: %d", out.Code)
	}
	out = call("POST", "/annotations", `{"page":2,"kind":"highlight","selected_text":"Evidence","note":"evaluate","rects":[{"x":0.1,"y":0.2,"width":0.2,"height":0.1}]}`)
	if out.Code != 201 {
		t.Fatalf("save annotation: %d %s", out.Code, out.Body.String())
	}
	p, _ := library.Snapshot(record.ID)
	out = call("PUT", "", fmt.Sprintf(`{"revision":%d,"notes":"study the assumptions"}`, p.Revision))
	if out.Code != 200 {
		t.Fatalf("save notes: %d %s", out.Code, out.Body.String())
	}
	out = call("PUT", "", fmt.Sprintf(`{"revision":%d,"notes":"stale tabs"}`, p.Revision))
	if out.Code != 409 {
		t.Fatalf("overwrote concurrent note: %d", out.Code)
	}
	library, err = NewPaperLibrary(directory)
	if err != nil {
		t.Fatal(err)
	}
	p, _ = library.Snapshot(record.ID)
	if len(p.Annotations) != 1 || p.Annotations[0].Page != 2 || p.Notes != "study the assumptions" || p.FileSHA256 != record.FileSHA256 {
		t.Fatalf("reopened values: %+v", p)
	}
	out = call("GET", "/pdf", "")
	if out.Code != 200 || !bytes.Equal(out.Body.Bytes(), pdf) {
		t.Fatal("annotating changed the source PDF")
	}
}
