package plugins

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"testing"
)

func openRegistry(t *testing.T, dir string) *Store {
	t.Helper()
	s, err := NewStore(dir)
	if err != nil {
		t.Fatal(err)
	}
	return s
}
func registryView(t *testing.T, s *Store) View {
	t.Helper()
	v, err := s.View()
	if err != nil {
		t.Fatal(err)
	}
	return v
}
func marketPackage(t *testing.T, id, version, round, report string) (CatalogEntry, []byte) {
	t.Helper()
	m := Manifest{SchemaVersion: 1, ID: id, Version: version, Name: "Research Methods", Description: "Example for authors", Author: "Team", Contributions: Contributions{RoundGuidance: round, ReportGuidance: report}}
	b, err := json.Marshal(m)
	if err != nil {
		t.Fatal(err)
	}
	return CatalogEntry{ID: id, Version: version, Name: m.Name, Description: m.Description, Author: m.Author, URL: id + ".json", SHA256: checksum(b), Capabilities: m.Capabilities()}, b
}
func catalogJSON(t *testing.T, entries ...CatalogEntry) []byte {
	t.Helper()
	data, err := json.Marshal(Catalog{SchemaVersion: 1, Name: "Example", Plugins: append([]CatalogEntry{}, entries...)})
	if err != nil {
		t.Fatal(err)
	}
	return data
}

type localCatalog struct {
	server *httptest.Server
	mu     sync.Mutex
	files  map[string][]byte
}

func newLocalCatalog(t *testing.T) *localCatalog {
	t.Helper()
	f := &localCatalog{files: map[string][]byte{}}
	f.server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet || r.ContentLength > 0 || r.Header.Get("Authorization") != "" || r.Header.Get("Cookie") != "" {
			t.Error("source received unexpected information")
		}
		f.mu.Lock()
		data, ok := f.files[r.URL.Path]
		f.mu.Unlock()
		if !ok {
			http.NotFound(w, r)
			return
		}
		_, _ = w.Write(data)
	}))
	t.Cleanup(f.server.Close)
	return f
}
func (f *localCatalog) put(path string, data []byte) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.files[path] = data
}
func (f *localCatalog) publish(t *testing.T, p CatalogEntry, data []byte) {
	f.put("/catalog.json", catalogJSON(t, p))
	f.put("/"+p.URL, data)
}
func (f *localCatalog) subscribe(t *testing.T, s *Store) string {
	t.Helper()
	url := f.server.URL + "/catalog.json"
	if err := s.AddSource(t.Context(), url); err != nil {
		t.Fatal(err)
	}
	for _, source := range registryView(t, s).Sources {
		if source.URL == url {
			return source.ID
		}
	}
	t.Fatal("subscription missing")
	return ""
}
func installMarket(t *testing.T, s *Store, source string, p CatalogEntry) {
	t.Helper()
	if err := s.Install(t.Context(), source, p.ID, p.SHA256, p.Capabilities); err != nil {
		t.Fatal(err)
	}
}

