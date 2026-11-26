package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func diagnosticFakeCLI(t *testing.T, name, body string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), name)
	if err := os.WriteFile(path, []byte("#!/bin/sh\nset -eu\n"+body+"\n"), 0700); err != nil {
		t.Fatal(err)
	}
	return path
}

func diagnosticFakePrograms(t *testing.T) (string, string) {
	t.Helper()
	codex := diagnosticFakeCLI(t, "codex", `
if /usr/bin/printenv OPENAI_API_KEY >/dev/null; then exit 9; fi
if /usr/bin/printenv CODEX_API_KEY >/dev/null; then exit 9; fi
if /usr/bin/printenv CURSOR_API_KEY >/dev/null; then exit 9; fi
case "$*" in
  '--version') printf 'codex-cli 0.170.0\n';;
  'login status') printf 'Logged in using ChatGPT\nalice@example.invalid SECRET_TOKEN\n' >&2;;
  *) printf 'NEVER_INFER SECRET_TOKEN' >&2; exit 99;;
esac
`)
	cursor := diagnosticFakeCLI(t, "agent", `
if /usr/bin/printenv OPENAI_API_KEY >/dev/null; then exit 9; fi
if /usr/bin/printenv CURSOR_AUTH_TOKEN >/dev/null; then exit 9; fi
case "$*" in
  '--version') printf '2026.11.11-043ef28\n';;
  'status --format json') printf '%s' '{"status":"authenticated","isAuthenticated":true,"hasAccessToken":true,"hasRefreshToken":true,"userInfo":{"email":"alice@example.invalid"},"private":"SECRET_TOKEN"}';;
  *) printf 'NEVER_INFER SECRET_TOKEN' >&2; exit 99;;
esac
`)
	return codex, cursor
}

