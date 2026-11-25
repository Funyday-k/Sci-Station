package research

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"sync"
	"testing"
)

func TestProjectPaperReadingChoices(t *testing.T) {
	lib := testPaperLib(t)
	p, _, err := lib.create(PaperMetadata{Title: "Shared fixture", ProjectIDs: []string{"one", "two"}, CoreProjectIDs: []string{"two"}}, "", "")
	if err != nil {
		t.Fatal(err)
	}
	path := "/" + p.ID
	body := `{"revision":1,"project_links":{"one":{"is_pinned":true,"sort_order":0,"folder_path":"Theory/BH","use_for":["derive"," compare ","derive"]},"two":{"sort_order":3,"folder_path":"Background","use_for":["teach"]}}}`
	if res := testPaperRequest(t, lib, "PATCH", path, body); res.Code != 200 {
		t.Fatal(res.Body.String())
	}
	rec, _ := lib.Snapshot(p.ID)
	a, b := rec.ProjectLinks["one"], rec.ProjectLinks["two"]
	if !a.IsPinned || *a.SortOrder != 0 || a.FolderPath != "Theory/BH" || !reflect.DeepEqual(a.UseFor, []string{"derive", "compare"}) ||
		b.IsPinned || *b.SortOrder != 3 || b.FolderPath != "Background" || !reflect.DeepEqual(b.UseFor, []string{"teach"}) ||
		!reflect.DeepEqual(rec.CoreProjectIDs, []string{"two"}) {
		t.Fatal(rec)
	}
	rec.ProjectLinks["one"].UseFor[0] = "outside"
	*a.SortOrder = 9
	again, _ := lib.Snapshot(p.ID)
	if *again.ProjectLinks["one"].SortOrder != 0 || again.ProjectLinks["one"].UseFor[0] != "derive" {
		t.Fatal("snapshot mutated stored link")
	}
	if res := testPaperRequest(t, lib, "PATCH", path, `{"revision":2,"project_links":{"orphan":{"is_pinned":true}}}`); res.Code != 400 {
		t.Fatal(res.Code)
	}
	if res := testPaperRequest(t, lib, "PATCH", path, `{"revision":2,"project_links":{"one":{"folder_path":"revised"}}}`); res.Code != 200 {
		t.Fatal(res.Body.String())
	}
	for _, tc := range []struct {
		query   string
		matches bool
	}{{"project=one&q=derive", true}, {"project=two&q=derive", false}, {"q=derive", false}} {
		res := testPaperRequest(t, lib, "GET", "/?"+tc.query, "")
		if res.Code != 200 || strings.Contains(res.Body.String(), p.ID) != tc.matches {
			t.Fatal(tc.query, res.Body.String())
		}
	}
	reopened, err := NewPaperLibrary(lib.dir)
	if err != nil {
		t.Fatal(err)
	}
	got, _ := reopened.Snapshot(p.ID)
	if !got.ProjectLinks["one"].IsPinned || *got.ProjectLinks["one"].SortOrder != 0 || !reflect.DeepEqual(got.ProjectLinks["two"], b) {
		t.Fatal(got)
	}
	if res := testPaperRequest(t, reopened, "PUT", path, `{"revision":3,"project_ids":["one"],"core_project_ids":[]}`); res.Code != 200 {
		t.Fatal(res.Body.String())
	}
	got, _ = reopened.Snapshot(p.ID)
	if len(got.ProjectLinks) != 1 || got.ProjectLinks["one"].FolderPath != "revised" {
		t.Fatal(got.ProjectLinks)
	}
}

func TestProjectPaperOrdering(t *testing.T) {
	lib := testPaperLib(t)
	for _, tc := range []struct {
		title  string
		pinned bool
		order  *int
	}{
		{"pinned", true, nil}, {"unordered", false, nil}, {"first", false, new(-1)}, {"second", false, new(0)},
	} {
		_, _, err := lib.create(PaperMetadata{Title: tc.title, ProjectIDs: []string{"one", "two"}, ProjectLinks: map[string]PaperProjectLink{"one": {IsPinned: tc.pinned, SortOrder: tc.order}, "two": {IsPinned: tc.title == "unordered"}}}, "", "")
		if err != nil {
			t.Fatal(err)
		}
	}
	for _, tc := range []struct {
		project string
		want    []string
	}{{"one", []string{"pinned", "first", "second", "unordered"}}, {"two", []string{"unordered", "second", "first", "pinned"}}} {
		res := testPaperRequest(t, lib, "GET", "/?project="+tc.project, "")
		var rows []Paper
		if err := json.Unmarshal(res.Body.Bytes(), &rows); err != nil {
			t.Fatal(err)
		}
		var titles []string
		for _, row := range rows {
			titles = append(titles, row.Title)
		}
		if !reflect.DeepEqual(titles, tc.want) {
			t.Fatalf("%s: %v", tc.project, titles)
		}
	}
}

