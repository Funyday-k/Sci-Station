package workspace

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strings"
	"sync"
	"testing"
)

func projectDir(t *testing.T) string {
	t.Helper()
	dir, err := os.MkdirTemp("/private/tmp", "roundtable-workspace-test-")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.RemoveAll(dir) })
	return dir
}

func put(t *testing.T, project, path, text string, mode os.FileMode) {
	t.Helper()
	full := filepath.Join(project, path)
	if err := os.MkdirAll(filepath.Dir(full), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(full, []byte(text), mode); err != nil {
		t.Fatal(err)
	}
}

func TestValidateRequiresSpecificRealProject(t *testing.T) {
	project := projectDir(t)
	if got, err := Validate(project + "/"); err != nil || got != project {
		t.Fatalf("Validate = %q, %v", got, err)
	}
	home, _ := os.UserHomeDir()
	for _, path := range []string{"", ".", "/", home, filepath.Dir(home)} {
		if _, err := Validate(path); !errors.Is(err, ErrInvalid) {
			t.Errorf("Validate(%q) = %v", path, err)
		}
	}
	link := filepath.Join(project, "link")
	if err := os.Symlink(project, link); err != nil {
		t.Fatal(err)
	}
	if _, err := Validate(link); !errors.Is(err, ErrInvalid) {
		t.Fatalf("symlink project accepted: %v", err)
	}
}

func TestWritePreservesBytesModeAndVersions(t *testing.T) {
	project := projectDir(t)
	put(t, project, "run.sh", "#!/bin/sh\r\necho old\r\n", 0751)
	before, err := Read(project, "run.sh")
	if err != nil {
		t.Fatal(err)
	}
	text := "#!/bin/sh\r\necho 新值\r\n"
	change, err := Write(project, "run.sh", text, before.Version)
	if err != nil {
		t.Fatal(err)
	}
	if change.Before != before.Version || change.After != version([]byte(text)) || change.Path != "run.sh" {
		t.Fatalf("wrong change: %+v", change)
	}
	if !strings.Contains(change.Diff, "-echo old\r\n+echo 新值\r\n") {
		t.Fatalf("incorrect diff: %q", change.Diff)
	}
	actual, _ := os.ReadFile(filepath.Join(project, "run.sh"))
	if string(actual) != text {
		t.Fatalf("line endings changed: %q", actual)
	}
	info, _ := os.Stat(filepath.Join(project, "run.sh"))
	if info.Mode().Perm() != 0751 {
		t.Fatalf("mode = %o", info.Mode().Perm())
	}
	after, err := Read(project, "run.sh")
	if err != nil || after.Version != change.After || after.Text != text {
		t.Fatalf("read after save: %+v %v", after, err)
	}
	entries, _ := os.ReadDir(project)
	if len(entries) != 1 {
		t.Fatalf("staging artifacts left behind: %v", entries)
	}
}

func TestMissingFileCreationAndStaleMissingVersion(t *testing.T) {
	project := projectDir(t)
	if err := os.Mkdir(filepath.Join(project, "src"), 0755); err != nil {
		t.Fatal(err)
	}
	file, err := Read(project, "src/new.go")
	if err != nil || file.Version != MissingVersion || file.Text != "" || file.Path != "src/new.go" {
		t.Fatalf("missing: %+v %v", file, err)
	}
	change, err := Write(project, file.Path, "package sample\n", file.Version)
	if err != nil {
		t.Fatal(err)
	}
	if change.Before != MissingVersion || !strings.Contains(change.Diff, "@@ -0,0 +1,1 @@") {
		t.Fatalf("creation change: %+v", change)
	}
	if _, err := Write(project, file.Path, "overwrite", MissingVersion); !errors.Is(err, ErrConflict) {
		t.Fatalf("stale creation: %v", err)
	}
	if _, err := Write(project, "absent/new.go", "package sample\n", MissingVersion); !errors.Is(err, ErrInvalid) {
		t.Fatalf("missing parent: %v", err)
	}
	if _, err := os.Stat(filepath.Join(project, "absent")); !os.IsNotExist(err) {
		t.Fatal("created unauthorized parent directory")
	}
}

func TestExternalEditAndDeletionCauseConflict(t *testing.T) {
	project := projectDir(t)
	put(t, project, "file.txt", "original\n", 0644)
	file, _ := Read(project, "file.txt")
	put(t, project, "file.txt", "external\n", 0644)
	if _, err := Write(project, "file.txt", "agent\n", file.Version); !errors.Is(err, ErrConflict) {
		t.Fatalf("external change: %v", err)
	}
	actual, _ := os.ReadFile(filepath.Join(project, "file.txt"))
	if string(actual) != "external\n" {
		t.Fatal("overwrote external edit")
	}
	if err := os.Remove(filepath.Join(project, "file.txt")); err != nil {
		t.Fatal(err)
	}
	if _, err := Write(project, "file.txt", "agent\n", file.Version); !errors.Is(err, ErrConflict) {
		t.Fatalf("external deletion: %v", err)
	}
}

func TestConcurrentWritersAllowOneCommit(t *testing.T) {
	project := projectDir(t)
	put(t, project, "file.txt", "base\n", 0644)
	file, _ := Read(project, "file.txt")
	start := make(chan struct{})
	results := make(chan error, 20)
	var wg sync.WaitGroup
	for i := range 20 {
		wg.Add(1)
		go func(index int) {
			defer wg.Done()
			<-start
			_, err := Write(project, "file.txt", fmt.Sprintf("writer %d\n", index), file.Version)
			results <- err
		}(i)
	}
	close(start)
	wg.Wait()
	close(results)
	success, conflicts := 0, 0
	for err := range results {
		if err == nil {
			success++
		} else if errors.Is(err, ErrConflict) {
			conflicts++
		} else {
			t.Fatal(err)
		}
	}
	if success != 1 || conflicts != 19 {
		t.Fatalf("success=%d conflict=%d", success, conflicts)
	}
}

func TestProcessWriterHelper(t *testing.T) {
	if os.Getenv("ROUNDTABLE_WORKSPACE_HELPER") != "1" {
		return
	}
	_, err := Write(os.Getenv("ROUNDTABLE_WORKSPACE_PROJECT"), "file.txt", os.Getenv("ROUNDTABLE_WORKSPACE_TEXT"), os.Getenv("ROUNDTABLE_WORKSPACE_VERSION"))
	if err == nil {
		fmt.Print("saved")
		os.Exit(0)
	}
	if errors.Is(err, ErrConflict) {
		fmt.Print("conflict")
		os.Exit(0)
	}
	fmt.Print(err)
	os.Exit(2)
}

func TestConcurrentProcessesAllowOneCommit(t *testing.T) {
	project := projectDir(t)
	put(t, project, "file.txt", "base\n", 0644)
	file, _ := Read(project, "file.txt")
	results := make(chan string, 2)
	for i := range 2 {
		go func(index int) {
			cmd := exec.Command(os.Args[0], "-test.run=^TestProcessWriterHelper$")
			cmd.Env = append(os.Environ(), "ROUNDTABLE_WORKSPACE_HELPER=1", "ROUNDTABLE_WORKSPACE_PROJECT="+project, "ROUNDTABLE_WORKSPACE_VERSION="+file.Version, fmt.Sprintf("ROUNDTABLE_WORKSPACE_TEXT=process %d\n", index))
			output, err := cmd.CombinedOutput()
			if err != nil {
				results <- "error: " + string(output)
				return
			}
			results <- string(output)
		}(i)
	}
	got := []string{<-results, <-results}
	if (got[0] != "saved" || got[1] != "conflict") && (got[1] != "saved" || got[0] != "conflict") {
		t.Fatalf("process results: %q", got)
	}
}

func TestRejectUnsafePathsAndSymlinks(t *testing.T) {
	project, outside := projectDir(t), projectDir(t)
	put(t, outside, "outside.txt", "private\n", 0644)
	put(t, project, "real/file.txt", "safe\n", 0644)
	for link, target := range map[string]string{"external": outside, "internal": "real", "file.txt": filepath.Join(outside, "outside.txt")} {
		if err := os.Symlink(target, filepath.Join(project, link)); err != nil {
			t.Fatal(err)
		}
	}
	for _, path := range []string{"../outside.txt", "/etc/passwd", "real/../file.txt", "real//file.txt", ".git/config", ".env", "node_modules/x.js", "credentials.json", "key.pem", "external/outside.txt", "internal/file.txt", "file.txt", "real\\file.txt", "real/file.txt\n"} {
		if _, err := Read(project, path); !errors.Is(err, ErrInvalid) {
			t.Errorf("Read(%q) = %v", path, err)
		}
		if _, err := Write(project, path, "changed\n", MissingVersion); !errors.Is(err, ErrInvalid) {
			t.Errorf("Write(%q) = %v", path, err)
		}
	}
	data, _ := os.ReadFile(filepath.Join(outside, "outside.txt"))
	if string(data) != "private\n" {
		t.Fatal("outside target modified")
	}
}

func TestCatalogOnlyVisibleEditableUTF8Files(t *testing.T) {
	project := projectDir(t)
	for path, content := range map[string]string{
		"README.md": "hello\n", "src/main.go": "package main\n", "go.mod": "module sample\n", "notes.txt": "中文\r\n", ".env": "KEY=secret", ".git/config": "private", "node_modules/x.js": "dependency", "build/generated.go": "generated", "credentials.json": "secret", "assets/image.png": "image", "binary.go": "a\x00b", "bad.txt": "\xff", "control.txt": "a\x01b", "oversized.txt": strings.Repeat("a", MaxFileBytes+1),
	} {
		put(t, project, path, content, 0644)
	}
	if err := os.Symlink("src", filepath.Join(project, "alias")); err != nil {
		t.Fatal(err)
	}
	got, err := Catalog(project)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"README.md", "go.mod", "notes.txt", "src/main.go"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("catalog = %q, want %q", got, want)
	}
	for _, path := range []string{"binary.go", "bad.txt", "control.txt", "oversized.txt"} {
		if _, err := Read(project, path); !errors.Is(err, ErrInvalid) {
			t.Errorf("Read(%s) = %v", path, err)
		}
	}
}

