package credentials

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestAccountUsesCanonicalDataDirectory(t *testing.T) {
	root := t.TempDir()
	first := filepath.Join(root, "first")
	second := filepath.Join(root, "second")
	link := filepath.Join(root, "alias")
	for _, dir := range []string{first, second} {
		if err := os.Mkdir(dir, 0700); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.Symlink(first, link); err != nil {
		t.Fatal(err)
	}
	original, err := accountForDirectory(first)
	if err != nil || !strings.HasPrefix(original, "mineru:") || strings.Contains(original, root) {
		t.Fatalf("expected an opaque MinerU account: %v", err)
	}
	alias, err := accountForDirectory(link)
	if err != nil || alias != original {
		t.Fatalf("same data directory must reopen its existing credential: %v", err)
	}
	other, err := accountForDirectory(second)
	if err != nil || other == original {
		t.Fatalf("different data directories must have independent credentials: %v", err)
	}
}