func TestProjectPaperUnknownFieldsAndDamagedRecords(t *testing.T) {
	lib := testPaperLib(t)
	p, _, err := lib.create(PaperMetadata{Title: "Fixture", ProjectIDs: []string{"one"}, ProjectLinks: map[string]PaperProjectLink{"one": {FolderPath: "old"}}}, "", "")
	if err != nil {
		t.Fatal(err)
	}
	file := filepath.Join(lib.dir, "records", p.ID+".json")
	data, err := os.ReadFile(file)
	if err != nil {
		t.Fatal(err)
	}
	var fields map[string]any
	if err = json.Unmarshal(data, &fields); err != nil {
		t.Fatal(err)
	}
	fields["future"] = map[string]any{"tag": []any{"v", float64(3)}}
	link := fields["project_links"].(map[string]any)["one"].(map[string]any)
	link["future_setting"] = map[string]any{"notes": []any{"x"}}
	data, err = json.Marshal(fields)
	if err != nil {
		t.Fatal(err)
	}
	if err = os.WriteFile(file, data, 0600); err != nil {
		t.Fatal(err)
	}
	lib, err = NewPaperLibrary(lib.dir)
	if err != nil {
		t.Fatal(err)
	}
	res := testPaperRequest(t, lib, "PATCH", "/"+p.ID, `{"revision":1,"project_links":{"one":{"is_pinned":true}}}`)
	if res.Code != 200 {
		t.Fatal(res.Body.String())
	}
	var saved map[string]any
	data, err = os.ReadFile(file)
	if err != nil {
		t.Fatal(err)
	}
	if err = json.Unmarshal(data, &saved); err != nil {
		t.Fatal(err)
	}
	updated := saved["project_links"].(map[string]any)["one"].(map[string]any)
	if !reflect.DeepEqual(saved["future"], fields["future"]) || !reflect.DeepEqual(updated["future_setting"], link["future_setting"]) || updated["folder_path"] != "old" {
		t.Fatal(saved)
	}
	for _, damaged := range [][]byte{[]byte("{"), bytes.Replace(data, []byte(`"folder_path":"old"`), []byte(`"folder_path":{}`), 1)} {
		if err = os.WriteFile(file, damaged, 0600); err != nil {
			t.Fatal(err)
		}
		res = testPaperRequest(t, lib, "PATCH", "/"+p.ID, `{"revision":2,"title":"overwrite"}`)
		if res.Code != 500 {
			t.Fatal(res.Code)
		}
		if _, err = NewPaperLibrary(lib.dir); err == nil {
			t.Fatal("damaged record opened")
		}
		raw, err := os.ReadFile(file)
		if err != nil || !bytes.Equal(raw, damaged) {
			t.Fatal("damaged record changed", err)
		}
	}
}

func TestProjectPaperCompetingEditsAcrossLibraryInstances(t *testing.T) {
	lib := testPaperLib(t)
	p, _, err := lib.create(PaperMetadata{Title: "Fixture", ProjectIDs: []string{"a", "b"}}, "", "")
	if err != nil {
		t.Fatal(err)
	}
	peer, err := NewPaperLibrary(lib.dir)
	if err != nil {
		t.Fatal(err)
	}
	var wg sync.WaitGroup
	start := make(chan struct{})
	results := make(chan int, 2)
	for id, instance := range map[string]*PaperLibrary{"a": lib, "b": peer} {
		wg.Go(func() {
			<-start
			res := testPaperRequest(t, instance, "PATCH", "/"+p.ID, fmt.Sprintf(`{"revision":1,"project_links":{%q:{"is_pinned":true}}}`, id))
			results <- res.Code
		})
	}
	close(start)
	wg.Wait()
	close(results)
	count := map[int]int{}
	for code := range results {
		count[code]++
	}
	if count[200] != 1 || count[409] != 1 {
		t.Fatal(count)
	}
	for _, instance := range []*PaperLibrary{lib, peer} {
		rec, _ := instance.Snapshot(p.ID)
		if rec.Revision != 2 || len(rec.ProjectLinks) != 1 {
			t.Fatal(rec)
		}
	}
}