func diagnosticFakeGateway(t *testing.T) (int, *atomic.Int32) {
	t.Helper()
	count := &atomic.Int32{}
	s := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		count.Add(1)
		if r.Method != "GET" {
			t.Errorf("diagnostic sent non-GET request %s", r.Method)
		}
		if r.Header.Get("Authorization") != "Bearer magpie-sci-station" || r.Header.Get("User-Agent") != "SciStation/2" {
			t.Error("unexpected local attribution")
		}
		w.Header().Set("Content-Type", "application/json")
		switch r.URL.Path {
		case "/api/hello":
			fmt.Fprint(w, `{"name":"magpie","version":"0.1.4572"}`)
		case "/v1/models":
			fmt.Fprint(w, `{"data":[{"id":"codex/gpt-6.2-sol"},{"id":"codex/new-model"},{"id":"cursor/composer-2.5"}]}`)
		default:
			t.Errorf("unexpected diagnostic endpoint %s", r.URL.Path)
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(s.Close)
	u, _ := url.Parse(s.URL)
	port, _ := strconv.Atoi(u.Port())
	return port, count
}

func diagnosticTestServer(t *testing.T, port int, codex, cursor string) *apiServer {
	t.Helper()
	prefs, err := openSettings(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	prefs.prefs.MagpiePort = port
	prefs.prefs.CodexTransport = "magpie"
	prefs.prefs.CLIPaths = map[string]string{"codex": codex, "cursor": cursor}
	return &apiServer{prefs: prefs}
}

func diagnosticDo(t *testing.T, a *apiServer, method, body string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(method, "http://127.0.0.1:8765/api/studio/diagnostics", strings.NewReader(body))
	if method == "POST" {
		req.Header.Set("X-Roundtable", "1")
		req.Header.Set("Content-Type", "application/json")
	}
	w := httptest.NewRecorder()
	a.serve(8765).ServeHTTP(w, req)
	return w
}

func diagnosticDecode(t *testing.T, w *httptest.ResponseRecorder) diagnosticResult {
	t.Helper()
	if w.Code != 200 {
		t.Fatalf("diagnostic status %d: %s", w.Code, w.Body.String())
	}
	for _, secret := range []string{"alice@example.invalid", "SECRET_TOKEN", "NEVER_INFER"} {
		if strings.Contains(w.Body.String(), secret) {
			t.Fatalf("diagnostic leaked vendor output: %s", secret)
		}
	}
	var result diagnosticResult
	if err := json.Unmarshal(w.Body.Bytes(), &result); err != nil {
		t.Fatal(err)
	}
	return result
}

func TestDiagnosticsCacheHasNoActiveActions(t *testing.T) {
	port, count := diagnosticFakeGateway(t)
	codex, cursor := diagnosticFakePrograms(t)
	a := diagnosticTestServer(t, port, codex, cursor)
	result := diagnosticDecode(t, diagnosticDo(t, a, "GET", ""))
	if result.CheckedAt != "" || count.Load() != 0 {
		t.Fatal("GET performed an active check")
	}
	for _, source := range result.Sources {
		if source.State != "unchecked" {
			t.Fatal("unchecked cache claimed readiness")
		}
	}
	t.Setenv("OPENAI_API_KEY", "dummy-key")
	t.Setenv("CODEX_API_KEY", "dummy-key")
	t.Setenv("CURSOR_API_KEY", "dummy-key")
	t.Setenv("CURSOR_AUTH_TOKEN", "dummy-token")
	result = diagnosticDecode(t, diagnosticDo(t, a, "POST", `{"target":"all"}`))
	for name, source := range result.Sources {
		if source.State != "ready" || source.CheckedAt == "" {
			t.Fatalf("%s: %#v", name, source)
		}
		if !strings.Contains(source.Detail, "没有发送模型请求") && !strings.Contains(source.Detail, "未验证") {
			t.Fatalf("missing scope boundary: %#v", source)
		}
	}
	if result.Sources["magpie"].ModelsCount != 3 || len(result.Sources["magpie"].Models) != 2 || result.Sources["magpie"].ModelAvailable == nil || !*result.Sources["magpie"].ModelAvailable {
		t.Fatal("catalog was not actually checked")
	}
	if count.Load() != 2 {
		t.Fatalf("wanted identity+catalog only, got %d", count.Load())
	}
	before := result.Sources["magpie"].CheckedAt
	result = diagnosticDecode(t, diagnosticDo(t, a, "POST", `{"target":"cursor"}`))
	if count.Load() != 2 || result.Sources["magpie"].State != "ready" || result.Sources["magpie"].CheckedAt != before {
		t.Fatal("single-source refresh overwrote another matching cached source")
	}
	_ = diagnosticDecode(t, diagnosticDo(t, a, "GET", ""))
	if count.Load() != 2 {
		t.Fatal("cached GET repeated network requests")
	}
	b := diagnosticTestServer(t, port, codex, cursor)
	if other := diagnosticDecode(t, diagnosticDo(t, b, "GET", "")); other.Sources["magpie"].State != "unchecked" {
		t.Fatal("diagnostic state leaked between app instances")
	}
}

func TestDiagnosticsPreviewDoesNotSaveAndChangedConfigInvalidates(t *testing.T) {
	port, count := diagnosticFakeGateway(t)
	codex, cursor := diagnosticFakePrograms(t)
	a := diagnosticTestServer(t, port, codex, cursor)
	_ = diagnosticDecode(t, diagnosticDo(t, a, "POST", `{"target":"all"}`))
	result := diagnosticDecode(t, diagnosticDo(t, a, "POST", `{"target":"codex","models":{"codex":"new-model"}}`))
	if !result.Preview || result.Sources["magpie"].Model != "codex/new-model" || result.Sources["cursor"].State != "ready" {
		t.Fatal("preview result or matching cached cursor was lost")
	}
	if a.prefs.get().Models["codex"] != "gpt-6.2-sol" {
		t.Fatal("preview mutated live settings")
	}
	result = diagnosticDecode(t, diagnosticDo(t, a, "GET", ""))
	if result.Sources["magpie"].State != "unchecked" || len(result.Sources["magpie"].Models) != 0 || result.Sources["codex"].State != "unchecked" {
		t.Fatal("preview state was presented as current saved connection")
	}
	if count.Load() != 4 {
		t.Fatal("GET must not check changed config")
	}
	a.prefs.mu.Lock()
	a.prefs.prefs.MagpiePort = port + 1
	a.prefs.mu.Unlock()
	result = diagnosticDecode(t, diagnosticDo(t, a, "GET", ""))
	if result.Sources["magpie"].State == "ready" {
		t.Fatal("old port remained ready")
	}
}

func TestDiagnosticsHTTPProtectionAndInputValidation(t *testing.T) {
	port, count := diagnosticFakeGateway(t)
	codex, cursor := diagnosticFakePrograms(t)
	a := diagnosticTestServer(t, port, codex, cursor)
	for _, tc := range []struct {
		name, method, body, host, origin, content, marker, fetch string
		want                                                     int
	}{
		{"missing marker", "POST", `{"target":"all"}`, "127.0.0.1:8765", "", "application/json", "", "", 403},
		{"cross origin", "POST", `{"target":"all"}`, "127.0.0.1:8765", "http://evil.invalid", "application/json", "1", "", 403},
		{"cross site", "POST", `{"target":"all"}`, "127.0.0.1:8765", "", "application/json", "1", "cross-site", 403},
		{"wrong host", "GET", "", "evil.invalid:8765", "", "", "", "", 403},
		{"wrong port", "GET", "", "127.0.0.1:9000", "", "", "", "", 403},
		{"wrong type", "POST", "{}", "127.0.0.1:8765", "", "text/plain", "1", "", 403},
		{"method", "DELETE", "{}", "127.0.0.1:8765", "", "application/json", "1", "", 405},
		{"unknown target", "POST", `{"target":"shell"}`, "127.0.0.1:8765", "", "application/json", "1", "", 400},
		{"unknown field", "POST", `{"target":"all","command":"touch bad"}`, "127.0.0.1:8765", "", "application/json", "1", "", 400},
		{"null", "POST", "null", "127.0.0.1:8765", "", "application/json", "1", "", 400},
		{"multiple", "POST", "{} {}", "127.0.0.1:8765", "", "application/json", "1", "", 400},
		{"port", "POST", `{"magpie_port":0}`, "127.0.0.1:8765", "", "application/json", "1", "", 400},
		{"executable", "POST", `{"cli_paths":{"codex":"/bin/sh"}}`, "127.0.0.1:8765", "", "application/json", "1", "", 400},
		{"too large", "POST", `{"target":"` + strings.Repeat("x", 70000) + `"}`, "127.0.0.1:8765", "", "application/json", "1", "", 400},
	} {
		t.Run(tc.name, func(t *testing.T) {
			r := httptest.NewRequest(tc.method, "http://127.0.0.1:8765/api/studio/diagnostics", strings.NewReader(tc.body))
			r.Host = tc.host
			r.Header.Set("Origin", tc.origin)
			r.Header.Set("Content-Type", tc.content)
			r.Header.Set("X-Roundtable", tc.marker)
			r.Header.Set("Sec-Fetch-Site", tc.fetch)
			w := httptest.NewRecorder()
			a.serve(8765).ServeHTTP(w, r)
			if w.Code != tc.want {
				t.Fatalf("got %d want %d", w.Code, tc.want)
			}
		})
	}
	if count.Load() != 0 {
		t.Fatal("rejected request performed network actions")
	}
}

func TestDiagnosticsGatewayIdentityCatalogAndRedirect(t *testing.T) {
	for _, tc := range []struct {
		name, hello, catalog string
		want                 string
		model                string
	}{
		{"wrong identity", `{"name":"other","version":"1.2.3"}`, `{"data":[{"id":"codex/gpt-6.2-sol"}]}`, "error", "gpt-6.2-sol"},
		{"empty catalog", `{"name":"magpie","version":"1.2.3"}`, `{"data":[]}`, "warning", "gpt-6.2-sol"},
		{"missing model", `{"name":"magpie","version":"1.2.3"}`, `{"data":[{"id":"codex/other"}]}`, "warning", "gpt-6.2-sol"},
		{"duplicate model", `{"name":"magpie","version":"1.2.3"}`, `{"data":[{"id":"codex/gpt-6.2-sol"},{"id":"codex/gpt-6.2-sol"}]}`, "ready", "gpt-6.2-sol"},
		{"routing aliases", `{"name":"magpie","version":"1.2.3"}`, `{"data":[{"id":"coder"},{"id":"my routing group"},{"id":"cursor/composer-2.5"},{"id":"codex/gpt-6.2-sol"},{"id":"codex/gpt-6.2-sol"}]}`, "ready", "gpt-6.2-sol"},
		{"bad version", `{"name":"magpie","version":"alice@example.invalid SECRET_TOKEN"}`, `{"data":[{"id":"codex/gpt-6.2-sol"}]}`, "warning", "gpt-6.2-sol"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			count := 0
			s := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				count++
				if r.URL.Path == "/api/hello" {
					fmt.Fprint(w, tc.hello)
				} else {
					fmt.Fprint(w, tc.catalog)
				}
			}))
			defer s.Close()
			u, _ := url.Parse(s.URL)
			port, _ := strconv.Atoi(u.Port())
			result := diagnoseMagpie(context.Background(), port, tc.model)
			if result.State != tc.want {
				t.Fatalf("%#v", result)
			}
			data, _ := json.Marshal(result)
			if strings.Contains(string(data), "SECRET_TOKEN") || strings.Contains(string(data), "alice@") {
				t.Fatal("version leaked raw data")
			}
			if tc.name == "wrong identity" && count != 1 {
				t.Fatal("queried catalog of an unverified service")
			}
			if tc.name == "routing aliases" {
				if result.ModelsCount != 4 || len(result.Models) != 1 || result.Models[0] != "codex/gpt-6.2-sol" {
					t.Fatalf("routing groups/duplicates affected gateway or seat suggestions: %#v", result)
				}
			}
		})
	}
	var forwarded atomic.Int32
	destination := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { forwarded.Add(1) }))
	defer destination.Close()
	redirect := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { http.Redirect(w, r, destination.URL, 302) }))
	defer redirect.Close()
	u, _ := url.Parse(redirect.URL)
	port, _ := strconv.Atoi(u.Port())
	result := diagnoseMagpie(context.Background(), port, "gpt-6.2-sol")
	if result.State != "error" || forwarded.Load() != 0 {
		t.Fatal("diagnostic followed a redirect beyond its gateway")
	}
}

