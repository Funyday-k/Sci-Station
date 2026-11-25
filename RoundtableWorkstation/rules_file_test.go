package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"scistation.local/desktop/internal/deliberation"
)

func TestRulesMarkdownContainsCurrentCatalogInstructions(t *testing.T) {
	catalog := deliberation.Catalog()
	got := string(rulesMarkdown(catalog))
	if !strings.HasPrefix(got, "# 圆桌讨论规则\n") {
		t.Fatalf("missing readable document title: %q", got[:min(len(got), 100)])
	}
	for _, preset := range catalog {
		if !strings.Contains(got, "## "+preset.Label) {
			t.Errorf("document missing preset %q", preset.Label)
		}
		for _, phase := range preset.Phases {
			if !strings.Contains(got, "### "+phase.Label) || !strings.Contains(got, strings.TrimSpace(phase.Instructions)) {
				t.Errorf("document missing current instructions for %s/%s", preset.ID, phase.ID)
			}
		}
	}
}

func TestWriteRulesFileRefreshesReadOnlyFile(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, rulesFileName)
	if err := os.WriteFile(path, []byte("old"), 0600); err != nil {
		t.Fatal(err)
	}
	want := []byte("new current rules\n")
	if err := writeRulesFile(path, want); err != nil {
		t.Fatal(err)
	}
	got, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != string(want) {
		t.Fatalf("file contents = %q, want %q", got, want)
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm()&0222 != 0 {
		t.Errorf("reference file is writable: mode %o", info.Mode().Perm())
	}
}
