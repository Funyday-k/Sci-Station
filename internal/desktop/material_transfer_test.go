package desktop

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"scistation.local/desktop/internal/meeting"
)

func TestAITransferChecksPendingAndCommittedMaterials(t *testing.T) {
	aDirectory, bDirectory, replacement := projectTestDir(t), projectTestDir(t), projectTestDir(t)
	root := t.TempDir()
	projects := meetingProjectService(t, aDirectory, bDirectory, replacement)
	projectA, err := registerFixtureDirectory(projects, aDirectory)
	if err != nil {
		t.Fatal(err)
	}
	projectB, err := registerFixtureDirectory(projects, bDirectory)
	if err != nil {
		t.Fatal(err)
	}
	a, b := projectA.ID, projectB.ID
	engine, err := meeting.New(root, func(context.Context, string, string, string, string) (string, error) {
		t.Error("mode transfer made a model request")
		return "", nil
	}, func() meeting.Settings { return meeting.Settings{Models: map[string]string{"codex": "fixture"}} })
	if err != nil {
		t.Fatal(err)
	}
	host := &apiServer{research: projects, meetings: engine}
	server := host.serve(8765)
	store := func(name, value string) meeting.Material {
		t.Helper()
		m, err := engine.StoreMaterial(name+".txt", strings.NewReader(value))
		if err != nil || m.Excerpt != value {
			t.Fatalf("store %q: %+v, %v", name, m, err)
		}
		return m
	}
	excerpt := func(projectID string) string {
		return meeting.ProjectExcerptMarker + fmt.Sprintf(`{"projectId":%q}`, projectID) + "\n\nPRIVATE_EXCERPT"
	}
	old := store("Committed A", excerpt(a))
	pending := store("Pending A", excerpt(a))
	foreign := store("Foreign B", excerpt(b))
	legacy := store("Legacy excerpt", meeting.PaperExcerptMarker+`{"page":1}`+"\n\nPRIVATE_LEGACY")
	neutral := store("Plain upload", "PRIVATE_UPLOAD")
	malformed := store("Malformed marker", meeting.PaperExcerptMarker+`{"projectId":99}`+"\n\nPRIVATE_MALFORMED")
	create := func(scope meeting.ProjectScope, ids ...string) *meeting.Session {
		t.Helper()
		s, err := engine.CreateScopedWithMaterials("Mode transfer fixture", scope, []string{"codex"}, ids)
		if err != nil {
			t.Fatal(err)
		}
		return s
	}
	room := create(meeting.ProjectScope{ID: a, Directory: aDirectory}, old.ID)
	global := create(meeting.ProjectScope{Global: true}, legacy.ID, malformed.ID)
	check := func(status int, sessionID, projectID string, ids ...string) meeting.MaterialTransferCheck {
		t.Helper()
		body, err := json.Marshal(map[string]any{"sessionId": sessionID, "projectId": projectID, "materialIds": ids})
		if err != nil {
			t.Fatal(err)
		}
		r := httptest.NewRequest(http.MethodPost, "http://localhost:8765/api/studio/materials/transfer-check", bytes.NewReader(body))
		r.Header.Set("Content-Type", "application/json")
		r.Header.Set("X-Roundtable", "1")
		w := httptest.NewRecorder()
		server.ServeHTTP(w, r)
		if w.Code != status {
			t.Fatalf("preflight got %d, want %d: %s", w.Code, status, w.Body.String())
		}
		if reply := w.Body.String(); strings.Contains(reply, "PRIVATE_") || strings.Contains(reply, root) ||
			strings.Contains(reply, `"excerpt"`) || status != 200 && strings.Contains(reply, `"materials"`) {
			t.Fatalf("preflight disclosed more than permitted metadata: %s", reply)
		}
		if status != http.StatusOK {
			return meeting.MaterialTransferCheck{}
		}
		return scienceWorkflowDecode[meeting.MaterialTransferCheck](t, w.Body.Bytes())
	}
	verified := check(200, room.ID, a, old.ID, pending.ID, pending.ID, neutral.ID)
	if !verified.SourceIsSingle || len(verified.Materials) != 3 || verified.Materials[0].ID != old.ID ||
		verified.Materials[1].ID != pending.ID || verified.Materials[1].Name != pending.Name || verified.Materials[2].ID != neutral.ID {
		t.Fatalf("wrong scoped preflight: %+v", verified)
	}
	if draft := check(200, "", "", neutral.ID); draft.SourceIsSingle || len(draft.Materials) != 1 {
		t.Fatalf("plain upload did not survive unscoped draft: %+v", draft)
	}
	check(200, "", a, pending.ID)
	check(200, global.ID, "", legacy.ID, neutral.ID)
	check(403, "", "", legacy.ID)
	check(403, global.ID, "", malformed.ID)
	check(403, global.ID, "", pending.ID)
	check(403, room.ID, a, neutral.ID, foreign.ID)
	check(403, room.ID, b)
	check(403, room.ID, "")
	check(404, room.ID, a, strings.Repeat("a", 32))
	check(404, strings.Repeat("b", 32), a)
	tooMany := make([]string, 13)
	for i := range tooMany {
		tooMany[i] = pending.ID
	}
	check(200, room.ID, a, tooMany[:12]...)
	check(400, room.ID, a, tooMany...)

	// Repeat the check after the inspected original changes, without binding
	// it to the open thread or changing its byte count.
	path := filepath.Join(root, "materials", pending.ID, "original")
	stamp := time.Now().Add(-time.Hour)
	if err := os.Chtimes(path, stamp, stamp); err != nil {
		t.Fatal(err)
	}
	if after := check(200, room.ID, a, pending.ID).Materials[0]; after.Revision == verified.Materials[1].Revision {
		t.Fatal("changed original did not invalidate the prior review")
	}
	if err := os.WriteFile(path, []byte(excerpt(b)), 0600); err != nil {
		t.Fatal(err)
	}
	check(403, room.ID, a, pending.ID)
	if err := os.Remove(path); err != nil {
		t.Fatal(err)
	}
	check(404, room.ID, a, pending.ID)

	// A replaced project-bound pool record may not be rescued by its earlier
	// committed snapshot. A different snapshot within the same scope conflicts.
	changeRecord := func(m meeting.Material) {
		t.Helper()
		encoded, err := json.Marshal(m)
		if err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(root, "materials", m.ID, "metadata.json"), encoded, 0600); err != nil {
			t.Fatal(err)
		}
	}
	updated := old
	updated.Name = "Changed.txt"
	changeRecord(updated)
	check(409, room.ID, a, old.ID)
	updated.Excerpt = excerpt(b)
	changeRecord(updated)
	check(403, room.ID, a, old.ID)
	changeMeetingProjectDirectory(t, host, projectA, replacement)
	check(403, room.ID, a, neutral.ID)

	unchanged, err := engine.Get(room.ID)
	if err != nil || len(unchanged.Materials) != 1 || unchanged.Materials[0] != old || len(unchanged.Rounds) != 0 {
		t.Fatalf("preflight changed the meeting: %+v, %v", unchanged, err)
	}
}
