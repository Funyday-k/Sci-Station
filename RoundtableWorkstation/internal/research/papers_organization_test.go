package research

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func collectionFixture(t *testing.T, lib *PaperLibrary, revision int, parent, name string) string {
	t.Helper()
	body := fmt.Sprintf(`{"revision":%d,"operation":"create_collection","parent_id":%q,"name":%q}`, revision, parent, name)
	response := testPaperRequest(t, lib, http.MethodPatch, "/organization", body)
	if response.Code != http.StatusOK {
		t.Fatal(response.Code, response.Body.String())
	}
	var organization paperOrganization
	if err := json.Unmarshal(response.Body.Bytes(), &organization); err != nil {
		t.Fatal(err)
	}
	for id, collection := range organization.Collections {
		if collection.ParentID == parent && collection.Name == name {
			return id
		}
	}
	t.Fatalf("collection %q missing", name)
	return ""
}

func TestLibraryOrganizationAndScopedBibliography(t *testing.T) {
	lib := testPaperLib(t)
	parent := collectionFixture(t, lib, 0, "", "Physics")
	child := collectionFixture(t, lib, 1, parent, "Solar")
	fixture, err := os.ReadFile(readerFixture(t))
	if err != nil {
		t.Fatal(err)
	}
	paper := uploadTestPDF(t, lib, string(fixture), fmt.Sprintf(`{
		"title":"Solar capture","authors":["de Vries, Ana","Emi Ng"],"year":2026,"tags":["signal"],
		"collection_id":%q,"project_ids":["solar","other"],"core_project_ids":["other"],
		"project_links":{"solar":{"is_pinned":true,"sort_order":3},"other":{"sort_order":1}}
	}`, child))
	second, _, err := lib.create(PaperMetadata{Title: "Other Paper", Tags: []string{"signal"}, ProjectIDs: []string{"other"}}, "", "")
	if err != nil {
		t.Fatal(err)
	}
	meta := `{"revision":1,"publication_title":"Physical Review","volume":"9","issue":"2","pages":"23--28","title":"Solar capture {update}"}`
	updated := testPaperRequest(t, lib, http.MethodPatch, "/"+paper.ID, meta)
	if updated.Code != http.StatusOK {
		t.Fatal(updated.Code, updated.Body.String())
	}
	if stale := testPaperRequest(t, lib, http.MethodPatch, "/"+paper.ID, `{"revision":1,"tags":["other"]}`); stale.Code != http.StatusConflict {
		t.Fatal(stale.Code, stale.Body.String())
	}
	request := func(revision int, operation, id, name string, expected int) {
		t.Helper()
		patch := fmt.Sprintf(`{"revision":%d,"operation":%q,"collection_id":%q,"name":%q,"color":"#355588"}`, revision, operation, id, name)
		response := testPaperRequest(t, lib, http.MethodPatch, "/organization", patch)
		if response.Code != expected {
			t.Fatal(response.Code, response.Body.String())
		}
	}
	request(2, "set_tag", "", "signal", http.StatusOK)
	request(2, "rename_collection", parent, "Wrong", http.StatusConflict)
	request(3, "rename_collection", parent, "Astroparticle", http.StatusOK)
	request(4, "delete_collection", child, "", http.StatusBadRequest)
	request(4, "delete_collection", parent, "", http.StatusBadRequest)
	request(4, "delete_tag", "", "signal", http.StatusOK)

	lib, err = NewPaperLibrary(lib.dir)
	if err != nil {
		t.Fatal(err)
	}
	organization, _, err := lib.readOrganization()
	if err != nil || organization.Collections[parent].Name != "Astroparticle" || len(organization.Tags) != 0 {
		t.Fatal(organization, err)
	}
	reopened, _ := lib.Snapshot(paper.ID)
	if !reflect.DeepEqual(reopened.ProjectLinks, paper.ProjectLinks) ||
		!reflect.DeepEqual(reopened.CoreProjectIDs, paper.CoreProjectIDs) ||
		!reflect.DeepEqual(reopened.ProjectIDs, paper.ProjectIDs) ||
		!reflect.DeepEqual(reopened.Tags, []string{"signal"}) || reopened.CollectionID != child {
		t.Fatal(reopened)
	}
	path, err := lib.PDFPath(paper.ID)
	if err != nil {
		t.Fatal(err)
	}
	original, err := os.ReadFile(path)
	if err != nil || !bytes.Equal(original, fixture) {
		t.Fatal("paper PDF changed", err)
	}
	bib := testPaperRequest(t, lib, http.MethodGet, "/bibtex?project=other&collection="+parent+"&tag=signal&q=Physical", "")
	for _, required := range []string{`@article{` + paper.Citekey, `title = {Solar capture \{update\}}`,
		`author = {de Vries, Ana and Emi Ng}`, `journal = {Physical Review}`,
		`volume = {9}`, `number = {2}`, `pages = {23--28}`} {
		if !strings.Contains(bib.Body.String(), required) {
			t.Fatalf("missing %q in %s", required, bib.Body.String())
		}
	}
	if bib.Code != http.StatusOK || strings.Contains(bib.Body.String(), second.Citekey) {
		t.Fatal(bib.Code, bib.Body.String())
	}
	unfiled := testPaperRequest(t, lib, http.MethodGet, "/?collection=unfiled&tag=signal", "")
	if unfiled.Code != http.StatusOK || !strings.Contains(unfiled.Body.String(), second.ID) || strings.Contains(unfiled.Body.String(), paper.ID) {
		t.Fatal(unfiled.Code, unfiled.Body.String())
	}
}