func TestDiagnosticsLoginMeaningAndNoInference(t *testing.T) {
	port, _ := diagnosticFakeGateway(t)
	codex, cursor := diagnosticFakePrograms(t)
	a := diagnosticTestServer(t, port, codex, cursor)
	a.prefs.prefs.CLIPaths["codex"] = diagnosticFakeCLI(t, "codex", `case "$*" in '--version') echo 'codex-cli 0.170.0';; 'login status') echo 'Not logged in SECRET_TOKEN' >&2; exit 1;; *) exit 99;; esac`)
	result := diagnosticDecode(t, diagnosticDo(t, a, "POST", `{"target":"codex"}`))
	if result.Sources["codex"].State != "ready" || result.Sources["codex"].LoginState != "not_logged_in" {
		t.Fatal("Magpie path incorrectly required direct Codex login")
	}
	result = diagnosticDecode(t, diagnosticDo(t, a, "POST", `{"target":"codex","codex_transport":"direct"}`))
	if result.Sources["codex"].State != "error" {
		t.Fatal("direct path accepted missing login")
	}
	a.prefs.prefs.CLIPaths["codex"] = diagnosticFakeCLI(t, "codex", `case "$*" in '--version') echo 'codex-cli 0.170.0';; 'login status') echo 'API key configured - SECRET_TOKEN' >&2;; *) exit 99;; esac`)
	result = diagnosticDecode(t, diagnosticDo(t, a, "POST", `{"target":"codex","codex_transport":"direct"}`))
	if result.Sources["codex"].State != "warning" || result.Sources["codex"].AuthMethod != "api_key" {
		t.Fatal("API-key login was described as subscription-ready")
	}
	a.prefs.prefs.CLIPaths["cursor"] = diagnosticFakeCLI(t, "agent", `case "$*" in '--version') echo '2026.11.11-043ef28';; 'status --format json') echo '{"status":"authenticated","isAuthenticated":true,"hasAccessToken":true,"hasRefreshToken":true,"message":"Logged in (unable to fetch user details)","email":"alice@example.invalid"}';; *) exit 99;; esac`)
	result = diagnosticDecode(t, diagnosticDo(t, a, "POST", `{"target":"cursor"}`))
	if result.Sources["cursor"].State != "warning" {
		t.Fatal("cached authentication was described as verified live connectivity")
	}
}

