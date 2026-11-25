package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"scistation.local/desktop/internal/plugins"
)

func TestPluginCLIPackAndValidate(t *testing.T) {
	dir := t.TempDir()
	manifestPath, modulePath := filepath.Join(dir, "manifest.json"), filepath.Join(dir, "module.wasm")
	packagePath := filepath.Join(dir, "plugin.json")
	writePluginCLITestFile(t, manifestPath, []byte(`{
  "schema_version": 1,
  "id": "org.example.counter",
  "name": "Counter",
  "version": "1.0.0",
  "author": "Example",
  "description": "Count public turns",
  "contributions": {"actions": [{"id": "count", "label": "Count", "input": "public_turns", "format": "text"}]}
}`))
	// The fixture exports memory, alloc(i32) -> i32 and run(i32, i32) -> i64.
	module, err := hex.DecodeString("0061736d01000000010c0260017f017f60027f7f017e03030200010503010001071803066d656d6f7279020005616c6c6f6300000372756e00010a0b02040041000b040042000b")
	if err != nil {
		t.Fatal(err)
	}
	writePluginCLITestFile(t, modulePath, module)
	pack := []string{"pack", "--manifest", manifestPath, "--module", modulePath, "--out", packagePath}
	assertPluginCLIStatus(t, 0, pack...)
	packaged, err := os.ReadFile(packagePath)
	if err != nil {
		t.Fatal(err)
	}
	manifest, err := plugins.ParsePackage(packaged)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(manifest.Module, module) {
		t.Fatal("pack did not preserve the module bytes")
	}
	output := assertPluginCLIStatus(t, 0, "validate", packagePath)
	if !strings.Contains(output, "org.example.counter 1.0.0") || !strings.Contains(output, fmt.Sprintf("%x", sha256.Sum256(packaged))) {
		t.Fatalf("validate did not print the package identity and digest: %s", output)
	}
	assertPluginCLIStatus(t, 1, pack...)
	unchanged, err := os.ReadFile(packagePath)
	if err != nil || !bytes.Equal(packaged, unchanged) {
		t.Fatalf("existing package was altered after retry: %v", err)
	}
	duplicate, err := os.ReadFile(manifestPath)
	if err != nil {
		t.Fatal(err)
	}
	duplicate = bytes.Replace(duplicate, []byte(`"version": "1.0.0"`), []byte(`"version": "2.0.0", "version": "1.0.0"`), 1)
	writePluginCLITestFile(t, manifestPath, duplicate)
	incompletePath := filepath.Join(dir, "incomplete.json")
	assertPluginCLIStatus(t, 1, "pack", "--manifest", manifestPath, "--module", modulePath, "--out", incompletePath)
	if _, err := os.Stat(incompletePath); !os.IsNotExist(err) {
		t.Fatalf("failed pack left an output file: %v", err)
	}
}

func TestPluginCLICatalog(t *testing.T) {
	dir := t.TempDir()
	first := filepath.Join(dir, "first plugin.json")
	second := filepath.Join(dir, "second.json")
	for path, id := range map[string]string{first: "org.example.first", second: "org.example.second"} {
		manifestPath := path + ".manifest"
		writePluginCLITestFile(t, manifestPath, []byte(fmt.Sprintf(`{
  "schema_version": 1,
  "id": %q,
  "name": "Checklist",
  "version": "1.0.0",
  "author": "Example",
  "description": "Summarize evidence",
  "contributions": {"round_guidance": "Check the evidence."}
}`, id)))
		assertPluginCLIStatus(t, 0, "pack", "--manifest", manifestPath, "--out", path)
	}
	catalogPath := filepath.Join(dir, "catalog.json")
	reorderedPath := filepath.Join(dir, "catalog-reordered.json")
	assertPluginCLIStatus(t, 0, "catalog", "--name", "Example catalog", "--out", catalogPath, first, second)
	assertPluginCLIStatus(t, 0, "catalog", "--name", "Example catalog", "--out", reorderedPath, second, first)
	data, err := os.ReadFile(catalogPath)
	if err != nil {
		t.Fatal(err)
	}
	reordered, err := os.ReadFile(reorderedPath)
	if err != nil || !bytes.Equal(data, reordered) {
		t.Fatalf("catalog changed with input order: %v", err)
	}
	catalog, err := plugins.ParseCatalog(data, "https://example.com/sub/catalog.json")
	if err != nil {
		t.Fatal(err)
	}
	if len(catalog.Plugins) != 2 || catalog.Name != "Example catalog" {
		t.Fatalf("unexpected catalog: %+v", catalog)
	}
	packageBytes, err := os.ReadFile(first)
	if err != nil {
		t.Fatal(err)
	}
	entry := catalog.Plugins[0]
	if entry.ID != "org.example.first" || entry.URL != "https://example.com/sub/first%20plugin.json" || entry.SHA256 != fmt.Sprintf("%x", sha256.Sum256(packageBytes)) {
		t.Fatalf("unexpected published entry: %+v", entry)
	}
	assertPluginCLIStatus(t, 1, "catalog", "--name", "New name", "--out", catalogPath, first)
	unchanged, err := os.ReadFile(catalogPath)
	if err != nil || !bytes.Equal(data, unchanged) {
		t.Fatalf("existing catalog was altered after retry: %v", err)
	}
	failurePath := filepath.Join(dir, "catalog-failure.json")
	assertPluginCLIStatus(t, 1, "catalog", "--name", "Example catalog", "--out", failurePath, first, first)
	assertPluginCLIStatus(t, 1, "catalog", "--name", "Example catalog", "--out", failurePath, first, filepath.Join(dir, "missing.json"))
	assertPluginCLIStatus(t, 1, "catalog", "--name", "Example catalog", "--out", filepath.Join(t.TempDir(), "catalog.json"), first)
	if _, err := os.Stat(failurePath); !os.IsNotExist(err) {
		t.Fatalf("failed command left an output file: %v", err)
	}
}

func TestPluginCLIRejectsOversizedPackage(t *testing.T) {
	path := filepath.Join(t.TempDir(), "oversized.json")
	writePluginCLITestFile(t, path, nil)
	if err := os.Truncate(path, plugins.MaxPackageBytes+1); err != nil {
		t.Fatal(err)
	}
	output := assertPluginCLIStatus(t, 1, "validate", path)
	if !strings.Contains(output, "上限") {
		t.Fatalf("validate did not identify the size limit: %s", output)
	}
}

func assertPluginCLIStatus(t *testing.T, want int, args ...string) string {
	t.Helper()
	var stdout, stderr bytes.Buffer
	if got := runPluginCLI(args, &stdout, &stderr); got != want {
		t.Fatalf("plugin %v = %d, want %d\nstdout: %s\nstderr: %s", args, got, want, &stdout, &stderr)
	}
	if want != 0 {
		return stderr.String()
	}
	return stdout.String()
}

func writePluginCLITestFile(t *testing.T, path string, data []byte) {
	t.Helper()
	if err := os.WriteFile(path, data, 0600); err != nil {
		t.Fatal(err)
	}
}
