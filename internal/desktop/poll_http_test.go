package desktop

import (
	"context"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"

	"scistation.local/desktop/internal/meeting"
)

func TestSessionConditionalRead(t *testing.T) {
	engine, err := meeting.New(t.TempDir(), func(context.Context, string, string, string, string) (string, error) {
		t.Fatal("polling started a model")
		return "", nil
	}, func() meeting.Settings { return meeting.Settings{} })
	if err != nil {
		t.Fatal(err)
	}
	project, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	s, err := engine.Create("check polling", project, []string{"codex"})
	if err != nil {
		t.Fatal(err)
	}
	server := (&apiServer{meetings: engine}).serve(8765)
	get := func(tag string) *httptest.ResponseRecorder {
		req := httptest.NewRequest(http.MethodGet, "http://127.0.0.1:8765/api/studio/sessions/"+s.ID, nil)
		req.Header.Set("If-None-Match", tag)
		out := httptest.NewRecorder()
		server.ServeHTTP(out, req)
		return out
	}
	full := get("")
	tag := full.Header().Get("ETag")
	if full.Code != http.StatusOK || tag == "" {
		t.Fatal(full.Code, tag)
	}
	same := get(tag)
	if same.Code != http.StatusNotModified || same.Body.Len() != 0 {
		t.Fatal(same.Code, same.Body.Len())
	}
	if _, err = engine.UserWrite(s.ID, "example.md", "new", "missing"); err != nil {
		t.Fatal(err)
	}
	updated := get(tag)
	if updated.Code != http.StatusOK || updated.Header().Get("ETag") == tag {
		t.Fatal(updated.Code)
	}
	t.Logf("unchanged conditional response: %d body bytes; updated journal: %d body bytes", same.Body.Len(), updated.Body.Len())
}