func TestInvalidTextAndVersionDoNotWrite(t *testing.T) {
	project := projectDir(t)
	for _, test := range []struct{ text, version string }{{"bad\x00text", MissingVersion}, {"\xff", MissingVersion}, {strings.Repeat("x", MaxFileBytes+1), MissingVersion}, {"valid", ""}, {"valid", "unknown"}} {
		if _, err := Write(project, "new.txt", test.text, test.version); !errors.Is(err, ErrInvalid) {
			t.Errorf("Write returned %v", err)
		}
	}
	if _, err := os.Stat(filepath.Join(project, "new.txt")); !os.IsNotExist(err) {
		t.Fatal("invalid write created file")
	}
}

func TestNoOpDoesNotReplaceFile(t *testing.T) {
	project := projectDir(t)
	put(t, project, "file.txt", "without newline", 0600)
	beforeInfo, _ := os.Stat(filepath.Join(project, "file.txt"))
	before, _ := Read(project, "file.txt")
	change, err := Write(project, "file.txt", before.Text, before.Version)
	if err != nil || change.Diff != "" || change.Before != change.After {
		t.Fatalf("no-op change: %+v %v", change, err)
	}
	afterInfo, _ := os.Stat(filepath.Join(project, "file.txt"))
	if !os.SameFile(beforeInfo, afterInfo) {
		t.Fatal("no-op replaced inode")
	}
}

func TestUnifiedDiffHandlesMissingNewlineAndEmptyFiles(t *testing.T) {
	got, err := unifiedDiff("file.txt", "old", "new\n")
	if err != nil {
		t.Fatal(err)
	}
	want := "--- a/file.txt\n+++ b/file.txt\n@@ -1,1 +1,1 @@\n-old\n\\ No newline at end of file\n+new\n"
	if got != want {
		t.Fatalf("diff = %q", got)
	}
	if got, err := unifiedDiff("file.txt", "one\n", ""); err != nil || !strings.Contains(got, "@@ -1,1 +0,0 @@\n-one\n") {
		t.Fatalf("empty diff: %q", got)
	}
	if got, err := unifiedDiff("file.txt", "same\n", "same\n"); err != nil || got != "" {
		t.Fatalf("identical diff: %q", got)
	}
}
