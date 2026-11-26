package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"

	"scistation.local/desktop/internal/meeting"
	"scistation.local/desktop/internal/workspace"
)

func reviewFixture(t *testing.T, sessions ...meeting.Session) *apiServer {
	t.Helper()
	dir := t.TempDir()
	for _, session := range sessions {
		if session.Status == "" {
			session.Status = "ready"
		}
		// An absent project demonstrates that review never reads workspace files.
		session.Project = filepath.Join(dir, "project-does-not-exist")
		body, err := json.Marshal(session)
		if err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(dir, session.ID+".json"), body, 0600); err != nil {
			t.Fatal(err)
		}
	}
	engine, err := meeting.New(dir, func(context.Context, string, string, string, string) (string, error) {
		t.Error("review must not call a model")
		return "", nil
	}, func() meeting.Settings { return meeting.Settings{} })
	if err != nil {
		t.Fatal(err)
	}
	return &apiServer{meetings: engine}
}

func reviewRequest(a *apiServer, method, id, path, before, after string) *httptest.ResponseRecorder {
	query := url.Values{"path": {path}, "before": {before}, "after": {after}}
	r := httptest.NewRequest(method, "/api/studio/sessions/"+id+"/review?"+query.Encode(), nil)
	w := httptest.NewRecorder()
	a.review(w, r, id)
	return w
}

func decodeReview(t *testing.T, w *httptest.ResponseRecorder) reviewResult {
	t.Helper()
	if w.Code != http.StatusOK {
		t.Fatalf("review status %d: %s", w.Code, w.Body)
	}
	var result reviewResult
	if err := json.Unmarshal(w.Body.Bytes(), &result); err != nil {
		t.Fatal(err)
	}
	return result
}

func TestReviewSelectsExactOldRevisionAmongSamePath(t *testing.T) {
	id := strings.Repeat("a", 32)
	changes := make([]workspace.Change, 0, 300)
	for i := range 300 {
		changes = append(changes, workspace.Change{Path: "same.md", Before: fmt.Sprint("before-", i), After: fmt.Sprint("after-", i), Diff: fmt.Sprintf("--- a/same.md\n+++ b/same.md\n@@ -1,1 +1,1 @@\n-old %d\n+new %d\n", i, i)})
	}
	a := reviewFixture(t, meeting.Session{ID: id, Rounds: []meeting.Round{{Turns: []meeting.Turn{{Seat: "codex", Changes: changes}}}}})
	for _, index := range []int{0, 149, 299, 0} {
		result := decodeReview(t, reviewRequest(a, "GET", id, "same.md", fmt.Sprint("before-", index), fmt.Sprint("after-", index)))
		if result.Path != "same.md" || result.Added != 1 || result.Removed != 1 || !strings.Contains(result.Diff, fmt.Sprintf("+new %d\n", index)) {
			t.Fatalf("wrong selected review: %+v", result)
		}
	}
	if w := reviewRequest(a, "GET", id, "same.md", "before-0", "after-299"); w.Code != 404 {
		t.Fatalf("mixed revisions accepted: %d", w.Code)
	}
}

func TestReviewIncludesHumanChangesAndExcludesOperations(t *testing.T) {
	id := strings.Repeat("b", 32)
	human := workspace.Change{Path: "draft.md", Before: "missing", After: "human", Diff: "--- a/draft.md\n+++ b/draft.md\n@@ -0,0 +1,2 @@\n+one\n+two\n"}
	intent := workspace.Change{Path: "other.md", Before: "missing", After: "intent", Diff: human.Diff}
	a := reviewFixture(t, meeting.Session{ID: id, UserChanges: []meeting.UserChange{{Change: human}}, Operations: []meeting.Operation{{Status: "applied", Change: &intent}}})
	result := decodeReview(t, reviewRequest(a, "GET", id, human.Path, human.Before, human.After))
	if result.Added != 2 || result.Removed != 0 {
		t.Fatalf("human totals: %+v", result)
	}
	if w := reviewRequest(a, "GET", id, intent.Path, intent.Before, intent.After); w.Code != 404 {
		t.Fatalf("operation-only record accepted: %d", w.Code)
	}
}

func TestReviewNormalizesHistoricalCoarsePatchWithoutWorkspace(t *testing.T) {
	id := strings.Repeat("4", 32)
	change := workspace.Change{Path: "old.md", Before: "before", After: "after", Diff: "--- a/old.md\n+++ b/old.md\n@@ -101,5 +201,5 @@\n-a\n-b\n-old\n-d\n-e\n+a\n+b\n+new\n+d\n+e\n"}
	a := reviewFixture(t, meeting.Session{ID: id, UserChanges: []meeting.UserChange{{Change: change}}})
	result := decodeReview(t, reviewRequest(a, "GET", id, change.Path, change.Before, change.After))
	if result.Added != 1 || result.Removed != 1 || strings.Contains(result.Diff, "-a\n") || !strings.Contains(result.Diff, "@@ -101,5 +201,5 @@") {
		t.Fatalf("historical normalization/counts: %+v", result)
	}
}

