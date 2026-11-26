package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"scistation.local/desktop/internal/research"
)

func TestLibraryBibtexUsesNativePickerAndFilteredSnapshot(t *testing.T) {
	lib, err := research.New(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	host := &apiServer{research: lib, desktop: true}
	handler := host.serve(9881)
	request := func(method, path, body, userAgent string, code int) *httptest.ResponseRecorder {
		t.Helper()
		r := httptest.NewRequest(method, "http://127.0.0.1:9881/api/research/papers"+path, strings.NewReader(body))
		r.Header.Set("Content-Type", "application/json")
		r.Header.Set("X-Roundtable", "1")
		r.Header.Set("User-Agent", userAgent)
		w := httptest.NewRecorder()
		handler.ServeHTTP(w, r)
		if w.Code != code {
			t.Fatal(w.Code, w.Body.String())
		}
		return w
	}
	first := request(http.MethodPost, "", `{"title":"Solar Capture","tags":["test tag"]}`, "", http.StatusCreated)
	var paper research.Paper
	if err = json.Unmarshal(first.Body.Bytes(), &paper); err != nil {
		t.Fatal(err)
	}
	request(http.MethodPost, "", `{"title":"Other Paper"}`, "", http.StatusCreated)
	output := filepath.Join(t.TempDir(), "references.bib")
	if err = os.WriteFile(output, []byte("old export"), 0600); err != nil {
		t.Fatal(err)
	}
	selection := output
	calls := 0
	host.setSavePicker(func(name, ext string) (string, error) {
		calls++
		if name != "references.bib" || ext != "bib" {
			t.Fatalf("unexpected save suggestion %q (%q)", name, ext)
		}
		return selection, nil
	})
	query := "?tag=test+tag&paper=" + paper.ID
	export := request(http.MethodGet, "/bibtex"+query, "", "", http.StatusOK)
	if !strings.Contains(export.Body.String(), paper.Citekey) || strings.Contains(export.Body.String(), "Other Paper") {
		t.Fatal(export.Body.String())
	}
	fallback := request(http.MethodPost, "/bibtex/save"+query, "{}", "", http.StatusOK)
	if !strings.Contains(fallback.Body.String(), "browser_download") || calls != 0 {
		t.Fatal(fallback.Body.String(), calls)
	}
	request(http.MethodPost, "/bibtex/save"+query, `{"path":"outside.bib"}`, desktopUserAgent, http.StatusBadRequest)
	request(http.MethodPost, "/bibtex/save?tag=missing", "{}", desktopUserAgent, http.StatusNotFound)
	if calls != 0 {
		t.Fatal("invalid request opened a save panel")
	}
	selection = ""
	cancel := request(http.MethodPost, "/bibtex/save"+query, "{}", desktopUserAgent, http.StatusOK)
	previous, err := os.ReadFile(output)
	if err != nil || string(previous) != "old export" || !strings.Contains(cancel.Body.String(), `"saved":false`) {
		t.Fatal(cancel.Body.String(), string(previous), err)
	}
	selection = output
	saved := request(http.MethodPost, "/bibtex/save"+query, "{}", desktopUserAgent, http.StatusOK)
	actual, err := os.ReadFile(output)
	if err != nil || string(actual) != export.Body.String() || !strings.Contains(saved.Body.String(), `"saved":true`) {
		t.Fatal(saved.Body.String(), string(actual), err)
	}
}

func TestNativeLibraryPDFPathRejectsSymlinks(t *testing.T) {
	root, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	file := filepath.Join(root, "original.pdf")
	if err = os.WriteFile(file, []byte("fixture"), 0600); err != nil {
		t.Fatal(err)
	}
	if err = regularLibraryPDF(file); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(root, "link.pdf")
	if err = os.Symlink(file, link); err != nil {
		t.Fatal(err)
	}
	if err = regularLibraryPDF(link); err == nil {
		t.Fatal("symlink accepted as a native PDF resource")
	}
}