func TestRegistrySubscriptionLifecycle(t *testing.T) {
	dir := t.TempDir()
	s := openRegistry(t, dir)
	f := newLocalCatalog(t)
	v1, b1 := marketPackage(t, "dev.example.methods", "1.2.0", "Review questions", "")
	f.publish(t, v1, b1)
	src := f.subscribe(t, s)
	if err := s.AddSource(t.Context(), f.server.URL+"/catalog.json"); err == nil {
		t.Fatal("duplicate source accepted")
	}
	if v := registryView(t, s); len(v.Installed) != 0 {
		t.Fatal("subscription installed a package")
	}
	for _, grants := range [][]string{nil, {}, {CapRoundGuidance, CapCodeExecute}, {CapReportGuidance}} {
		if err := s.Install(t.Context(), src, v1.ID, v1.SHA256, grants); err == nil {
			t.Fatalf("incorrect permissions accepted: %v", grants)
		}
	}
	if err := s.Install(t.Context(), src, v1.ID, "", v1.Capabilities); err == nil {
		t.Fatal("missing checksum accepted")
	}
	if err := s.Install(t.Context(), src, v1.ID, v1.SHA256, v1.Capabilities, "7.0.0"); err == nil {
		t.Fatal("incorrect expected version accepted")
	}
	f.put("/"+v1.URL, append(append([]byte{}, b1...), ' '))
	if err := s.Install(t.Context(), src, v1.ID, v1.SHA256, v1.Capabilities); err == nil {
		t.Fatal("changed bytes accepted")
	}
	f.put("/"+v1.URL, b1)
	installMarket(t, s, src, v1)
	if err := s.SetEnabled(v1.ID, src, v1.Version, v1.SHA256, false); err != nil {
		t.Fatal(err)
	}
	v2, b2 := marketPackage(t, v1.ID, "1.10.0", "Review questions", "List references")
	f.publish(t, v2, b2)
	if err := s.Refresh(t.Context(), src); err != nil {
		t.Fatal(err)
	}
	reopened := openRegistry(t, dir)
	if got := registryView(t, reopened).Installed[0]; got.Version != v1.Version || got.Enabled {
		t.Fatal("refresh upgraded or enabled installed version")
	}
	if err := reopened.Install(t.Context(), src, v2.ID, v2.SHA256, v1.Capabilities); err == nil {
		t.Fatal("old grant silently accepted for upgrade")
	}
	installMarket(t, reopened, src, v2)
	if err := s.Uninstall(v1.ID, src, v1.Version, v1.SHA256); err == nil {
		t.Fatal("stale uninstall succeeded")
	}
	if err := s.SetEnabled(v2.ID, "other", v2.Version, v2.SHA256, true); err == nil {
		t.Fatal("different source enabled")
	}
	if got := registryView(t, s).Installed[0]; got.Version != v2.Version || got.Enabled {
		t.Fatal("upgrade lost disabled state")
	}
	f.publish(t, v1, b1)
	if err := s.Refresh(t.Context(), src); err != nil {
		t.Fatal(err)
	}
	if err := s.Install(t.Context(), src, v1.ID, v1.SHA256, v1.Capabilities); err == nil {
		t.Fatal("downgrade accepted")
	}
	changed, otherBytes := marketPackage(t, v2.ID, v2.Version, "Different bytes", "List references")
	f.publish(t, changed, otherBytes)
	if err := s.Refresh(t.Context(), src); err != nil {
		t.Fatal(err)
	}
	if err := s.Install(t.Context(), src, changed.ID, changed.SHA256, changed.Capabilities); err == nil {
		t.Fatal("same version replacement accepted")
	}
	other := newLocalCatalog(t)
	other.publish(t, v2, b2)
	otherID := other.subscribe(t, s)
	if err := s.Install(t.Context(), otherID, v2.ID, v2.SHA256, v2.Capabilities); err == nil {
		t.Fatal("cross-source replacement accepted")
	}
	f.put("/catalog.json", []byte("broken"))
	if err := reopened.Refresh(t.Context(), src); err == nil {
		t.Fatal("bad refresh succeeded")
	}
	if v := registryView(t, reopened); !slices.ContainsFunc(v.Available, func(p AvailablePlugin) bool { return p.SourceID == src && p.SHA256 == changed.SHA256 }) {
		t.Fatal("bad refresh destroyed cached catalog")
	}
	if err := s.RemoveSource(src); err != nil {
		t.Fatal(err)
	}
	if err := reopened.SetEnabled(v2.ID, src, v2.Version, v2.SHA256, true); err != nil {
		t.Fatal(err)
	}
	enabled, err := s.Enabled()
	if err != nil || len(enabled) != 1 || enabled[0].Contributions.ReportGuidance != "List references" {
		t.Fatalf("unsubscribed package missing: %v %v", enabled, err)
	}
	if err := s.Uninstall(v2.ID, src, v2.Version, v2.SHA256); err != nil {
		t.Fatal(err)
	}
	if got := registryView(t, s).Installed; len(got) != 0 {
		t.Fatalf("package still installed: %v", got)
	}
	files, err := os.ReadDir(filepath.Join(dir, "packages"))
	if err != nil || len(files) != 0 {
		t.Fatalf("left package bytes: %v %v", files, err)
	}
}

