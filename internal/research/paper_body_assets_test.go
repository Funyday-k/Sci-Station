package research

import (
	"archive/zip"
	"bytes"
	"context"
	"encoding/base64"
	"errors"
	"image"
	"image/color"
	"image/png"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"testing"
	"unicode/utf8"
)

type minerEntryFixture struct {
	name string
	data []byte
	mode os.FileMode
}

func minerArchiveFixture(t *testing.T, entries ...minerEntryFixture) []byte {
	t.Helper()
	buf := new(bytes.Buffer)
	z := zip.NewWriter(buf)
	for _, entry := range entries {
		header := &zip.FileHeader{Name: entry.name, Method: zip.Store}
		if entry.mode != 0 {
			header.SetMode(entry.mode)
		}
		f, err := z.CreateHeader(header)
		if err != nil {
			t.Fatal(err)
		}
		if _, err = f.Write(entry.data); err != nil {
			t.Fatal(err)
		}
	}
	if err := z.Close(); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

func minerPNGFixture(t *testing.T, shade uint8) []byte {
	t.Helper()
	picture := image.NewGray(image.Rect(0, 0, 3, 2))
	picture.SetGray(0, 0, color.Gray{Y: shade})
	buf := new(bytes.Buffer)
	if err := png.Encode(buf, picture); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

func TestMinerUArchivePreservesReferencesAndVerifiesLocalRasters(t *testing.T) {
	orig := "# Paper\r\n\r\n## 摘要\r\n正文 😀\r\n\r\n![Local](<./images/foo bar.png> \"optional title\")\r\n\r\n**Figure 1. Local caption 😀.**\r\n\r\n" +
		"Figure 2. Caption before the image.\r\n<img CLASS='center' ALT='HTML' src='../figures/second.webp'/>\r\n\r\n" +
		"![Outside](../../escape.png) ![Remote](https://example.invalid/a.png) ![Invalid](images/fake.png)\r\n" +
		"![Link](images/link.png) ![Missing](images/missing.png)\r\n\r\n\\[\r\nE = mc^2\r\n\\]\r\n\r\n" +
		"```markdown\r\n![Code sample](images/foo%20bar.png)\r\n```\r\n"
	pngBytes := minerPNGFixture(t, 120)
	webPBytes, err := base64.StdEncoding.DecodeString("UklGRh4AAABXRUJQVlA4TBEAAAAvAAAAAAfQ//73v/+BiOh/AAA=")
	if err != nil {
		t.Fatal(err)
	}
	data := minerArchiveFixture(t,
		minerEntryFixture{"paper/alternate.md", []byte("Not the full text."), 0},
		minerEntryFixture{"paper/full.md", []byte(orig), 0},
		minerEntryFixture{"paper/images/foo bar.png", pngBytes, 0},
		minerEntryFixture{"figures/second.webp", webPBytes, 0},
		minerEntryFixture{"paper/images/fake.png", []byte("<svg onload='unsafe'></svg>"), 0},
		minerEntryFixture{"paper/images/link.png", pngBytes, os.ModeSymlink | 0600},
		minerEntryFixture{"paper/../../escape.png", pngBytes, 0},
		minerEntryFixture{"escape.png", pngBytes, 0},
		minerEntryFixture{"paper/images/unreferenced.png", pngBytes, 0},
	)
	conversion, err := ReadMinerMarkdown(data)
	if err != nil {
		t.Fatal(err)
	}
	q := conversion.Quality
	if conversion.Markdown != orig || conversion.SHA256 != hashPaperBytes([]byte(orig)) || conversion.AssetsHash == "" ||
		len(conversion.assets.files) != 2 || q.Engine != "mineru" || !q.HasAbstract || !q.HasDisplayMath ||
		len(q.Figures) != 7 || q.MissingFigures != 5 {
		t.Fatalf("unexpected inspection: %+v", q)
	}
	normalized := []rune(normalizeWorkflowText(orig))
	for i, caption := range []string{"**Figure 1. Local caption 😀.**", "Figure 2. Caption before the image."} {
		figure := q.Figures[i]
		if len(figure.AssetID) != 64 || string(normalized[figure.CiteStart:figure.CiteEnd]) != caption {
			t.Fatalf("wrong figure locator: %+v", figure)
		}
	}
	first := q.Figures[0].AssetID
	second := q.Figures[1].AssetID
	if !bytes.Equal(conversion.assets.files[first], pngBytes) || conversion.assets.manifest[first].Type != "image/png" ||
		!bytes.Equal(conversion.assets.files[second], webPBytes) || conversion.assets.manifest[second].Type != "image/webp" {
		t.Fatal("figures changed or lost their media types")
	}
}

func TestMinerUArchiveRejectsAmbiguousCorruptAndOversizedResults(t *testing.T) {
	const raw = "Actual text.\n![A](images/a.png)"
	markdown := minerEntryFixture{"full.md", []byte(raw), 0}
	picture := minerEntryFixture{"images/a.png", minerPNGFixture(t, 120), 0}
	broken := minerArchiveFixture(t, markdown, picture)
	reader, err := zip.NewReader(bytes.NewReader(broken), int64(len(broken)))
	if err != nil {
		t.Fatal(err)
	}
	offset, err := reader.File[1].DataOffset()
	if err != nil {
		t.Fatal(err)
	}
	broken[offset+2] ^= 0xff
	for _, tc := range []struct {
		name string
		zip  []byte
	}{
		{"corrupt archive", []byte("not a zip")},
		{"corrupt referenced image", broken},
		{"duplicate image", minerArchiveFixture(t, markdown, picture, minerEntryFixture{"./images/a.png", picture.data, 0})},
		{"ambiguous main file", minerArchiveFixture(t, minerEntryFixture{"a/full.md", markdown.data, 0}, minerEntryFixture{"b/full.md", markdown.data, 0})},
		{"oversized image", minerArchiveFixture(t, markdown, minerEntryFixture{picture.name, make([]byte, maxFigureBytes+1), 0})},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if result, err := ReadMinerMarkdown(tc.zip); err == nil || result.Markdown != "" {
				t.Fatal("invalid conversion escaped archive validation")
			}
		})
	}
}

