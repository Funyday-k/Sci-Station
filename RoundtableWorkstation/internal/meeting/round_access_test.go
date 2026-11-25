package meeting

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"

	"scistation.local/desktop/internal/deliberation"
)

func TestRoundWritePermissionUsesTheSavedEffectiveValue(t *testing.T) {
	allow, deny := true, false
	cases := []struct {
		name, preset string
		global       bool
		requested    *bool
		want         bool
	}{
		{name: "legacy project collaboration", preset: "work", global: true, want: true},
		{name: "project collaboration read-only", preset: "work", global: true, requested: &deny},
		{name: "project collaboration writable", preset: "work", global: true, requested: &allow, want: true},
		{name: "global limit", preset: "work", requested: &allow},
		{name: "preset limit", preset: "review", global: true, requested: &allow},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			var global atomic.Bool
			global.Store(tc.global)
			var calls int
			call := func(ctx context.Context, _, _, prompt, _ string) (string, error) {
				calls++
				switch calls {
				case 1:
					global.Store(!tc.global)
					rules := deliberation.InstructionsFrom(ctx)
					if strings.Contains(rules, `{"action":"write"`) != tc.want {
						t.Error("write action in instructions disagrees with the effective permission")
					}
					if strings.Contains(prompt, `"allow_edits":true`) != tc.want {
						t.Error("model context disagrees with the effective permission")
					}
					return `{"action":"read","path":"test.md"}`, nil
				case 2:
					return `{"action":"write","path":"test.md","text":"changed"}`, nil
				default:
					if strings.Contains(prompt, "edits are disabled for this round") == tc.want {
						t.Error("write feedback disagrees with the effective permission")
					}
					return say("complete"), nil
				}
			}
			engine, err := New(tempDir(t), call, func() Settings {
				settings := testSettings()
				settings.AllowEdits = global.Load()
				return settings
			})
			if err != nil {
				t.Fatal(err)
			}
			project := tempDir(t)
			s, err := engine.Create("Round permission", project, []string{"codex"})
			if err != nil {
				t.Fatal(err)
			}
			started, err := engine.StartRound(s.ID, "", "", 0, RoundOptions{Preset: tc.preset, AllowEdits: tc.requested})
			if err != nil {
				t.Fatal(err)
			}
			final := settled(t, engine, s.ID)
			if started.Rounds[0].Settings.AllowEdits != tc.want || final.Rounds[0].Settings.AllowEdits != tc.want || final.Status != "ready" {
				t.Fatalf("unexpected persisted round: %+v", final.Rounds[0])
			}
			text, err := os.ReadFile(filepath.Join(project, "test.md"))
			if tc.want {
				if err != nil || string(text) != "changed" || len(final.Operations) != 1 {
					t.Fatalf("authorized write was not applied: %q, %v", text, err)
				}
			} else if !os.IsNotExist(err) || len(final.Operations) != 0 {
				t.Fatalf("read-only round touched the file or write journal: %q, %v", text, err)
			}
		})
	}
}
