//go:build darwin && cgo

package research

import (
	"bytes"
	"io"
	"mime/multipart"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
)

func TestAttachLinkOnlyPDFAndExportText(t *testing.T) {
	lib := testPaperLib(t)
	paper, _, err := lib.create(PaperMetadata{Title: "Evidence Paper", URL: "https://example.org/article"}, "", "")
	if err != nil {
		t.Fatal(err)
	}
	source, err := os.ReadFile(readerFixture(t))
	if err != nil {
		t.Fatal(err)
	}
	var form bytes.Buffer
	writer := multipart.NewWriter(&form)
	file, err := writer.CreateFormFile("file", "local.pdf")
	if err != nil {
		t.Fatal(err)
	}
	if _, err = io.Copy(file, bytes.NewReader(source)); err != nil {
		t.Fatal(err)
	}
	if err = writer.Close(); err != nil {
		t.Fatal(err)
	}
	request := httptest.NewRequest("POST", "/api/research/papers/"+paper.ID+"/pdf", &form)
	request.Header.Set("Content-Type", writer.FormDataContentType())
	results := httptest.NewRecorder()
	lib.ServeHTTP(results, request)
	if results.Code != 200 {
		t.Fatalf("attach %d: %s", results.Code, results.Body)
	}
	again := testPaperRequest(t, lib, "POST", "/"+paper.ID+"/pdf", "{}")
	if again.Code != 409 {
		t.Fatal(again.Code)
	}
	result := testPaperRequest(t, lib, "GET", "/"+paper.ID+"/markdown", "")
	body := result.Body.String()
	if result.Code != 200 || !strings.Contains(result.Header().Get("Content-Type"), "text/markdown") || !strings.Contains(body, "# Evidence Paper") || !strings.Contains(body, "## 第 2 页") || strings.Count(body, "Evidence sample") != 2 {
		t.Fatalf("export %d: %s", result.Code, body)
	}
}