func TestOrganizationUnknownFieldsAndBadFormatRecovery(t *testing.T) {
	lib := testPaperLib(t)
	id := collectionFixture(t, lib, 0, "", "Folder")
	write := func(data []byte) {
		t.Helper()
		if err := os.WriteFile(lib.organizationPath(), data, 0600); err != nil {
			t.Fatal(err)
		}
	}
	initial := fmt.Appendf(nil, `{"version":1,"revision":1,"tags":{},"collections":{%q:{"name":"Folder","future":{"opaque":[1,2]}}},"future":{"abc":3}}`, id)
	write(initial)
	request := func(revision int) *httptest.ResponseRecorder {
		return testPaperRequest(t, lib, http.MethodPatch, "/organization",
			fmt.Sprintf(`{"revision":%d,"operation":"rename_collection","collection_id":%q,"name":"Renamed"}`, revision, id))
	}
	res := request(1)
	if res.Code != http.StatusOK {
		t.Fatal(res.Code, res.Body.String())
	}
	saved, err := os.ReadFile(lib.organizationPath())
	if err != nil || !bytes.Contains(saved, []byte(`"future":{"opaque":[1,2]}`)) || !bytes.Contains(saved, []byte(`"future":{"abc":3}`)) {
		t.Fatal(string(saved), err)
	}
	for _, broken := range [][]byte{[]byte("{"), bytes.Replace(saved, []byte(`"version":1`), []byte(`"version":2`), 1)} {
		write(broken)
		if res = request(2); res.Code != http.StatusUnprocessableEntity ||
			!strings.Contains(res.Body.String(), errUnreadablePaperOrganization.Error()) {
			t.Fatal(res.Code, res.Body.String())
		}
		if _, err = NewPaperLibrary(lib.dir); err == nil {
			t.Fatal("malformed or unsupported organization opened")
		}
		raw, err := os.ReadFile(lib.organizationPath())
		if err != nil || !bytes.Equal(raw, broken) {
			t.Fatal("invalid record was overwritten", err)
		}
	}
	write(saved)
	if res = request(2); res.Code != http.StatusOK {
		t.Fatal(res.Code, res.Body.String())
	}
}

func TestCollectionAssignmentAndRemovalAreSerialized(t *testing.T) {
	lib := testPaperLib(t)
	id := collectionFixture(t, lib, 0, "", "Folder")
	paper, _, err := lib.create(PaperMetadata{Title: "Previous record"}, "", "")
	if err != nil {
		t.Fatal(err)
	}
	other, err := NewPaperLibrary(lib.dir)
	if err != nil {
		t.Fatal(err)
	}
	start := make(chan struct{})
	results := make(chan int, 2)
	go func() {
		<-start
		results <- testPaperRequest(t, lib, http.MethodPatch, "/"+paper.ID,
			fmt.Sprintf(`{"revision":1,"collection_id":%q}`, id)).Code
	}()
	go func() {
		<-start
		results <- testPaperRequest(t, other, http.MethodPatch, "/organization",
			fmt.Sprintf(`{"revision":1,"operation":"delete_collection","collection_id":%q}`, id)).Code
	}()
	close(start)
	codes := map[int]int{<-results: 1}
	codes[<-results]++
	if codes[http.StatusOK] != 1 || codes[http.StatusBadRequest] != 1 {
		t.Fatal(codes)
	}
	reopened, err := NewPaperLibrary(lib.dir)
	if err != nil {
		t.Fatal(err)
	}
	organization, _, err := reopened.readOrganization()
	record, _ := reopened.Snapshot(paper.ID)
	_, exists := organization.Collections[id]
	if err != nil || exists != (record.CollectionID == id) {
		t.Fatal(organization, record, err)
	}
	if _, err := os.Stat(filepath.Join(lib.dir, "records", paper.ID+".json")); err != nil {
		t.Fatal(err)
	}
}

func TestLibraryWikiColumnResolvesActivePages(t *testing.T) {
	service := newResearch(t, t.TempDir())
	project := createResearchProject(t, service, "Reading")
	paper, _, err := service.papers.create(PaperMetadata{Title: "Paper with a Wiki", ProjectIDs: []string{project.ID}}, "", "")
	if err != nil {
		t.Fatal(err)
	}
	path := "/projects/" + project.ID + "/notes"
	note := decodeResearch[Note](t, callResearch(t, service, "POST", path,
		map[string]string{"title": "Paper summary", "paperId": paper.ID, "body": "Private note text"}, http.StatusCreated))
	result := callResearch(t, service, "GET", "/paper-wiki-status", nil, http.StatusOK)
	if status := decodeResearch[map[string]bool](t, result); len(status) != 1 || !status[paper.ID] ||
		bytes.Contains(result, []byte("Private note text")) {
		t.Fatal(string(result))
	}
	callResearch(t, service, "DELETE", fmt.Sprintf("%s/%s?revision=%d", path, note.ID, note.Revision), nil, http.StatusNoContent)
	if status := decodeResearch[map[string]bool](t, callResearch(t, service, "GET", "/paper-wiki-status", nil, http.StatusOK)); len(status) != 0 {
		t.Fatal(status)
	}
}