func TestRegistryBindsMetadataAndBudgetsBothStages(t *testing.T) {
	s := openRegistry(t, t.TempDir())
	f := newLocalCatalog(t)
	first, b1 := marketPackage(t, "dev.example.one", "1.0.0", strings.Repeat("a", 4900), strings.Repeat("b", 1000))
	second, b2 := marketPackage(t, "dev.example.two", "1.0.0", strings.Repeat("a", 4800), strings.Repeat("b", 1000))
	f.put("/catalog.json", catalogJSON(t, first, second))
	f.put("/"+first.URL, b1)
	f.put("/"+second.URL, b2)
	src := f.subscribe(t, s)
	installMarket(t, s, src, first)
	if err := s.Install(t.Context(), src, second.ID, second.SHA256, second.Capabilities); err == nil {
		t.Fatal("combined round budget exceeded")
	}
	if err := s.SetEnabled(first.ID, src, first.Version, first.SHA256, false); err != nil {
		t.Fatal(err)
	}
	installMarket(t, s, src, second)
	if err := s.SetEnabled(first.ID, src, first.Version, first.SHA256, true); err == nil {
		t.Fatal("reenabling exceeded combined budget")
	}
	if got := registryView(t, s).Installed; len(got) != 2 || got[0].Enabled || !got[1].Enabled {
		t.Fatal("failed enable modified prior installation")
	}
	mismatch, b3 := marketPackage(t, "dev.example.three", "1.0.0", "guidance", "")
	mismatch.Name = "Wrong metadata"
	f.publish(t, mismatch, b3)
	if err := s.Refresh(t.Context(), src); err != nil {
		t.Fatal(err)
	}
	if err := s.Install(t.Context(), src, mismatch.ID, mismatch.SHA256, mismatch.Capabilities); err == nil {
		t.Fatal("mismatched metadata accepted")
	}
	mismatch.Name = "Research Methods"
	mismatch.Capabilities = []string{CapReportGuidance}
	f.publish(t, mismatch, b3)
	if err := s.Refresh(t.Context(), src); err != nil {
		t.Fatal(err)
	}
	if err := s.Install(t.Context(), src, mismatch.ID, mismatch.SHA256, mismatch.Capabilities); err == nil {
		t.Fatal("mismatched capability accepted")
	}
	third, b3 := marketPackage(t, "dev.example.three", "1.0.0", "", strings.Repeat("x", 7300))
	f.publish(t, third, b3)
	if err := s.Refresh(t.Context(), src); err != nil {
		t.Fatal(err)
	}
	if err := s.Install(t.Context(), src, third.ID, third.SHA256, third.Capabilities); err == nil {
		t.Fatal("combined report budget exceeded")
	}
}

func TestRegistryExactActionAndOfflineGuidance(t *testing.T) {
	dir := t.TempDir()
	s := openRegistry(t, dir)
	v := registryView(t, s)
	var action AvailablePlugin
	for _, item := range v.Available {
		installMarket(t, s, item.SourceID, item.CatalogEntry)
		if slices.Contains(item.Capabilities, CapCodeExecute) {
			action = item
		}
	}
	if action.ID == "" {
		t.Fatal("missing offline example action")
	}
	p, err := s.ActionPlugin(action.ID, builtinID, action.Version, action.SHA256)
	if err != nil || len(p.Module) == 0 {
		t.Fatalf("action unavailable: %v", err)
	}
	for _, key := range [][3]string{{"bogus", action.Version, action.SHA256}, {builtinID, "0.0.1", action.SHA256}, {builtinID, action.Version, strings.Repeat("f", 64)}} {
		if _, err := s.ActionPlugin(action.ID, key[0], key[1], key[2]); err == nil {
			t.Fatalf("stale key accepted: %v", key)
		}
	}
	encoded, err := json.Marshal(registryView(t, s))
	if err != nil || bytes.Contains(encoded, []byte(`"module"`)) {
		t.Fatal("market view exposed module")
	}
	if err := s.SetEnabled(action.ID, builtinID, action.Version, action.SHA256, false); err != nil {
		t.Fatal(err)
	}
	if _, err := s.ActionPlugin(action.ID, builtinID, action.Version, action.SHA256); err == nil {
		t.Fatal("disabled action enabled")
	}
	if err := s.SetEnabled(action.ID, builtinID, action.Version, action.SHA256, true); err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(filepath.Join(dir, "packages", action.SHA256)); err != nil {
		t.Fatal(err)
	}
	if _, err := s.ActionPlugin(action.ID, builtinID, action.Version, action.SHA256); err == nil {
		t.Fatal("missing package accepted")
	}
	for i := 0; i < cap(moduleSlots); i++ {
		moduleSlots <- struct{}{}
	}
	defer func() {
		for i := 0; i < cap(moduleSlots); i++ {
			<-moduleSlots
		}
	}()
	guidance, err := s.EnabledGuidance()
	if err != nil || len(guidance) == 0 {
		t.Fatalf("pure action blocked meeting: %v", err)
	}
	for _, p := range guidance {
		if p.ID == action.ID || p.Module != nil {
			t.Fatal("action data entered meeting")
		}
	}
}

