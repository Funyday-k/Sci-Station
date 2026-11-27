package desktop

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestDesktopDataLocationStartupAndExplicitPrecedence(t *testing.T) {
	roots, custom := identityTestRoot(t)
	customChoice, err := roots.desktopInitial(custom)
	if err != nil || customChoice.dir != custom || !customChoice.create || customChoice.rememberDefault {
		t.Fatal(customChoice, err)
	}
	if _, err := os.Stat(roots.defaultDataDir()); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("explicit startup initialized default data", err)
	}
	headless, err := roots.initial("")
	if err != nil || headless.dir != "" {
		t.Fatal("headless process silently selected a new folder", headless, err)
	}
	choice, err := roots.desktopInitial("")
	if err != nil || choice.dir != roots.defaultDataDir() || !choice.create || !choice.rememberDefault {
		t.Fatal(choice, err)
	}
	initial, err := startRegisteredWorkspace(roots, choice, 0, false)
	if err != nil {
		t.Fatal(err)
	}
	defer initial.close()
	if roots.windowTitle(initial) != "Sci-Station" {
		t.Fatal(roots.windowTitle(initial))
	}
	if choice, err = roots.desktopInitial(""); err != nil || choice.expected.ID != initial.binding.ID || choice.create {
		t.Fatal(choice, err)
	}
	explicit, err := startRegisteredWorkspace(roots, customChoice, 0, false)
	if err != nil {
		t.Fatal(err)
	}
	defer explicit.close()
	if choice, err = roots.initial(""); err != nil || choice.expected.ID != initial.binding.ID {
		t.Fatal("headless data override changed recent selection", choice, err)
	}
	if err := roots.remember(custom, explicit.binding); err != nil {
		t.Fatal(err)
	}
	if choice, err = roots.desktopInitial(""); err != nil || choice.dir != custom {
		t.Fatal(choice, err)
	}
	if !strings.HasSuffix(roots.windowTitle(explicit), filepath.Base(custom)) {
		t.Fatal(roots.windowTitle(explicit))
	}
	// An earlier concurrent startup must not overwrite this newer selection.
	if err = roots.refreshRecent(rootChoice{rememberDefault: true}, initial); err != nil {
		t.Fatal(err)
	}
	if choice, err = roots.initial(""); err != nil || choice.dir != custom {
		t.Fatal("default publication superseded an explicit selection", choice, err)
	}
}

func TestDesktopDataLocationRecoveryKeepsExistingRecords(t *testing.T) {
	roots, missing := identityTestRoot(t)
	if err := os.Remove(missing); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(roots.dir, 0700); err != nil {
		t.Fatal(err)
	}
	missingRecord, err := json.Marshal(missing)
	if err != nil {
		t.Fatal(err)
	}
	for _, previous := range []string{string(missingRecord), "damaged"} {
		if err := os.WriteFile(filepath.Join(roots.dir, "last-workspace.json"), []byte(previous), 0600); err != nil {
			t.Fatal(err)
		}
		choice, issue := roots.desktopInitial("")
		if issue == nil {
			if choice.dir != missing || choice.create || choice.rememberDefault {
				t.Fatal("silently selected another data folder", choice)
			}
			if _, err := startRegisteredWorkspace(roots, choice, 0, false); !errors.Is(err, os.ErrNotExist) {
				t.Fatal("expected missing remembered folder to fail on open", err)
			}
		} else if choice.dir != "" {
			t.Fatal("selected a data folder from a damaged record", choice, issue)
		}
		for _, path := range []string{roots.defaultDataDir(), missing} {
			if _, err := os.Stat(path); !errors.Is(err, os.ErrNotExist) {
				t.Fatal("initialized a missing data folder", path, err)
			}
		}
	}
	if err := os.Remove(filepath.Join(roots.dir, "last-workspace.json")); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(roots.defaultDataDir(), 0700); err != nil {
		t.Fatal(err)
	}
	sentinel := filepath.Join(roots.defaultDataDir(), "previous-notes.txt")
	if err := os.WriteFile(sentinel, []byte("keep"), 0600); err != nil {
		t.Fatal(err)
	}
	choice, err := roots.desktopInitial("")
	if err != nil || choice.create {
		t.Fatal(choice, err)
	}
	if _, err := startRegisteredWorkspace(roots, choice, 0, false); err == nil {
		t.Fatal("opened unrecognized nonempty data")
	}
	if data, err := os.ReadFile(sentinel); err != nil || string(data) != "keep" {
		t.Fatal(string(data), err)
	}
	if _, err := storageFolderChoice(missing); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("recreated folder after it disappeared from a native picker", err)
	}
}

func TestDataLocationSettingsRenderAndNativeActions(t *testing.T) {
	roots, custom := identityTestRoot(t)
	t.Setenv("SCI_STATION_WORKSPACE_REGISTRY", roots.dir)
	api := openNavigationFixture(t, custom)
	api.workspaceDir = custom
	api.desktop = true
	page := navigationRequest(t, api, "GET", "/studio?view=settings", "", 200).Body.String()
	for _, text := range []string{custom, filepath.Join(custom, "research", "library"), roots.defaultDataDir(), `id="storage-choose"`, `id="storage-reveal"`} {
		if !strings.Contains(page, text) {
			t.Fatal("storage page missing", text)
		}
	}
	api.desktop = false
	page = navigationRequest(t, api, "GET", "/studio?view=settings", "", 200).Body.String()
	if strings.Contains(page, `id="storage-choose"`) || !strings.Contains(page, custom) {
		t.Fatal("headless settings did not distinguish paths and desktop actions")
	}
	rootFixtureRequest(t, api, "POST", "/api/workspace/choose-storage", struct{}{}, 409, nil)
	rootFixtureRequest(t, api, "POST", "/api/workspace/default-storage", struct{}{}, 409, nil)
	rootFixtureRequest(t, api, "POST", "/api/workspace/choose-storage", map[string]string{"path": custom}, 400, nil)
}