func TestPaperMarkdownFigurePreviewReplaysQuoteAndValidatesOfflineAssets(t *testing.T) {
	root := t.TempDir()
	s := newResearch(t, root)
	proj := createResearchProject(t, s, "Paper assets")
	data, err := os.ReadFile(readerFixture(t))
	if err != nil {
		t.Fatal(err)
	}
	p := uploadTestPDF(t, s.papers, string(data), `{"title":"Figure Paper","project_ids":["`+proj.ID+`"]}`)
	const raw = "# Important paper\r\n\r\n## Results\r\nWe compare three models.\r\n\r\n![](images/result.png)\r\n\r\nFigure 3. 😀 The plotted models differ.\r\n"
	markdown := minerEntryFixture{"full.md", []byte(raw), 0}
	image := minerPNGFixture(t, 17)
	picture := minerEntryFixture{"images/result.png", image, 0}
	conversion, err := ReadMinerMarkdown(minerArchiveFixture(t, markdown, picture))
	if err != nil {
		t.Fatal(err)
	}
	current, err := s.SaveMinerMarkdown(context.Background(), p.ID, p.Revision, p.FileSHA256, conversion)
	if err != nil {
		t.Fatal(err)
	}
	hash := current.Markdown.SourceHash()
	if current.Markdown.Hash != conversion.SHA256 || current.Markdown.AssetsHash != conversion.AssetsHash || hash == conversion.SHA256 {
		t.Fatalf("version must identify both text and images: %+v", current.Markdown)
	}
	// Reopen from disk to verify the serving path is independent of the MinerU session.
	s = newResearch(t, root)
	base := "/papers/" + p.ID + "/body"
	if got := callResearch(t, s, "GET", base, nil, 200); string(got) != raw {
		t.Fatal("archived source bytes have changed")
	}
	preview := decodeResearch[struct {
		Hash    string
		Quality BodyQuality
	}](t, callResearch(t, s, "GET", base+"/preview", nil, 200))
	if preview.Hash != hash || len(preview.Quality.Figures) != 1 || preview.Quality.Figures[0].AssetID == "" {
		t.Fatal(preview)
	}
	figure := preview.Quality.Figures[0]
	route := "/" + p.ID + "/body/figures/" + hash + "/" + figure.AssetID
	got := testPaperRequest(t, s.papers, "GET", route, "")
	if got.Code != 200 || !bytes.Equal(got.Body.Bytes(), image) || got.Header().Get("Content-Type") != "image/png" ||
		got.Header().Get("Cache-Control") != "no-store" || got.Header().Get("X-Content-Type-Options") != "nosniff" {
		t.Fatal("offline image is unavailable or different")
	}
	head := testPaperRequest(t, s.papers, "HEAD", route, "")
	if head.Code != 200 || head.Body.Len() != 0 || head.Header().Get("Content-Length") != strconv.Itoa(len(image)) {
		t.Fatal("HEAD did not describe the stored image")
	}
	callResearch(t, s, http.MethodPost, "/papers"+route, nil, 405)
	callResearch(t, s, "GET", strings.Replace("/papers"+route, hash, conversion.SHA256, 1), nil, 404)

	previewSource, err := s.WorkflowSourceAtLine(context.Background(), proj.ID, SourceLocation{Kind: "paper-markdown", ID: p.ID}, 8)
	const caption = "Figure 3. 😀 The plotted models differ."
	if err != nil || previewSource.Hash != hash || previewSource.Heading != "Results" || len(previewSource.Figures) != 1 ||
		!strings.HasPrefix(previewSource.Text, caption) {
		t.Fatalf("unexpected source preview: %+v, %v", previewSource, err)
	}
	location := ProjectEvidenceLocation{ProjectID: proj.ID, Kind: "paper-markdown", ID: p.ID, Offset: figure.CiteStart, End: figure.CiteEnd}
	sourceRoute := "/projects/" + proj.ID + "/source-excerpts/paper-markdown/" + p.ID + "?offset=" + strconv.Itoa(location.Offset) + "&end=" + strconv.Itoa(location.End) + "&fingerprint=" + hash
	excerpt := decodeResearch[ProjectSourceExcerpt](t, callResearch(t, s, "GET", sourceRoute, nil, 200))
	if excerpt.Quote != caption || len(excerpt.Figures) != 1 || excerpt.Figures[0].AssetID != figure.AssetID || excerpt.Line != 8 ||
		utf8.RuneCountInString(caption) != location.End-location.Offset {
		t.Fatalf("caption did not round-trip: %+v", excerpt)
	}

	assetPath := filepath.Join(s.papers.assetPath(p.ID, current.Markdown.BlobID), figure.AssetID)
	modified := bytes.Clone(image)
	modified[len(modified)-1] ^= 0xff
	if err := os.WriteFile(assetPath, modified, 0600); err != nil {
		t.Fatal(err)
	}
	callResearch(t, s, "GET", "/papers"+route, nil, 409)
	damaged := decodeResearch[struct{ Quality BodyQuality }](t, callResearch(t, s, "GET", base+"/preview", nil, 200))
	if damaged.Quality.MissingFigures != 1 || damaged.Quality.Figures[0].AssetID != "" {
		t.Fatal("damaged asset reported as available")
	}
	healed, err := s.SaveMinerMarkdown(context.Background(), p.ID, current.Revision, p.FileSHA256, conversion)
	if err != nil || healed.Revision <= current.Revision || healed.Markdown.SourceHash() != hash {
		t.Fatal("explicit retry did not restore the adopted asset", err)
	}
	callResearch(t, s, "GET", "/papers"+route, nil, 200)
	if _, err = os.Stat(assetPath); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("superseded blob survived successful publication", err)
	}
	rerun, err := s.SaveMinerMarkdown(context.Background(), p.ID, current.Revision, p.FileSHA256, conversion)
	if err != nil || rerun.Revision != healed.Revision {
		t.Fatal("healthy retry is not idempotent", err)
	}

	picture.data = minerPNGFixture(t, 32)
	changed, err := ReadMinerMarkdown(minerArchiveFixture(t, markdown, picture))
	if err != nil {
		t.Fatal(err)
	}
	otherOpen := newResearch(t, root)
	start := make(chan struct{})
	results := make(chan error, 2)
	var wg sync.WaitGroup
	for _, lib := range []*Service{s, otherOpen} {
		wg.Go(func() {
			<-start
			if lib == s {
				_, err := lib.SaveMinerMarkdown(context.Background(), p.ID, healed.Revision, p.FileSHA256, changed)
				results <- err
			} else {
				_, err := lib.papers.storeBody(p.ID, healed.Revision, []byte("Another writer's Markdown."), "import", "", paperAssets{})
				results <- err
			}
		})
	}
	close(start)
	wg.Wait()
	close(results)
	success, conflicted := 0, 0
	for err := range results {
		if err == nil {
			success++
		} else if errors.Is(err, errPaperConflict) {
			conflicted++
		} else {
			t.Fatal(err)
		}
	}
	if success != 1 || conflicted != 1 {
		t.Fatal("matched revisions must publish exactly one source")
	}
	reopened := newResearch(t, root)
	callResearch(t, reopened, "GET", "/papers"+route, nil, 404)
	callResearch(t, reopened, "GET", sourceRoute, nil, 409)
	files, err := os.ReadDir(filepath.Join(reopened.papers.dir, "markdown"))
	if err != nil {
		t.Fatal(err)
	}
	if len(files) < 1 || len(files) > 2 {
		t.Fatalf("failed or superseded versions left visible files: %v", files)
	}
	record, _ := reopened.papers.Snapshot(p.ID)
	callResearch(t, reopened, "DELETE", "/papers/"+p.ID+"?revision="+strconv.Itoa(record.Revision), nil, 204)
	files, err = os.ReadDir(filepath.Join(reopened.papers.dir, "markdown"))
	if err != nil || len(files) != 0 {
		t.Fatalf("paper deletion left files: %v %v", files, err)
	}
}

func TestPaperMarkdownQualityReportsOldPDFKitFallback(t *testing.T) {
	s := newResearch(t, t.TempDir())
	p, _, err := s.papers.create(PaperMetadata{Title: "Legacy import"}, "", "")
	if err != nil {
		t.Fatal(err)
	}
	const old = "---\nextraction_engine: pdfkit_fallback\nfallback_reason: No token\n---\n\n# Paper\n## 摘要\n真实正文\n" +
		"![](figures/missing.png)\n\n$$\nE=mc^2\n$$\n"
	uploadMarkdownFixture(t, s, p, old, 200)
	report := decodeResearch[struct {
		Markdown string
		Hash     string
		Quality  BodyQuality
	}](t, callResearch(t, s, "GET", "/papers/"+p.ID+"/body/preview", nil, 200))
	q := report.Quality
	if report.Hash != hashPaperBytes([]byte(old)) || report.Markdown != old || q.Engine != "pdfkit" || !q.HasAbstract || !q.HasDisplayMath ||
		len(q.Figures) != 1 || q.MissingFigures != 1 || q.Figures[0].AssetID != "" {
		t.Fatalf("legacy quality or body changed: %+v", report)
	}
}