func TestRegistryCorruptFilePreserved(t *testing.T) {
	for _, bad := range []string{"oops", "null", "{}", `{"schema_version":1,"sources":{"broken":{}},"installed":{}}`} {
		dir := t.TempDir()
		s := openRegistry(t, dir)
		file := filepath.Join(dir, "registry.json")
		if err := os.WriteFile(file, []byte(bad), 0600); err != nil {
			t.Fatal(err)
		}
		if _, err := NewStore(dir); err == nil {
			t.Fatalf("invalid registry %q accepted", bad)
		}
		if _, err := s.View(); err == nil {
			t.Fatal("corruption went unnoticed")
		}
		if err := s.RemoveSource("bad"); err == nil {
			t.Fatal("changed corrupt registry")
		}
		data, err := os.ReadFile(file)
		if err != nil || string(data) != bad {
			t.Fatal("corruption overwritten")
		}
	}
}

func TestRegistryConcurrentProcesses(t *testing.T) {
	const envStore = "MAGPIE_TEST_MARKET_STORE"
	const envSource = "MAGPIE_TEST_MARKET_URL"
	if dir := os.Getenv(envStore); dir != "" {
		if err := openRegistry(t, dir).AddSource(t.Context(), os.Getenv(envSource)); err != nil {
			t.Fatal(err)
		}
		return
	}
	dir := t.TempDir()
	s := openRegistry(t, dir)
	f := newLocalCatalog(t)
	const n = 6
	for i := 0; i < n; i++ {
		f.put(fmt.Sprintf("/%d", i), catalogJSON(t))
	}
	var wg sync.WaitGroup
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			cmd := exec.CommandContext(t.Context(), os.Args[0], "-test.run=^TestRegistryConcurrentProcesses$")
			cmd.Env = append(os.Environ(), envStore+"="+dir, envSource+"="+fmt.Sprintf("%s/%d", f.server.URL, i))
			if out, err := cmd.CombinedOutput(); err != nil {
				t.Errorf("child failed: %v %s", err, out)
			}
		}(i)
	}
	wg.Wait()
	if got := len(registryView(t, s).Sources); got != n+1 {
		t.Fatalf("lost concurrent update: %d", got)
	}
}

func TestRegistryRefreshCannotResurrectRemovedSource(t *testing.T) {
	s := openRegistry(t, t.TempDir())
	data := catalogJSON(t)
	wait := make(chan struct{})
	started := make(chan struct{})
	var mu sync.Mutex
	requests := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		requests++
		n := requests
		mu.Unlock()
		if n == 2 {
			close(started)
			<-wait
		}
		_, _ = w.Write(data)
	}))
	defer srv.Close()
	if err := s.AddSource(t.Context(), srv.URL+"/catalog.json"); err != nil {
		t.Fatal(err)
	}
	id := registryView(t, s).Sources[1].ID
	done := make(chan error, 1)
	go func() { done <- s.Refresh(context.Background(), id) }()
	<-started
	removeErr := s.RemoveSource(id)
	addErr := s.AddSource(t.Context(), srv.URL+"/catalog.json")
	close(wait)
	if err := <-done; err == nil || removeErr != nil || addErr != nil {
		t.Fatalf("stale refresh: %v, remove: %v, re-add: %v", err, removeErr, addErr)
	}
}
