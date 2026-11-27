package research

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestInterfaceLanguageRoundTripIsRootScoped(t *testing.T) {
	dir := t.TempDir()
	s := newResearch(t, dir)
	language := func(s *Service) string {
		return decodeResearch[map[string]string](t, callResearch(t, s, "GET", "/interface", nil, 200))["language"]
	}
	if got := language(s); got != "system" {
		t.Fatalf("default language %q", got)
	}
	path := filepath.Join(dir, interfaceSettingsFile)
	if err := os.WriteFile(path, []byte(`{"version":1,"language":"system","extra":{"kept":true}}`), 0600); err != nil {
		t.Fatal(err)
	}
	for _, choice := range []string{"zh-Hans", "en", "system"} {
		response := callResearch(t, s, "PATCH", "/interface", map[string]string{"language": choice}, 200)
		if got := decodeResearch[map[string]string](t, response)["language"]; got != choice {
			t.Fatalf("response language %q", got)
		}
		if got := language(newResearch(t, dir)); got != choice {
			t.Fatalf("reopened language %q", got)
		}
		if got := language(newResearch(t, t.TempDir())); got != "system" {
			t.Fatalf("second root language %q", got)
		}
	}
	callResearch(t, s, "PATCH", "/interface", map[string]string{"language": "fr"}, 400)
	var persisted struct {
		Extra struct{ Kept bool }
	}
	if err := json.Unmarshal(readModuleTestFile(t, path), &persisted); err != nil || !persisted.Extra.Kept {
		t.Fatalf("unknown preference lost: %+v, %v", persisted, err)
	}
	broken := []byte(`{"version":2,"language":"en"}`)
	if err := os.WriteFile(path, broken, 0600); err != nil {
		t.Fatal(err)
	}
	callResearch(t, s, "GET", "/interface", nil, 500)
	callResearch(t, s, "PATCH", "/interface", map[string]string{"language": "zh-Hans"}, 500)
	if got := string(readModuleTestFile(t, path)); got != string(broken) {
		t.Fatalf("failed update overwrote preferences: %s", got)
	}
}

func TestInterfaceLanguageNotifiesDesktopAfterCommit(t *testing.T) {
	s := newResearch(t, t.TempDir())
	var updates []string
	s.OnWorkspaceMenuChanged(func() {
		language, err := s.InterfaceLanguage()
		if err != nil {
			t.Fatal(err)
		}
		updates = append(updates, language)
	})
	callResearch(t, s, "PATCH", "/interface", map[string]string{"language": "en"}, 200)
	callResearch(t, s, "PATCH", "/interface", map[string]string{"language": "invalid"}, 400)
	callResearch(t, s, "PATCH", "/interface", map[string]string{"language": "zh-Hans"}, 200)
	if len(updates) != 2 || updates[0] != "en" || updates[1] != "zh-Hans" {
		t.Fatal(updates)
	}
}
