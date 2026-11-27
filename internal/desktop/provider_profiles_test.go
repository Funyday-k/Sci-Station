package desktop

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"scistation.local/desktop/internal/credentials"
	"scistation.local/desktop/internal/gateway"
	"scistation.local/desktop/internal/meeting"
)

func providerFixtureKeys() func(string, string) credentials.Store {
	var mu sync.Mutex
	keys := map[[2]string]*mockMinerKeychain{}
	return func(id, endpoint string) credentials.Store {
		mu.Lock()
		defer mu.Unlock()
		index := [2]string{id, endpoint}
		if keys[index] == nil {
			keys[index] = &mockMinerKeychain{}
		}
		return keys[index]
	}
}

func TestProviderProfilePreservesExtensionsAndFailedWrites(t *testing.T) {
	dir := t.TempDir()
	file := filepath.Join(dir, "provider-profiles.json")
	baseline := []byte(`{"version":1,"future":{"opaque":true},"profiles":[{"id":"known","name":"Before","base_url":"http://127.0.0.1:39223/v1","model":"fixture","temperature":0.2,"future_field":{"revision":4}}]}`)
	if err := os.WriteFile(file, baseline, 0600); err != nil {
		t.Fatal(err)
	}
	keys := providerFixtureKeys()
	store, err := openProviderProfiles(dir, keys)
	if err != nil {
		t.Fatal(err)
	}
	profile := store.Profiles()[0]
	profile.Name = "After"
	store.file = dir
	if _, err := store.upsert(profile); !errors.Is(err, errProviderWrite) || store.Profiles()[0].Name != "Before" {
		t.Fatal("failed profile write changed active preferences", err)
	}
	store.file = file
	if actual, err := os.ReadFile(file); err != nil || !bytes.Equal(actual, baseline) {
		t.Fatal("failed write changed original profile file", err)
	}
	if _, err := store.upsert(profile); err != nil {
		t.Fatal(err)
	}
	updated, err := os.ReadFile(file)
	if err != nil || !bytes.Contains(updated, []byte(`"future":{"opaque":true}`)) || !bytes.Contains(updated, []byte(`"future_field":{"revision":4}`)) {
		t.Fatal("unknown fields were discarded", err)
	}
	if err := store.updateKey(profile.ID, "fixture-temporary-secret"); err != nil {
		t.Fatal(err)
	}
	second := profile
	second.BaseURL = "http://127.0.0.1:39224/v1"
	if _, err := store.upsert(second); err == nil || store.remove(profile.ID) == nil || store.Profiles()[0].BaseURL != profile.BaseURL {
		t.Fatal("endpoint or profile changed while still holding an associated key")
	}
	if key, err := store.ResolveKey(second); err != nil || key != "" {
		t.Fatal("a changed endpoint can reuse the previous key")
	}
	if after, err := os.ReadFile(file); err != nil || !bytes.Equal(updated, after) {
		t.Fatal("key operations touched the profile file", err)
	}
	if err := store.updateKey(profile.ID, ""); err != nil {
		t.Fatal(err)
	}
	if _, err := store.upsert(second); err != nil {
		t.Fatal(err)
	}
	reopened, err := openProviderProfiles(dir, keys)
	if err != nil || reopened.Profiles()[0].BaseURL != second.BaseURL || reopened.Profiles()[0].Name != "After" {
		t.Fatal("profile preferences did not survive reopen", err)
	}
	unknown := []byte(`{"version":2,"profiles":[],"future":true}`)
	if err := os.WriteFile(file, unknown, 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := openProviderProfiles(dir, keys); err == nil {
		t.Fatal("unsupported profile format was loaded")
	}
	if after, err := os.ReadFile(file); err != nil || !bytes.Equal(after, unknown) {
		t.Fatal("unsupported profile file was altered", err)
	}
}

func TestDirectProviderUsesNormalMeetingAndModelCatalog(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	t.Setenv("XDG_CONFIG_HOME", t.TempDir())
	const saved = "fixture-direct-profile-key"
	const temporary = "fixture-one-time-connection-key"
	var calls, variant atomic.Int32
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodGet && r.URL.Path == "/v1/models" {
			http.Error(w, "fixture Magpie offline", http.StatusServiceUnavailable)
			return
		}
		if r.Method != http.MethodPost || r.URL.Path != "/self-hosted/v1/chat/completions" ||
			r.Header.Get(desktopCredentialHeader) != "" || r.Header.Get("X-Magpie-Session") != "" {
			t.Error("wrong outbound direct provider request")
			http.Error(w, "unexpected request", 400)
			return
		}
		calls.Add(1)
		var body struct {
			Model       string                           `json:"model"`
			Temperature float64                          `json:"temperature"`
			MaxTokens   int                              `json:"max_tokens"`
			Stream      bool                             `json:"stream"`
			Messages    []struct{ Role, Content string } `json:"messages"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.Model != "fixture/testing" || body.Temperature != 0.45 || body.MaxTokens != 1800 || !body.Stream || len(body.Messages) == 0 {
			t.Error("lost direct provider configuration")
			http.Error(w, "invalid payload", 400)
			return
		}
		last := body.Messages[len(body.Messages)-1].Content
		key, message := saved, `{"action":"say","text":"Verified in the existing roundtable."}`
		switch {
		case last == "Reply with OK.":
			key, message = temporary, "OK"
		case strings.HasPrefix(last, "AGENDA DRAFT REQUEST"):
			message = `{"agenda":[{"title":"Review the calculation","kind":"discussion"}]}`
		}
		if r.Header.Get("Authorization") != "Bearer "+key {
			t.Error("wrong direct provider credential")
			http.Error(w, "wrong authorization", 403)
			return
		}
		switch variant.Load() {
		case 1:
			http.Redirect(w, r, "/redirected", http.StatusTemporaryRedirect)
		case 2:
			w.Header().Set("Content-Type", "text/event-stream")
			split := len(saved) / 2
			for _, delta := range []string{"Safe prefix ", saved[:split], saved[split:]} {
				fmt.Fprintf(w, "data: {\"choices\":[{\"delta\":{\"content\":%q}}]}\n\n", delta)
			}
			io.WriteString(w, "data: {\"choices\":[{\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n")
		default:
			fmt.Fprintf(w, `{"choices":[{"finish_reason":"stop","message":{"content":%q}}]}`, message)
		}
	}))
	defer upstream.Close()
	dir := t.TempDir()
	prefs, err := openSettings(dir)
	if err != nil {
		t.Fatal(err)
	}
	u, _ := url.Parse(upstream.URL)
	prefs.prefs.MagpiePort, _ = strconv.Atoi(u.Port())
	keys := providerFixtureKeys()
	prefs.providerProfiles, err = openProviderProfiles(dir, keys)
	if err != nil {
		t.Fatal(err)
	}
	engine, err := meeting.New(filepath.Join(dir, "studio"), gatewayCall(studioGateway(prefs)), func() meeting.Settings { return prefs.get().Settings })
	if err != nil {
		t.Fatal(err)
	}
	defer engine.Shutdown(context.Background())
	host := openNavigationFixture(t, t.TempDir())
	host.desktop, host.minerCreds, host.prefs, host.meetings = true, newMinerCredentials(&mockMinerKeychain{}), prefs, engine
	api := host.serve(18765)
	do := func(method, path string, input any, proof string, want int) []byte {
		t.Helper()
		data, _ := json.Marshal(input)
		r := httptest.NewRequest(method, "http://127.0.0.1:18765/api/studio/"+path, bytes.NewReader(data))
		r.Header.Set("X-Roundtable", "1")
		r.Header.Set("Content-Type", "application/json")
		r.Header.Set(desktopCredentialHeader, proof)
		w := httptest.NewRecorder()
		api.ServeHTTP(w, r)
		if strings.Contains(w.Body.String(), saved) || strings.Contains(w.Body.String(), temporary) {
			t.Fatal("HTTP API exposed a provider key")
		}
		if w.Code != want {
			t.Fatalf("%s %s: got %d, want %d: %s", method, path, w.Code, want, w.Body.String())
		}
		return w.Body.Bytes()
	}
	proof := host.minerCreds.proof
	const path = "provider-profiles"
	do("GET", path, nil, "", 403)
	draft := gateway.CompatibleProfile{Name: "Self-hosted Fixture", BaseURL: upstream.URL + "/self-hosted/v1", Model: "fixture/testing", Temperature: 0.45, MaxTokens: 1800}
	do("POST", path, map[string]any{"action": "test", "profile": draft, "key": temporary}, proof, 200)
	if _, err := os.Stat(filepath.Join(dir, "provider-profiles.json")); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("connection test should leave no persisted profile")
	}
	profile := scienceWorkflowDecode[gateway.CompatibleProfile](t, do("POST", path, map[string]any{"action": "save", "profile": draft}, proof, 200))
	if profile.ID == "" || calls.Load() != 1 {
		t.Fatal("saving metadata submitted an unexpected provider call")
	}
	setKey := map[string]any{"action": "set_key", "id": profile.ID, "key": saved}
	do("POST", path, setKey, "", 403)
	do("POST", path, setKey, proof, 200)
	b := do("GET", path, nil, proof, 200)
	if rows := scienceWorkflowDecode[[]providerProfileView](t, b); len(rows) != 1 || !rows[0].Configured {
		t.Fatal("saved key status missing")
	}

	catalog := scienceWorkflowDecode[gateway.Catalog](t, do("GET", "models", nil, "", 200))
	model := profile.CatalogModel().ID
	if len(catalog.Models) != 1 || catalog.DefaultModel != model || catalog.MagpieError == "" {
		t.Fatal("direct models must remain available with Magpie offline")
	}
	project, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	testMeetingProject(t, host, project)
	s := scienceWorkflowDecode[meeting.Session](t, do("POST", "sessions", map[string]any{
		"topic": "Check the fixture calculation", "project": project, "members": []meeting.Member{{Model: model, Effort: "auto"}},
	}, "", 201))
	if len(s.Members) != 1 || s.Members[0].Source != "openai-compatible" {
		t.Fatal("regular session did not bind the catalog model")
	}
	sessionPath := "sessions/" + s.ID
	waitFor := func(ready func(meeting.Session) bool) meeting.Session {
		t.Helper()
		for stop := time.Now().Add(3 * time.Second); time.Now().Before(stop); {
			s := scienceWorkflowDecode[meeting.Session](t, do("GET", sessionPath, nil, "", 200))
			if ready(s) {
				return s
			}
			time.Sleep(10 * time.Millisecond)
		}
		t.Fatal("timed out for existing meeting engine")
		return meeting.Session{}
	}
	waitFor(func(s meeting.Session) bool { return s.AgendaDraftStatus == "ready" })
	do("POST", sessionPath+"/run", map[string]any{"expected_round": 0}, "", 202)
	s = waitFor(func(s meeting.Session) bool { return s.Status != "running" && len(s.Rounds) > 0 })
	b, _ = json.Marshal(s.Rounds)
	if s.Status != "ready" || !bytes.Contains(b, []byte("Verified in the existing roundtable.")) {
		t.Fatal("direct provider did not produce a public turn")
	}

	reopened, err := openProviderProfiles(dir, keys)
	if err != nil {
		t.Fatal(err)
	}
	if configured, err := reopened.configured(reopened.Profiles()[0]); err != nil || !configured {
		t.Fatal("saved credential not available after reopening")
	}
	metadata, _ := os.ReadFile(filepath.Join(dir, "provider-profiles.json"))
	if bytes.Contains(metadata, []byte(saved)) || bytes.Contains(metadata, []byte(temporary)) {
		t.Fatal("provider key was persisted to the profile file")
	}
	variant.Store(1)
	if _, err := studioGateway(prefs).Generate(context.Background(), model, "auto", "", "redirect fixture", ""); err == nil ||
		!strings.Contains(err.Error(), "HTTP 307") {
		t.Fatal("provider did not reject a redirect")
	}
	variant.Store(2)
	var observed strings.Builder
	if result, err := studioGateway(prefs).GenerateWithImages(context.Background(), model, "auto", "", "echo fixture", "", nil, func(text string) {
		if text == "" {
			observed.Reset()
		} else {
			observed.WriteString(text)
		}
	}); err == nil || result != "" || observed.Len() != 0 {
		t.Fatal("direct output leaked a credential echoed across events")
	}
	do("POST", path, map[string]any{"action": "clear_key", "id": profile.ID}, proof, 200)
	do("POST", path, map[string]any{"action": "remove", "id": profile.ID}, proof, 200)
}
