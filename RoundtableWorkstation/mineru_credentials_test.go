package main

import (
	"archive/zip"
	"bytes"
	"errors"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"scistation.local/desktop/internal/research"
)

const minerFixture = "fixture-mineru-credential"

type mockMinerKeychain struct {
	value    string
	err      error
	resolved int
}

func (s *mockMinerKeychain) Configured() (bool, error) { return s.value != "", s.err }

func (s *mockMinerKeychain) Resolve() (string, error) {
	s.resolved++
	return s.value, s.err
}

func (s *mockMinerKeychain) Save(value string) error {
	if s.err == nil {
		s.value = value
	}
	return s.err
}

func (s *mockMinerKeychain) Delete() error { return s.Save("") }

func minerRequest(t *testing.T, handler http.Handler, method, route, proof, body string, want int) []byte {
	t.Helper()
	r := httptest.NewRequest(method, "http://127.0.0.1:18765/api/research/tools/mineru/"+route, strings.NewReader(body))
	r.Header.Set("Content-Type", "application/json")
	r.Header.Set("X-Roundtable", "1")
	r.Header.Set("User-Agent", desktopUserAgent)
	r.Header.Set(minerCredentialHeader, proof)
	w := httptest.NewRecorder()
	handler.ServeHTTP(w, r)
	if strings.Contains(w.Body.String(), minerFixture) || (proof != "" && strings.Contains(w.Body.String(), proof)) {
		t.Fatal("response exposed credential material")
	}
	if w.Code != want {
		t.Fatalf("%s %s: got %d, want %d: %s", method, route, w.Code, want, w.Body.String())
	}
	if w.Header().Get("Cache-Control") != "no-store" {
		t.Fatal("credential response must not be cached")
	}
	return w.Body.Bytes()
}

func TestMinerUKeychainLifecycleAndFailure(t *testing.T) {
	dir := t.TempDir()
	lab, err := research.New(filepath.Join(dir, "research"))
	if err != nil {
		t.Fatal(err)
	}
	settingsPath := filepath.Join(dir, "settings.json")
	baseline := []byte(`{"magpie_port":3425,"unknown_field":{"preserve":true}}`)
	if err = os.WriteFile(settingsPath, baseline, 0600); err != nil {
		t.Fatal(err)
	}
	store := &mockMinerKeychain{}
	first := &apiServer{research: lab, desktop: true, minerCreds: newMinerCredentials(store)}
	proof := first.minerCreds.proof
	request := first.serve(18765)
	configured := func(handler http.Handler, proof string, want bool) {
		t.Helper()
		b := minerRequest(t, handler, http.MethodGet, "credential", proof, "", http.StatusOK)
		status := scienceWorkflowDecode[map[string]bool](t, b)
		if len(status) != 1 || status["configured"] != want {
			t.Fatalf("unexpected Keychain status: %s", b)
		}
	}

	minerRequest(t, request, http.MethodGet, "credential", "", "", http.StatusForbidden)
	minerRequest(t, request, http.MethodPost, "credential", "", `{"action":"save","token":"fixture"}`, http.StatusForbidden)
	configured(request, proof, false)
	minerRequest(t, request, http.MethodPost, "credential", proof, `{"action":"save","token":" "}`, http.StatusBadRequest)
	minerRequest(t, request, http.MethodPost, "credential", proof, `{"action":"save","token":"abc\ndef"}`, http.StatusBadRequest)
	minerRequest(t, request, http.MethodPost, "credential", proof, fmt.Sprintf(`{"action":"save","token":"  %s  "}`, minerFixture), http.StatusOK)
	configured(request, proof, true)
	if store.resolved != 0 || store.value != minerFixture {
		t.Fatal("save should trim the value and status must not resolve it")
	}

	// A fresh API and new desktop session use the same isolated Keychain store.
	reopened := &apiServer{research: lab, desktop: true, minerCreds: newMinerCredentials(store)}
	request = reopened.serve(18765)
	minerRequest(t, request, http.MethodGet, "credential", proof, "", http.StatusForbidden)
	proof = reopened.minerCreds.proof
	configured(request, proof, true)
	store.err = errors.New("denied " + minerFixture)
	minerRequest(t, request, http.MethodGet, "credential", proof, "", http.StatusServiceUnavailable)
	minerRequest(t, request, http.MethodPost, "credential", proof, `{"action":"save","token":"fixture-replacement"}`, http.StatusServiceUnavailable)
	minerRequest(t, request, http.MethodPost, "credential", proof, `{"action":"clear"}`, http.StatusServiceUnavailable)
	if store.value != minerFixture {
		t.Fatal("failure changed the saved credential")
	}
	store.err = nil
	minerRequest(t, request, http.MethodPost, "credential", proof, `{"action":"save","token":"fixture-replacement"}`, http.StatusOK)
	if store.value != "fixture-replacement" {
		t.Fatal("valid replacement did not reach Keychain")
	}
	for range 2 {
		minerRequest(t, request, http.MethodPost, "credential", proof, `{"action":"clear"}`, http.StatusOK)
	}
	configured(request, proof, false)
	if actual, err := os.ReadFile(settingsPath); err != nil || !bytes.Equal(actual, baseline) {
		t.Fatal("credential management modified unrelated settings")
	}
}