func TestDiagnosticsCancellationAndBusy(t *testing.T) {
	codex, cursor := diagnosticFakePrograms(t)
	a := diagnosticTestServer(t, 3425, codex, cursor)
	a.diag.busy = true
	if w := diagnosticDo(t, a, "POST", `{"target":"cursor"}`); w.Code != 409 {
		t.Fatal(w.Code)
	}
	a.diag.busy = false
	slow := diagnosticFakeCLI(t, "agent", `if [ "$*" = '--version' ]; then echo '2026.11.11-043ef28'; exit 0; fi
trap '' TERM
while :; do /bin/sleep 1; done`)
	a.prefs.prefs.CLIPaths["cursor"] = slow
	ctx, cancel := context.WithTimeout(context.Background(), 80*time.Millisecond)
	defer cancel()
	r := httptest.NewRequest("POST", "http://127.0.0.1:8765/api/studio/diagnostics", strings.NewReader(`{"target":"cursor"}`)).WithContext(ctx)
	r.Header.Set("X-Roundtable", "1")
	r.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	start := time.Now()
	a.serve(8765).ServeHTTP(w, r)
	if w.Code != 408 || time.Since(start) > 2*time.Second {
		t.Fatalf("cancellation: %d after %s", w.Code, time.Since(start))
	}
	if a.diag.snapshot(a.prefs.get()).CheckedAt != "" {
		t.Fatal("cancelled check overwrote last results")
	}
}

