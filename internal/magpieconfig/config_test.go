package magpieconfig

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"testing"
)

func TestLocalModelSelection(t *testing.T) {
	home := t.TempDir()
	config := filepath.Join(home, ".config")
	t.Setenv("HOME", home)
	t.Setenv("XDG_CONFIG_HOME", config)
	write := func(path string, value any) {
		t.Helper()
		if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
			t.Fatal(err)
		}
		b, err := json.Marshal(value)
		if err != nil {
			t.Fatal(err)
		}
		if err = os.WriteFile(path, b, 0600); err != nil {
			t.Fatal(err)
		}
	}
	spec := filepath.Join(home, "Fixture.app", "Contents", "Resources", AgentFile)
	write(spec, "test adapter")
	write(filepath.Join(config, "magpie", "plugins.json"), map[string][]Entry{"plugins": {{Spec: spec}}})
	for _, test := range []struct {
		name, address, legacyIdentity string
		want                          error
	}{
		{"model and address", "http://127.0.0.1:4242/v1", "", nil},
		{"original public identity", "http://localhost:4242/v1", "magpie-sci-station", nil},
		{"other identity", "http://localhost:4242/v1", "private-test-value", ErrCustomKey},
		{"external address", "https://example.invalid/v1", "", ErrConfig},
	} {
		t.Run(test.name, func(t *testing.T) {
			fields := map[string]string{"baseURL": test.address, "model": "fixture/model"}
			if test.legacyIdentity != "" {
				fields["gatewayKey"] = test.legacyIdentity
			}
			write(filepath.Join(config, AgentID, "connection.json"), fields)
			got, err := Load(3425)
			if !errors.Is(err, test.want) || got.Connected != (test.want == nil) {
				t.Fatalf("connected=%v, err=%v", got.Connected, err)
			}
			if got.Connected && (got.Model != "fixture/model" || got.Port != 4242) {
				t.Fatalf("unexpected connection: %+v", got)
			}
		})
	}
}
