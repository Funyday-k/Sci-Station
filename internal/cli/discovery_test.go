package cli

import (
	"os"
	"path/filepath"
	"testing"
)

func mockCLI(t *testing.T, body string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "mock-client")
	if err := os.WriteFile(path, []byte("#!/bin/sh\nset -eu\n"+body+"\n"), 0700); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestDiscoverExplicitOverride(t *testing.T) {
	path := mockCLI(t, "exit 0")
	info := Discover("codex", path)
	if !info.Available || info.Path != path {
		t.Fatalf("unexpected executable discovery: %#v", info)
	}
	if Discover("codex", path+"-missing").Available {
		t.Fatal("missing explicit override fell back to another executable")
	}
	if Discover("other", path).Available {
		t.Fatal("unknown seat must not be available")
	}
}

func TestDiscoverWithFinderPath(t *testing.T) {
	home := t.TempDir()
	bin := filepath.Join(home, ".local", "bin")
	if err := os.MkdirAll(bin, 0700); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(bin, "agent")
	if err := os.WriteFile(path, []byte("#!/bin/sh\nexit 0\n"), 0700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("HOME", home)
	t.Setenv("PATH", "")
	if info := Discover("cursor", ""); !info.Available || info.Path != path {
		t.Fatalf("Finder launch discovery failed: %#v", info)
	}
}