func TestDiagnosticsMissingUnknownAndUnauthenticated(t *testing.T) {
	codex, cursor := diagnosticFakePrograms(t)
	a := diagnosticTestServer(t, 3425, codex, cursor)
	a.prefs.prefs.CLIPaths["cursor"] = filepath.Join(t.TempDir(), "agent")
	result := diagnosticDecode(t, diagnosticDo(t, a, "POST", `{"target":"cursor"}`))
	if result.Sources["cursor"].State != "error" || !strings.Contains(result.Sources["cursor"].Title, "未安装") {
		t.Fatal("missing executable was not distinguished")
	}
	for _, tc := range []struct{ name, body, want, login string }{
		{"unknown", "printf 'unexpected SECRET_TOKEN alice@example.invalid'", "warning", "unknown"},
		{"unauthenticated", `printf '%s' '{"status":"unauthenticated","isAuthenticated":false,"hasAccessToken":false,"hasRefreshToken":false,"message":"Not logged in SECRET_TOKEN"}'`, "error", "not_logged_in"},
		{"partial", `printf '%s' '{"status":"partially-authenticated","isAuthenticated":false,"hasAccessToken":true,"hasRefreshToken":false}'`, "error", "not_logged_in"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			a.prefs.prefs.CLIPaths["cursor"] = diagnosticFakeCLI(t, "agent", "if [ \"$*\" = '--version' ]; then echo '2026.11.11-043ef28'; exit 0; fi\n"+tc.body)
			result := diagnosticDecode(t, diagnosticDo(t, a, "POST", `{"target":"cursor"}`))
			if source := result.Sources["cursor"]; source.State != tc.want || source.LoginState != tc.login {
				t.Fatalf("%#v", source)
			}
		})
	}
}

func TestDiagnosticsGatewayConnectionAndSelectedModelAreSeparate(t *testing.T) {
	port, _ := diagnosticFakeGateway(t)
	codex, cursor := diagnosticFakePrograms(t)
	a := diagnosticTestServer(t, port, codex, cursor)
	result := diagnosticDecode(t, diagnosticDo(t, a, "POST", `{"target":"all","models":{"codex":"not-listed"}}`))
	gateway := result.Sources["magpie"]
	if gateway.State != "warning" || gateway.ModelAvailable == nil || *gateway.ModelAvailable || len(gateway.Models) != 2 || gateway.ModelsCount != 3 {
		t.Fatalf("connected gateway was conflated with missing model: %#v", gateway)
	}
	if result.Sources["codex"].State != "error" {
		t.Fatal("Codex Magpie route accepted a missing requested model")
	}
	for _, id := range gateway.Models {
		if !strings.HasPrefix(id, "codex/") {
			t.Fatalf("another seat's model was suggested: %q", id)
		}
	}
	result = diagnosticDecode(t, diagnosticDo(t, a, "POST", `{"target":"all","codex_transport":"direct","models":{"codex":"not-listed"}}`))
	if result.Sources["magpie"].State != "warning" || result.Sources["codex"].State != "ready" {
		t.Fatal("direct Codex auth incorrectly depended on gateway model membership")
	}
}
