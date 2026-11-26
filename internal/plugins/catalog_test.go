package plugins

import (
	"bytes"
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func TestCatalogValidatesURLsAndStaticIndex(t *testing.T) {
	for _, raw := range []string{"file:///tmp/catalog", "http://elsewhere.example/catalog", "https://alice:secret@host.example/catalog", "http://localhost.example/catalog", "https://example.org:99999/catalog", "http://127.0.0.1/x#part"} {
		if _, err := checkedURL(raw); err == nil {
			t.Fatalf("accepted invalid URL %q", raw)
		}
	}
	for _, raw := range []string{"http://127.0.0.1/catalog", "http://[::1]:4000/catalog", "https://third-party.example/repo/catalog.json"} {
		if _, err := checkedURL(raw); err != nil {
			t.Fatalf("valid URL %q: %v", raw, err)
		}
	}
	p, _ := marketPackage(t, "dev.example.tool", "1.0.0", "guidance", "")
	const base = "https://author.example/sub/catalog.json"
	for _, raw := range []string{"https://other.example/pkg.json", "http://author.example/pkg", "https://user@author.example/pkg", "https://author.example:8443/pkg", "pkg#frag"} {
		p.URL = raw
		if _, err := ParseCatalog(catalogJSON(t, p), base); err == nil {
			t.Fatalf("accepted package location %q", raw)
		}
	}
	p.URL = "../tools/pkg.json"
	c, err := ParseCatalog(catalogJSON(t, p), base)
	if err != nil || c.Plugins[0].URL != "https://author.example/tools/pkg.json" {
		t.Fatalf("relative package resolution: %v %v", c, err)
	}
	if _, err := ParseCatalog(catalogJSON(t, p), ""); err == nil {
		t.Fatal("embedded path escaped directory")
	}
	p.URL = "pkg.json"
	if _, err := ParseCatalog(catalogJSON(t, p, p), base); err == nil {
		t.Fatal("duplicate ID accepted")
	}
	for _, raw := range [][]byte{
		bytes.Replace(catalogJSON(t, p), []byte(`"name":"Example"`), []byte(`"name":"Example","name":"dupe"`), 1),
		append(catalogJSON(t, p), []byte("{}")...),
		bytes.Replace(catalogJSON(t, p), []byte(`"version":"1.0.0"`), []byte(`"version":"1.00.0"`), 1),
		bytes.Replace(catalogJSON(t, p), []byte(`"round.guidance"`), []byte(`"round.guidance","round.guidance"`), 1),
		bytes.Replace(catalogJSON(t, p), []byte(`"round.guidance"`), []byte(`"unknown"`), 1),
		bytes.Repeat([]byte(" "), MaxCatalogBytes+1),
	} {
		if _, err := ParseCatalog(raw, base); err == nil {
			t.Fatal("invalid index accepted")
		}
	}
}

func TestCatalogFetchEnforcesRedirectsLimitsAndCancellation(t *testing.T) {
	var hits atomic.Int32
	other := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) { hits.Add(1) }))
	defer other.Close()
	mux := http.NewServeMux()
	mux.HandleFunc("/cross", func(w http.ResponseWriter, r *http.Request) { http.Redirect(w, r, other.URL, http.StatusFound) })
	mux.HandleFunc("/credentials", func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, "http://user:password@"+r.Host+"/final", http.StatusFound)
	})
	mux.HandleFunc("/same", func(w http.ResponseWriter, r *http.Request) { http.Redirect(w, r, "/sub/index", http.StatusFound) })
	mux.HandleFunc("/sub/index", func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Referer") != "" {
			t.Error("redirect sent referer")
		}
		_, _ = w.Write([]byte("ok"))
	})
	mux.HandleFunc("/loop", func(w http.ResponseWriter, r *http.Request) { http.Redirect(w, r, "/loop", http.StatusFound) })
	mux.HandleFunc("/slow", func(w http.ResponseWriter, r *http.Request) { <-r.Context().Done() })
	mux.HandleFunc("/large", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.(http.Flusher).Flush()
		_, _ = w.Write([]byte(strings.Repeat("a", 1024)))
	})
	srv := httptest.NewServer(mux)
	defer srv.Close()
	for _, path := range []string{"/cross", "/credentials", "/loop", "/large", "/missing"} {
		if _, _, err := fetch(t.Context(), srv.URL+path, 3); err == nil {
			t.Fatalf("path should fail: %s", path)
		}
	}
	if hits.Load() != 0 {
		t.Fatal("cross-origin redirect forwarded a request")
	}
	b, url, err := fetch(t.Context(), srv.URL+"/same", 2)
	if err != nil || string(b) != "ok" || url != srv.URL+"/sub/index" {
		t.Fatalf("same origin redirect: %q %q %v", b, url, err)
	}
	ctx, cancel := context.WithTimeout(t.Context(), 50*time.Millisecond)
	defer cancel()
	if _, _, err := fetch(ctx, srv.URL+"/slow", 256); err == nil {
		t.Fatal("fetch did not respect caller cancellation")
	}
}
