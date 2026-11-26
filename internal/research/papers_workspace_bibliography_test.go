package research

import (
	"bytes"
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestWorkspaceLibraryPreferencesAndDefaultImport(t *testing.T) {
	lib := testPaperLib(t)
	id := collectionFixture(t, lib, 0, "", "Physics")
	body := `{"revision":1,"operation":"set_library_preferences","library":{"default_collection":"` + id +
		`","visible_columns":["year","title","doi"],"sort_column":"year","sort_descending":true}}`
	response := testPaperRequest(t, lib, http.MethodPatch, "/organization", body)
	if response.Code != http.StatusOK {
		t.Fatal(response.Code, response.Body.String())
	}
	bad := testPaperRequest(t, lib, http.MethodPatch, "/organization",
		`{"revision":2,"operation":"set_library_preferences","library":{"visible_columns":["title","title"]}}`)
	if bad.Code != http.StatusBadRequest {
		t.Fatal(bad.Code, bad.Body.String())
	}
	preview := testPaperRequest(t, lib, http.MethodPost, "/preview", `{"title":"Suggested"}`)
	if preview.Code != http.StatusOK || !strings.Contains(preview.Body.String(), id) {
		t.Fatal(preview.Code, preview.Body.String())
	}
	for _, fixture := range []struct{ body, collection string }{
		{`{"title":"Default fixture","citekey":"AutoKey"}`, id},
		{`{"title":"Explicitly unfiled","collection_id":"","citekey":"ExplicitKey"}`, ""},
	} {
		result := testPaperRequest(t, lib, http.MethodPost, "", fixture.body)
		var paper Paper
		if result.Code != http.StatusCreated || json.Unmarshal(result.Body.Bytes(), &paper) != nil ||
			paper.CollectionID != fixture.collection {
			t.Fatal(result.Code, result.Body.String())
		}
	}
	reopened, err := NewPaperLibrary(lib.dir)
	if err != nil {
		t.Fatal(err)
	}
	prefs, _, err := reopened.readOrganization()
	if err != nil || strings.Join(prefs.Library.VisibleColumns, ",") != "year,title,doi" ||
		prefs.Library.DefaultCollection != id || prefs.Library.SortColumn != "year" || !prefs.Library.SortDescending {
		t.Fatal(prefs, err)
	}
	bibtex := testPaperRequest(t, reopened, http.MethodGet, "/bibliography", "")
	if bibtex.Code != http.StatusOK || !strings.Contains(bibtex.Body.String(), "@misc{AutoKey,") ||
		!strings.Contains(bibtex.Body.String(), "@misc{ExplicitKey,") {
		t.Fatal(bibtex.Code, bibtex.Body.String())
	}
}

func TestWorkspaceBibliographyPreservesUserBytesAndRejectsMalformedImport(t *testing.T) {
	lib := testPaperLib(t)
	path := filepath.Join(lib.dir, "refs", libraryBibliographyName)
	if err := os.Mkdir(filepath.Dir(path), 0700); err != nil {
		t.Fatal(err)
	}
	user := []byte(`% user-owned @misc{NewKey, a comment}
@string(monthName = "November")
@article ( UserKey, title = {User's title}, month = monthName, custom = {NewKey} )
`)
	if err := os.WriteFile(path, user, 0640); err != nil {
		t.Fatal(err)
	}
	first := testPaperRequest(t, lib, http.MethodPost, "", `{"title":"Must not replace the title","citekey":"UserKey"}`)
	if first.Code != http.StatusCreated {
		t.Fatal(first.Code, first.Body.String())
	}
	before, err := os.ReadFile(path)
	if err != nil || !bytes.Equal(user, before) {
		t.Fatal(string(before), err)
	}
	second := testPaperRequest(t, lib, http.MethodPost, "", `{"title":"Append me","citekey":"NewKey"}`)
	if second.Code != http.StatusCreated {
		t.Fatal(second.Code, second.Body.String())
	}
	before, err = os.ReadFile(path)
	if err != nil || !bytes.HasPrefix(before, user) || !bytes.Contains(before[len(user):], []byte("@misc{NewKey,")) {
		t.Fatal(string(before), err)
	}
	if mode, err := os.Stat(path); err != nil || mode.Mode().Perm() != 0640 {
		t.Fatal(mode, err)
	}
	for _, malformed := range [][]byte{append(bytes.Clone(before), []byte("@article{incomplete,")...), {0xff}} {
		if err = os.WriteFile(path, malformed, 0640); err != nil {
			t.Fatal(err)
		}
		response := testPaperRequest(t, lib, http.MethodPost, "", `{"title":"Must remain a draft"}`)
		after, err := os.ReadFile(path)
		if response.Code != http.StatusUnprocessableEntity || len(lib.all()) != 2 || err != nil || !bytes.Equal(after, malformed) {
			t.Fatal(response.Code, response.Body.String(), string(after), err)
		}
	}
}

func TestWorkspaceBibliographyRollsBackAndRejectsUnmanagedPaths(t *testing.T) {
	lib := testPaperLib(t)
	path := filepath.Join(lib.dir, "refs", libraryBibliographyName)
	paper := Paper{PaperMetadata: PaperMetadata{Title: "New draft", Citekey: "NewDraft"}}
	_, _, err := lib.create(paper.PaperMetadata, filepath.Join(lib.dir, "missing-stage.pdf"), "")
	if err == nil || len(lib.all()) != 0 {
		t.Fatal("failed import was published", err)
	}
	if _, err = os.Stat(path); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("failed import left a bibliography entry", err)
	}
	finish, err := lib.appendLibraryBibliography(paper)
	if err != nil {
		t.Fatal(err)
	}
	externallyEdited := []byte("@book{ExternalKey, title = {User edit}}\n")
	if err = os.WriteFile(path, externallyEdited, 0600); err != nil {
		t.Fatal(err)
	}
	if err = finish(false); !errors.Is(err, errBibliographyConflict) {
		t.Fatal(err)
	}
	contents, err := os.ReadFile(path)
	if err != nil || !bytes.Equal(contents, externallyEdited) {
		t.Fatal("rollback changed a concurrent user edit", err)
	}
	externalFile := filepath.Join(t.TempDir(), "external.bib")
	if err = os.WriteFile(externalFile, externallyEdited, 0600); err != nil {
		t.Fatal(err)
	}
	if err = os.Remove(path); err != nil {
		t.Fatal(err)
	}
	if err = os.Symlink(externalFile, path); err != nil {
		t.Fatal(err)
	}
	if _, _, err = lib.create(paper.PaperMetadata, "", ""); !errors.Is(err, errUnreadableBibliography) {
		t.Fatal("library accepted a symlink", err)
	}
	contents, err = os.ReadFile(externalFile)
	if err != nil || !bytes.Equal(contents, externallyEdited) {
		t.Fatal("bibliography write changed an unmanaged file", err)
	}
}
