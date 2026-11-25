package workspace

import (
	"errors"
	"io"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func TestMaterialsShowActualProjectFilesAndRestrictPreview(t *testing.T) {
	project := projectDir(t)
	other := projectDir(t)
	put(t, project, "code/analysis.py", "print('work')\n", 0600)
	put(t, project, "code/view.html", "<script>noop()</script>", 0600)
	put(t, project, "code/.private.py", "hidden", 0600)
	put(t, project, "code/nested/.env", "token", 0600)
	put(t, project, "code/credentials.txt", "token", 0600)
	put(t, project, "code/plain.txt", strings.Repeat("x", MaxMaterialTextBytes+1), 0600)
	put(t, project, "data/spectrum.npy", "\x93NUMPY\x00", 0600)
	put(t, project, "figures/plot.png", "\x89PNG\r\n\x1a\n", 0600)
	put(t, project, "figures/masquerade.png", "<svg></svg>", 0600)
	put(t, project, "outputs/report.pdf", "%PDF-1.7\n", 0600)
	put(t, project, "notes/unlisted.md", "not in the materials collections", 0600)
	put(t, other, "other.py", "outside the project", 0600)
	if err := os.Symlink(filepath.Join(other, "other.py"), filepath.Join(project, "code/link.py")); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(other, filepath.Join(project, "code/linked-folder")); err != nil {
		t.Fatal(err)
	}

	catalog, err := MaterialCatalog(project)
	if err != nil {
		t.Fatal(err)
	}
	kinds := map[string]string{}
	for _, item := range catalog {
		kinds[item.Path] = item.Kind
	}
	want := map[string]string{
		"code/analysis.py": "python", "code/view.html": "text", "code/plain.txt": "text",
		"data/spectrum.npy": "data", "figures/plot.png": "image", "figures/masquerade.png": "image", "outputs/report.pdf": "pdf",
	}
	if !reflect.DeepEqual(kinds, want) {
		t.Fatalf("wrong material inventory: %v", kinds)
	}

	for path, mediaType := range map[string]string{
		"code/analysis.py": "text/plain; charset=utf-8", "code/view.html": "text/plain; charset=utf-8",
		"figures/plot.png": "image/png", "outputs/report.pdf": "application/pdf",
	} {
		f, file, got, err := MaterialPreview(project, path)
		if err != nil {
			t.Fatal(err)
		}
		data, err := io.ReadAll(f)
		f.Close()
		original, originalErr := os.ReadFile(filepath.Join(project, path))
		if err != nil || originalErr != nil || file.Path != path || got != mediaType || string(data) != string(original) {
			t.Errorf("preview changed %s: %q, %q: %v", path, got, data, err)
		}
	}
	for _, path := range []string{
		"code/.private.py", "code/credentials.txt", "code/plain.txt", "code/link.py", "code/linked-folder/other.py",
		"code/../notes/unlisted.md", "notes/unlisted.md", "data/spectrum.npy", "figures/masquerade.png",
	} {
		if f, _, _, err := MaterialPreview(project, path); !errors.Is(err, ErrInvalid) {
			if f != nil {
				f.Close()
			}
			t.Errorf("preview unexpectedly allowed %s: %v", path, err)
		}
	}
	got, item, err := MaterialLocation(project, "data/spectrum.npy")
	if err != nil || got != filepath.Join(project, "data", "spectrum.npy") || item.Kind != "data" {
		t.Fatalf("binary material could not be opened in its default app: %q, %+v, %v", got, item, err)
	}
}
