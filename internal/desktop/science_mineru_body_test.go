package desktop

import (
	"archive/zip"
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"image"
	"image/color"
	"image/png"
	"io"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"scistation.local/desktop/internal/research"
)

func TestMinerUAdoptsOnlyPreviewedBodyBoundToUploadedPDF(t *testing.T) {
	lab, err := research.New(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	pdf := scienceWorkflowPDF("Actual uploaded body")
	var upload bytes.Buffer
	form := multipart.NewWriter(&upload)
	part, err := form.CreateFormFile("file", "fixture.pdf")
	if err != nil {
		t.Fatal(err)
	}
	if _, err = part.Write(pdf); err != nil {
		t.Fatal(err)
	}
	if err = form.Close(); err != nil {
		t.Fatal(err)
	}
	r := httptest.NewRequest("POST", "/api/research/papers", &upload)
	r.Header.Set("Content-Type", form.FormDataContentType())
	w := httptest.NewRecorder()
	lab.ServeHTTP(w, r)
	if w.Code != 201 {
		t.Fatalf("upload %d %s", w.Code, w.Body.String())
	}
	p := scienceWorkflowDecode[research.Paper](t, w.Body.Bytes())
	const raw = "# Converted\r\nThe detector counts independent events.\r\n\r\n![Detector](images/detector.png)"
	archive := func(shade uint8) []byte {
		var zipData bytes.Buffer
		z := zip.NewWriter(&zipData)
		entry, err := z.Create("provider/full.md")
		if err != nil {
			t.Fatal(err)
		}
		if _, err = io.WriteString(entry, raw); err != nil {
			t.Fatal(err)
		}
		entry, err = z.Create("provider/images/detector.png")
		if err != nil {
			t.Fatal(err)
		}
		raster := image.NewGray(image.Rect(0, 0, 2, 2))
		raster.SetGray(0, 0, color.Gray{Y: shade})
		if err = png.Encode(entry, raster); err != nil {
			t.Fatal(err)
		}
		if err = z.Close(); err != nil {
			t.Fatal(err)
		}
		return zipData.Bytes()
	}
	zipData := archive(50)
	var dataID string
	previous := scientificHTTP
	defer func() { scientificHTTP = previous }()
	scientificHTTP = &http.Client{Transport: conversionTransport(func(req *http.Request) (*http.Response, error) {
		var reply []byte
		switch req.URL.Path {
		case "/api/v4/file-urls/batch":
			var v struct {
				Files []struct {
					ID string `json:"data_id"`
				}
			}
			if err := json.NewDecoder(req.Body).Decode(&v); err != nil || len(v.Files) != 1 {
				t.Fatal(v, err)
			}
			dataID = v.Files[0].ID
			reply = []byte(`{"code":0,"data":{"batch_id":"batch","file_urls":["https://mineru.net/upload"]}}`)
		case "/upload":
			got, err := io.ReadAll(req.Body)
			if err != nil || !bytes.Equal(pdf, got) || req.Header.Get("Authorization") != "" {
				t.Fatal("invalid upload")
			}
			reply = []byte("{}")
		case "/api/v4/extract-results/batch/batch":
			reply = []byte(fmt.Sprintf(`{"code":0,"data":{"extract_result":[{"data_id":%q,"file_name":%q,"state":"done","full_zip_url":"https://mineru.net/result"}]}}`, dataID, p.ID+".pdf"))
		case "/result":
			if req.Header.Get("Authorization") != "" {
				t.Fatal("credential sent to result URL")
			}
			reply = zipData
		default:
			t.Fatalf("unexpected request %s", req.URL)
		}
		return &http.Response{StatusCode: 200, Header: make(http.Header), Body: io.NopCloser(bytes.NewReader(reply))}, nil
	})}
	api := apiServer{}
	in := map[string]any{"paper": p.ID, "token": "fixture-value", "batch": "batch"}
	run := func(route string, want int) []byte {
		body, err := json.Marshal(in)
		if err != nil {
			t.Fatal(err)
		}
		w := httptest.NewRecorder()
		api.mineruTool(lab, w, httptest.NewRequest("POST", "/", bytes.NewReader(body)), route)
		if w.Code != want {
			t.Fatalf("%s got %d want %d: %s", route, w.Code, want, w.Body.String())
		}
		return w.Body.Bytes()
	}
	run("mineru/start", 201)
	if dataID == p.ID || len(dataID) != 32 {
		t.Fatal("provider result not bound to the uploaded version")
	}
	preview := scienceWorkflowDecode[struct {
		Bound bool
		research.MinerMarkdown
	}](t, run("mineru/result", 200))
	if !preview.Bound || preview.Markdown != raw || preview.SHA256 != fmt.Sprintf("%x", sha256.Sum256([]byte(raw))) ||
		preview.AssetsHash == "" || len(preview.Quality.Figures) != 1 || preview.Quality.Figures[0].AssetID == "" {
		t.Fatal(preview)
	}
	in["saveSource"] = true
	in["revision"] = p.Revision
	in["expectedHash"] = strings.Repeat("0", 64)
	run("mineru/result", 409)
	in["expectedHash"] = preview.SHA256
	run("mineru/result", 409) // An image-bearing source requires the previewed asset hash.
	in["expectedAssetsHash"] = preview.AssetsHash
	zipData = archive(70)
	run("mineru/result", 409) // Same Markdown, different image.
	zipData = archive(50)
	bound := dataID
	dataID = p.ID
	run("mineru/result", 409)
	dataID = bound
	rec := scienceWorkflowDecode[research.Paper](t, run("mineru/result", 200))
	if rec.Markdown == nil || rec.Markdown.Origin != "mineru" || rec.Markdown.PDFHash != p.FileSHA256 || rec.Markdown.AssetsHash != preview.AssetsHash {
		t.Fatal(rec)
	}
	if _, _, err = lab.ConversionOriginal(context.Background(), p.ID); err != nil {
		t.Fatal(err)
	}
}
