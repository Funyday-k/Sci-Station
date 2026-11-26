//go:build darwin && cgo

package research

import (
	"bytes"
	"context"
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
	out = call("POST", "/annotations", `{"page":2,"kind":"highlight","selected_text":"Evidence","selectionStart":0,"selectionEnd":8,"note":"evaluate","rects":[{"x":0.1,"y":0.2,"width":0.2,"height":0.1}]}`)
	if out.Code != 201 {
		t.Fatalf("save annotation: %d %s", out.Code, out.Body.String())
	}
	p, _ := library.Snapshot(record.ID)
	position := fmt.Sprintf(`{"sourceHash":%q,"page":2,"zoom":1.4,"scroll":0.42}`, record.FileSHA256)
	if out = call("POST", "/reading-position", position); out.Code != 204 {
		t.Fatalf("save reading position: %d %s", out.Code, out.Body.String())
	}
	withPosition, _ := library.Snapshot(record.ID)
	if withPosition.Revision != p.Revision || withPosition.UpdatedAt != p.UpdatedAt {
		t.Fatal("reading position changed the content revision or updated timestamp")
	}
	if out = call("POST", "/reading-position", strings.Replace(position, record.FileSHA256, "other", 1)); out.Code != 409 {
		t.Fatalf("stale reading source was accepted: %d", out.Code)
	}
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
	if len(p.Annotations) != 1 || p.Annotations[0].Page != 2 || p.Notes != "study the assumptions" || p.FileSHA256 != record.FileSHA256 ||
		p.ReadingPosition == nil || p.ReadingPosition.Page != 2 || p.ReadingPosition.Zoom != 1.4 || p.ReadingPosition.Scroll != 0.42 {
		t.Fatalf("reopened values: %+v", p)
	}
	ann := p.Annotations[0]
	evidence := Evidence{
		PaperID: p.ID, Page: ann.Page, Quote: ann.SelectedText, SourceHash: p.FileSHA256,
		AnnotationID: ann.ID, SelectionStart: ann.SelectionStart, SelectionEnd: ann.SelectionEnd,
	}
	if ann.SelectionStart == nil || ann.SelectionEnd == nil {
		t.Fatalf("source range not restored: %+v", ann)
	}
	if err := library.VerifyPDFEvidence(context.Background(), evidence); err != nil {
		t.Fatalf("verify reopened source: %v", err)
	}
	encoded, err := json.Marshal(evidence)
	if err != nil {
		t.Fatal(err)
	}
	if out = call("POST", "/verify-evidence", string(encoded)); out.Code != 204 {
		t.Fatalf("verify endpoint: %d %s", out.Code, out.Body.String())
	}
	wrongOffset := 1
	evidence.SelectionStart = &wrongOffset
	if err := library.VerifyPDFEvidence(context.Background(), evidence); err == nil {
		t.Fatal("accepted correct quote with wrong offset")
	}
	evidence.SelectionStart, evidence.SelectionEnd = nil, nil
	if err := library.VerifyPDFEvidence(context.Background(), evidence); err != nil {
		t.Fatalf("verify legacy quote-only evidence: %v", err)
	}
	out = call("GET", "/pdf", "")
	if out.Code != 200 || !bytes.Equal(out.Body.Bytes(), pdf) {
		t.Fatal("annotating changed the source PDF")
	}
	path := filepath.Join(directory, "pdf", record.ID+".pdf")
	if err := os.WriteFile(path, append(pdf, '\n'), 0600); err != nil {
		t.Fatal(err)
	}
	if err := library.VerifyPDFEvidence(context.Background(), evidence); err == nil || !strings.Contains(err.Error(), "PDF 指纹不同") {
		t.Fatalf("edited file with same extract must fail at digest check: %v", err)
	}
}