func TestReviewDoesNotCrossSessionsOrFallBackToCurrentFile(t *testing.T) {
	first, second := strings.Repeat("c", 32), strings.Repeat("d", 32)
	change := workspace.Change{Path: "draft.md", Before: "old", After: "new", Diff: "--- a/draft.md\n+++ b/draft.md\n@@ -1,1 +1,1 @@\n-old\n+new\n"}
	a := reviewFixture(t, meeting.Session{ID: first, UserChanges: []meeting.UserChange{{Change: change}}}, meeting.Session{ID: second})
	decodeReview(t, reviewRequest(a, "GET", first, change.Path, change.Before, change.After))
	for _, test := range []struct{ id, path string }{{second, change.Path}, {first, "../arbitrary.txt"}, {strings.Repeat("e", 32), change.Path}} {
		if w := reviewRequest(a, "GET", test.id, test.path, change.Before, change.After); w.Code != 404 {
			t.Errorf("unexpected lookup status %d for %+v", w.Code, test)
		}
	}
}

func TestReviewRejectsMissingDuplicateAndWrongMethod(t *testing.T) {
	a := reviewFixture(t)
	id := strings.Repeat("f", 32)
	for _, query := range []string{"", "path=a.md", "path=a.md&before=old", "path=a.md&before=old&after=", "path=a.md&path=b.md&before=old&after=new", "path=%zz&before=old&after=new"} {
		w := httptest.NewRecorder()
		a.review(w, httptest.NewRequest("GET", "/?"+query, nil), id)
		if w.Code != 400 {
			t.Errorf("query %q returned %d", query, w.Code)
		}
	}
	if w := reviewRequest(a, "POST", id, "a.md", "old", "new"); w.Code != 405 || w.Header().Get("Allow") != "GET" {
		t.Fatalf("method guard: %d %v", w.Code, w.Header())
	}
}

func TestReviewInvalidHistoricalPatchAndEmptyRevision(t *testing.T) {
	id := strings.Repeat("1", 32)
	a := reviewFixture(t, meeting.Session{ID: id, UserChanges: []meeting.UserChange{
		{Change: workspace.Change{Path: "broken.md", Before: "old", After: "new", Diff: "--- a/broken.md\n+++ b/broken.md\n@@ -1,1 +1,1 @@\n-old\n"}},
		{Change: workspace.Change{Path: "empty.md", Before: "same", After: "same", Diff: ""}},
	}})
	if w := reviewRequest(a, "GET", id, "broken.md", "old", "new"); w.Code != 422 {
		t.Fatalf("invalid historical patch returned %d: %s", w.Code, w.Body)
	}
	result := decodeReview(t, reviewRequest(a, "GET", id, "empty.md", "same", "same"))
	if result.Diff != "" || result.Added != 0 || result.Removed != 0 {
		t.Fatalf("empty revision = %+v", result)
	}
}

func TestReviewCacheDoesNotHideChangedSavedPatch(t *testing.T) {
	id := strings.Repeat("2", 32)
	for _, line := range []string{"first", "second"} {
		change := workspace.Change{Path: "file.md", Before: "old", After: "new", Diff: "--- a/file.md\n+++ b/file.md\n@@ -1 +1 @@\n-old\n+" + line + "\n"}
		a := reviewFixture(t, meeting.Session{ID: id, UserChanges: []meeting.UserChange{{Change: change}}})
		result := decodeReview(t, reviewRequest(a, "GET", id, change.Path, change.Before, change.After))
		if !strings.Contains(result.Diff, "+"+line+"\n") {
			t.Fatalf("stale cached patch: %+v", result)
		}
	}
}

func TestReviewReportsUnreadableSessionSeparately(t *testing.T) {
	dir := t.TempDir()
	engine, err := meeting.New(dir, func(context.Context, string, string, string, string) (string, error) { return "", nil }, func() meeting.Settings { return meeting.Settings{} })
	if err != nil {
		t.Fatal(err)
	}
	id := strings.Repeat("3", 32)
	if err := os.WriteFile(filepath.Join(dir, id+".json"), []byte("invalid JSON"), 0600); err != nil {
		t.Fatal(err)
	}
	if w := reviewRequest(&apiServer{meetings: engine}, "GET", id, "file.md", "old", "new"); w.Code != 500 {
		t.Fatalf("corrupt session returned %d: %s", w.Code, w.Body)
	}
}

func TestReviewCacheBoundsBytesAndEntries(t *testing.T) {
	var cache reviewMemo
	for i := range 100 {
		key := reviewKey{Session: fmt.Sprint(i)}
		cache.put(key, reviewResult{Path: "a.md", Diff: strings.Repeat("x", 150000)})
	}
	if len(cache.entries) > reviewCacheEntries || cache.bytes > reviewCacheBytes {
		t.Fatalf("cache is unbounded: entries=%d bytes=%d", len(cache.entries), cache.bytes)
	}
	if _, found := cache.get(reviewKey{Session: "0"}); found {
		t.Fatal("old FIFO entry retained")
	}
	if _, found := cache.get(reviewKey{Session: "99"}); !found {
		t.Fatal("latest entry missing")
	}
	cache.put(reviewKey{Session: "oversized"}, reviewResult{Diff: strings.Repeat("x", reviewCacheBytes+1)})
	if _, found := cache.get(reviewKey{Session: "oversized"}); found {
		t.Fatal("oversized result cached")
	}
	var wg sync.WaitGroup
	for i := range 20 {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			key := reviewKey{Session: fmt.Sprint("concurrent-", i)}
			cache.put(key, reviewResult{Diff: "+safe\n"})
			cache.get(key)
		}(i)
	}
	wg.Wait()
}