func TestMinerUUsesSavedTokenOnlyInDesktopSession(t *testing.T) {
	lab, err := research.New(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	store := &mockMinerKeychain{value: minerFixture}
	host := &apiServer{research: lab, desktop: true, minerCreds: newMinerCredentials(store)}
	handler := host.serve(18765)
	proof := host.minerCreds.proof

	var upload bytes.Buffer
	form := multipart.NewWriter(&upload)
	file, err := form.CreateFormFile("file", "fixture.pdf")
	if err != nil {
		t.Fatal(err)
	}
	pdf := scienceWorkflowPDF("Local conversion fixture")
	if _, err = file.Write(pdf); err != nil {
		t.Fatal(err)
	}
	if err = form.Close(); err != nil {
		t.Fatal(err)
	}
	r := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:18765/api/research/papers", &upload)
	r.Header.Set("Content-Type", form.FormDataContentType())
	r.Header.Set("X-Roundtable", "1")
	w := httptest.NewRecorder()
	handler.ServeHTTP(w, r)
	if w.Code != http.StatusCreated {
		t.Fatalf("fixture import: %d %s", w.Code, w.Body)
	}
	paper := scienceWorkflowDecode[research.Paper](t, w.Body.Bytes()).ID
	start := fmt.Sprintf(`{"paper":%q}`, paper)
	batch := fmt.Sprintf(`{"paper":%q,"batch":"fixture-batch"}`, paper)
	transient := fmt.Sprintf(`{"paper":%q,"batch":"fixture-batch","token":"fixture-transient"}`, paper)
	var archive bytes.Buffer
	zipped := zip.NewWriter(&archive)
	md, err := zipped.Create("full.md")
	if err != nil {
		t.Fatal(err)
	}
	if _, err = io.WriteString(md, "# Offline fixture"); err != nil {
		t.Fatal(err)
	}
	if err = zipped.Close(); err != nil {
		t.Fatal(err)
	}

	orig := scientificHTTP
	t.Cleanup(func() { scientificHTTP = orig })
	wantToken := minerFixture
	state := "done"
	var remoteCalls int
	scientificHTTP = &http.Client{Transport: conversionTransport(func(r *http.Request) (*http.Response, error) {
		remoteCalls++
		if r.Header.Get(minerCredentialHeader) != "" {
			t.Fatal("desktop proof reached external service")
		}
		respond := func(status int, body io.Reader) (*http.Response, error) {
			return &http.Response{StatusCode: status, Header: http.Header{}, Body: io.NopCloser(body)}, nil
		}
		switch r.URL.Host {
		case "mineru.net":
			if r.Header.Get("Authorization") != "Bearer "+wantToken {
				t.Fatal("incorrect token on MinerU request")
			}
			if r.Method == http.MethodPost && r.URL.Path == "/api/v4/file-urls/batch" {
				return respond(200, strings.NewReader(`{"data":{"batch_id":"fixture-batch","file_urls":["https://cdn.mineru.net/upload"]}}`))
			}
			if r.Method == http.MethodGet && r.URL.Path == "/api/v4/extract-results/batch/fixture-batch" {
				return respond(200, strings.NewReader(fmt.Sprintf(`{"data":{"extract_result":[{"data_id":%q,"state":%q,"err_msg":%q,"full_zip_url":"https://cdn.mineru.net/result"}]}}`, paper, state, minerFixture)))
			}
		case "cdn.mineru.net":
			if r.Header.Get("Authorization") != "" {
				t.Fatal("credential reached the CDN")
			}
			if r.Method == http.MethodPut && r.URL.Path == "/upload" {
				read, err := io.ReadAll(r.Body)
				if err != nil || !bytes.Equal(read, pdf) {
					t.Fatal("PDF upload does not match source")
				}
				return respond(200, strings.NewReader(""))
			}
			if r.Method == http.MethodGet && r.URL.Path == "/result" {
				return respond(200, bytes.NewReader(archive.Bytes()))
			}
		}
		t.Fatal("unexpected outbound request")
		return nil, errors.New("unexpected outbound request")
	})}

	minerRequest(t, handler, http.MethodPost, "start", "", start, http.StatusBadRequest)
	minerRequest(t, handler, http.MethodPost, "status", proof, start, http.StatusBadRequest)
	if remoteCalls != 0 || store.resolved != 0 {
		t.Fatal("invalid requests must not read Keychain or contact MinerU")
	}
	minerRequest(t, handler, http.MethodPost, "start", proof, start, http.StatusCreated)
	minerRequest(t, handler, http.MethodPost, "status", proof, batch, http.StatusOK)
	result := minerRequest(t, handler, http.MethodPost, "result", proof, batch, http.StatusOK)
	if !bytes.Contains(result, []byte("# Offline fixture")) {
		t.Fatal("missing conversion result")
	}
	state = "failed"
	minerRequest(t, handler, http.MethodPost, "status", proof, batch, http.StatusUnprocessableEntity)
	state = "done"
	if store.resolved != 4 {
		t.Fatal("expected one Keychain read per authorized conversion request")
	}

	wantToken = "fixture-transient"
	minerRequest(t, handler, http.MethodPost, "status", proof, transient, http.StatusOK)
	headless := (&apiServer{research: lab, minerCreds: host.minerCreds}).serve(18765)
	minerRequest(t, headless, http.MethodGet, "credential", proof, "", http.StatusForbidden)
	minerRequest(t, headless, http.MethodPost, "status", proof, batch, http.StatusBadRequest)
	minerRequest(t, headless, http.MethodPost, "status", "", transient, http.StatusOK)
	if store.resolved != 4 {
		t.Fatal("transient and headless requests must not resolve stored credentials")
	}

	used := remoteCalls
	store.err = errors.New("credentials are locked")
	minerRequest(t, handler, http.MethodPost, "status", proof, batch, http.StatusServiceUnavailable)
	if remoteCalls != used {
		t.Fatal("must not contact MinerU after Keychain fails")
	}
}
