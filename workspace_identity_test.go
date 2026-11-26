package main

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"slices"
	"testing"
)

func identityTestRoot(t *testing.T) (desktopRoots, string) {
	t.Helper()
	parent, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(parent, "Research")
	if err := os.Mkdir(path, 0700); err != nil {
		t.Fatal(err)
	}
	return desktopRoots{filepath.Join(parent, "registry")}, path
}

func TestRememberedWorkspaceMoveAndReplacement(t *testing.T) {
	roots, path := identityTestRoot(t)
	first, err := startRegisteredWorkspace(roots, rootChoice{dir: path, create: true}, 0, false)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(first.close)
	if err := roots.remember(path, first.binding); err != nil {
		t.Fatal(err)
	}
	remembered, err := roots.initial("")
	if err != nil || remembered.expected.ID != first.binding.ID || remembered.dir != path {
		t.Fatal(remembered, err)
	}
	moved := filepath.Join(filepath.Dir(path), "Relocated")
	if err := os.Rename(path, moved); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(path, 0700); err != nil {
		t.Fatal(err)
	}
	// Model a normally initialized workspace from a different installation.
	if err := markNewRoot(path); err != nil {
		t.Fatal(err)
	}
	if choice, err := roots.initial(""); !errors.Is(err, errWorkspaceReplaced) || choice.dir != "" {
		t.Fatal("startup selected a different directory entity", choice, err)
	}
	if _, err := startRegisteredWorkspace(roots, remembered, 0, false); !errors.Is(err, errWorkspaceReplaced) {
		t.Fatal("a pending startup changed directory identity", err)
	}
	if _, err := os.Stat(filepath.Join(path, ".studio-process.lock")); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("the rejected folder was initialized", err)
	}
	response, err := http.Get(first.address + "/api/health")
	if err != nil {
		t.Fatal(err)
	}
	_, _ = io.Copy(io.Discard, response.Body)
	_ = response.Body.Close()
	if response.StatusCode != http.StatusConflict {
		t.Fatal("old listener accepted a changed folder", response.StatusCode)
	}
	first.close()

	replacement, err := startRegisteredWorkspace(roots, rootChoice{dir: path}, 0, false)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(replacement.close)
	if replacement.binding.ID == first.binding.ID || replacement.address == first.address {
		t.Fatal("the selected replacement shared the previous scope or origin")
	}
	if err := roots.remember(path, replacement.binding); err != nil {
		t.Fatal(err)
	}
	choice, err := roots.initial("")
	if err != nil || choice.expected.ID != replacement.binding.ID {
		t.Fatal(choice, err)
	}

	recovered, err := startRegisteredWorkspace(roots, rootChoice{dir: moved}, 0, false)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(recovered.close)
	if recovered.binding.ID != first.binding.ID || recovered.address != first.address ||
		!slices.Contains(recovered.binding.Paths, path) || !slices.Contains(recovered.binding.Paths, moved) {
		t.Fatal("explicitly choosing the moved root lost its original scope or origin", recovered.binding, recovered.address)
	}
}

func TestLegacyRememberedWorkspaceRetainsCredentialAndOriginScope(t *testing.T) {
	for _, format := range []string{"path", "versioned"} {
		t.Run(format, func(t *testing.T) {
			roots, path := identityTestRoot(t)
			if err := markNewRoot(path); err != nil {
				t.Fatal(err)
			}
			id := rootID(path)
			port, err := roots.reserve(rootBinding{ID: id}, 0)
			if err != nil {
				t.Fatal(err)
			}
			var legacy any = path
			if format == "versioned" {
				legacy = map[string]any{"path": path, "identity": id, "version": 1, "future": map[string]bool{"keep": true}}
			}
			body, err := json.Marshal(legacy)
			if err != nil {
				t.Fatal(err)
			}
			file := filepath.Join(roots.dir, "last-workspace.json")
			if err := atomicFile(file, body); err != nil {
				t.Fatal(err)
			}
			choice, err := roots.initial("")
			if err != nil {
				t.Fatal(err)
			}
			migrated, err := startRegisteredWorkspace(roots, choice, 0, false)
			if err != nil {
				t.Fatal(err)
			}
			t.Cleanup(migrated.close)
			if migrated.binding.ID != id || migrated.api.rootIdentity() != id {
				t.Fatal("migration changed the identifier used for existing Keychain accounts", migrated.binding)
			}
			boundPort, err := roots.reserve(migrated.binding, 0)
			if err != nil || boundPort != port {
				t.Fatal("migration changed the port", boundPort, err)
			}
			recent, err := roots.readRecent()
			if err != nil || !recent.Bound || recent.Identity != id {
				t.Fatal(recent, err)
			}
			if format == "versioned" {
				data, err := os.ReadFile(file)
				if err != nil {
					t.Fatal(err)
				}
				var fields struct {
					Future map[string]bool
				}
				if json.Unmarshal(data, &fields) != nil || !fields.Future["keep"] {
					t.Fatal("migration dropped existing data", string(data))
				}
			}
			migrated.close()
			if err := os.Rename(path, path+" prior"); err != nil {
				t.Fatal(err)
			}
			if err := os.Mkdir(path, 0700); err != nil {
				t.Fatal(err)
			}
			if err := markNewRoot(path); err != nil {
				t.Fatal(err)
			}
			choice, err = roots.initial("")
			if !errors.Is(err, errWorkspaceReplaced) || choice.dir != "" {
				t.Fatal("upgraded recent record selected the wrong folder", choice, err)
			}
		})
	}
}
