package research

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"mime/multipart"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"unicode/utf8"
)

func TestWorkflowProjectRetrievalKeepsCurrentSourcesAndReusesLocalVectors(t *testing.T) {
	root := t.TempDir()
	s := newResearch(t, root)
	project := createResearchProject(t, s, "Project retrieval fixture")
	other := createResearchProject(t, s, "Separate project fixture")
	notes := "/projects/" + project.ID + "/notes"
	createNote := func(path, title, body string) Note {
		return decodeResearch[Note](t, callResearch(t, s, "POST", path, map[string]string{"title": title, "body": body}, 201))
	}
	note := createNote(notes, "Research note", "# Setup\nBoundary scattering at steady temperature.")
	const otherText = "crossprojectfixture"
	createNote("/projects/"+other.ID+"/notes", "Private elsewhere", otherText)
	if err := os.WriteFile(filepath.Join(project.Path, "unregistered.txt"), []byte("unregistered marker"), 0600); err != nil {
		t.Fatal(err)
	}

	paper, _, err := s.papers.create(PaperMetadata{
		Title: "Shared paper", ProjectIDs: []string{project.ID, other.ID}, CoreProjectIDs: []string{project.ID},
	}, "", "")
	if err != nil {
		t.Fatal(err)
	}
	const original = "# Overview\r\n😀 Separate section.\r\n## Calculation\r\nBoundary scattering is the controlled result.\r\n"
	paper = decodeResearch[Paper](t, uploadMarkdownFixture(t, s, paper, original, 200))
	material := uploadRetrievalMaterial(t, s, project.ID, "thermal limits in the isolated fixture")

	find := func(mode, query string) WorkflowRetrieval {
		t.Helper()
		out, err := s.FindWorkflowProject(t.Context(), project.ID, query, WorkflowRetrievalOptions{Mode: mode})
		if err != nil {
			t.Fatal(err)
		}
		return out
	}
	lexical := find("lexical", "boundary scattering")
	if len(lexical.Items) != 2 || lexical.Trace.Mode != "lexical" || lexical.Trace.FallbackReason != "embeddings_disabled" ||
		lexical.Trace.Verified != 3 || !strings.HasPrefix(lexical.Trace.QueryHash, "sha256:") {
		t.Fatalf("unexpected lexical result: %+v", lexical)
	}
	if _, err := os.Stat(s.retrievalCachePath(project.ID)); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("lexical-only use created a hybrid cache: %v", err)
	}
	if hits := find("lexical", otherText).Items; len(hits) != 0 {
		t.Fatalf("read an unrelated project: %+v", hits)
	}
	if hits := find("lexical", "unregistered marker").Items; len(hits) != 0 {
		t.Fatalf("read an unregistered file: %+v", hits)
	}

	first := find("hybrid", "boundary scattering")
	if len(first.Items) < 2 || first.Items[0].ID != paper.ID || first.Trace.Updated != 3 || first.Trace.Reused != 0 ||
		first.Trace.Model != retrievalModel || first.Trace.CacheVersion != retrievalCacheVersion {
		t.Fatalf("unexpected hybrid result: %+v", first)
	}
	hit := first.Items[0]
	source, err := s.WorkflowSource(t.Context(), project.ID, hit.SourceLocation)
	if err != nil || source.Hash != hit.Hash || !strings.HasPrefix(source.Text, hit.Text) ||
		hit.Line != 3 || hit.EndLine != 4 || hit.Heading != "Calculation" ||
		hit.Offset != utf8.RuneCountInString("# Overview\n😀 Separate section.\n") || hit.SourceHashStatus != "fresh" {
		t.Fatalf("failed to resolve current original passage: hit %+v preview %+v (%v)", hit, source, err)
	}

	cachePath := s.retrievalCachePath(project.ID)
	snapshot, err := os.ReadFile(cachePath)
	if err != nil || bytes.Contains(snapshot, []byte("Boundary")) || bytes.Contains(snapshot, []byte("thermal limits")) ||
		bytes.Contains(snapshot, []byte(otherText)) || !bytes.Contains(snapshot, []byte(material.ID)) {
		t.Fatalf("bad derived cache: %v", err)
	}
	s = newResearch(t, root)
	reused := find("hybrid", "boundary scattering")
	if reused.Trace.Reused != 3 || reused.Trace.Updated != 0 || reused.Items[0] != hit {
		t.Fatalf("restart changed reusable rankings: %+v", reused)
	}
	after, err := os.ReadFile(cachePath)
	if err != nil || !bytes.Equal(after, snapshot) {
		t.Fatalf("unchanged cache was replaced: %v", err)
	}

	editedNote := decodeResearch[Note](t, callResearch(t, s, "PATCH", notes+"/"+note.ID,
		map[string]any{"revision": note.Revision, "body": "Spectral diffusion replaces the earlier analysis."}, 200))
	next := find("hybrid", "spectral diffusion")
	if len(next.Items) == 0 || next.Items[0].ID != note.ID || next.Trace.Updated != 1 || next.Trace.Reused != 2 {
		t.Fatalf("changed note vectors were not refreshed incrementally: %+v", next)
	}
	callResearch(t, s, "DELETE", notes+"/"+note.ID+"?revision="+fmt.Sprint(editedNote.Revision), nil, 204)
	next = find("hybrid", "boundary scattering")
	if next.Trace.Removed != 1 || next.Trace.Reused != 2 || len(next.Items) == 0 || next.Items[0].ID != paper.ID {
		t.Fatalf("removed note was retained: %+v", next)
	}

	paper = decodeResearch[Paper](t, uploadMarkdownFixture(t, s, paper, "# Correction\nThe updated derivation uses absorption.", 200))
	next = find("hybrid", "updated derivation")
	if next.Trace.Updated != 1 || next.Trace.Reused != 1 || len(next.Items) == 0 ||
		next.Items[0].ID != paper.ID || next.Items[0].Hash == hit.Hash {
		t.Fatalf("changed paper revision retained an old locator: %+v", next)
	}

	rebuild, err := s.FindWorkflowProject(t.Context(), project.ID, "", WorkflowRetrievalOptions{
		Mode: "hybrid", Rebuild: true, Source: SourceLocation{Kind: "paper-markdown", ID: paper.ID},
	})
	if err != nil || rebuild.Trace.CacheStatus != "rebuilt" || rebuild.Trace.Updated != 1 || rebuild.Trace.Removed != 0 {
		t.Fatalf("selected rebuild failed: %+v %v", rebuild, err)
	}
	rebuild, err = s.FindWorkflowProject(t.Context(), project.ID, "", WorkflowRetrievalOptions{Mode: "hybrid", Rebuild: true})
	if err != nil || rebuild.Trace.CacheStatus != "rebuilt" || rebuild.Trace.Updated != 2 || rebuild.Trace.Reused != 0 {
		t.Fatalf("project rebuild failed: %+v %v", rebuild, err)
	}

	disk, status := readRetrievalCache(cachePath, project.ID)
	if status != "current" {
		t.Fatal(status)
	}
	disk.Model = "obsolete-fixture-model"
	old, err := json.Marshal(disk)
	if err != nil {
		t.Fatal(err)
	}
	if err = os.WriteFile(cachePath, old, 0600); err != nil {
		t.Fatal(err)
	}
	if refreshed := find("hybrid", "updated derivation"); refreshed.Trace.CacheStatus != "version_changed" ||
		refreshed.Trace.Updated != 2 || refreshed.Trace.Reused != 0 {
		t.Fatalf("incompatible model reused: %+v", refreshed)
	}
	if err = os.WriteFile(cachePath, []byte("{malformed"), 0600); err != nil {
		t.Fatal(err)
	}
	if refreshed := find("hybrid", "updated derivation"); refreshed.Trace.CacheStatus != "invalid" || refreshed.Trace.Updated != 2 {
		t.Fatalf("malformed cache prevented regeneration: %+v", refreshed)
	}
}

func TestWorkflowProjectRetrievalScopeAndCacheFailure(t *testing.T) {
	s := newResearch(t, t.TempDir())
	project := createResearchProject(t, s, "Downgrade fixture")
	other := createResearchProject(t, s, "Foreign project fixture")
	notes := "/projects/" + project.ID + "/notes"
	note := decodeResearch[Note](t, callResearch(t, s, "POST", notes, map[string]string{
		"title": "Private note", "body": "Gamma flux redacted fixture.",
	}, 201))
	hybrid := WorkflowRetrievalOptions{Mode: "hybrid"}
	query := "gamma flux"
	cachePath := s.retrievalCachePath(project.ID)
	external := filepath.Join(t.TempDir(), "untouched")
	if err := os.WriteFile(external, []byte("external fixture"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(filepath.Dir(cachePath), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(external, cachePath); err != nil {
		t.Fatal(err)
	}
	fallback, err := s.FindWorkflowProject(t.Context(), project.ID, query, hybrid)
	if err != nil || fallback.Trace.Mode != "lexical" || fallback.Trace.FallbackReason != "cache_write_failed" ||
		len(fallback.Items) != 1 || fallback.Items[0].ID != note.ID || fallback.Items[0].EmbeddingScore != 0 {
		t.Fatalf("expected safe lexical fallback: %+v %v", fallback, err)
	}
	if data, err := os.ReadFile(external); err != nil || string(data) != "external fixture" {
		t.Fatalf("touched linked cache target: %q %v", data, err)
	}

	selected := WorkflowRetrievalOptions{
		Mode: "hybrid", Rebuild: true, Source: SourceLocation{Kind: "note", ID: note.ID},
	}
	if _, err = s.FindWorkflowProject(t.Context(), other.ID, "", selected); err == nil {
		t.Fatal("project cache could be built from unrelated note")
	}
	if _, err := os.Stat(s.retrievalCachePath(other.ID)); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("unauthorized rebuild wrote a cache: %v", err)
	}
	modulePatch(t, s, project.ID, moduleChange{Action: "set", ModuleID: "wiki", Enabled: moduleBool(false)})
	hidden, err := s.FindWorkflowProject(t.Context(), project.ID, query, WorkflowRetrievalOptions{Mode: "lexical"})
	if err != nil || len(hidden.Items) != 0 || hidden.Trace.Sources != 0 {
		t.Fatalf("disabled wiki remained searchable: %+v %v", hidden, err)
	}
	if _, err = s.FindWorkflowProject(t.Context(), project.ID, "", selected); err == nil {
		t.Fatal("rebuilt a disabled source")
	}
	modulePatch(t, s, project.ID, moduleChange{Action: "set", ModuleID: "ai-lab", Enabled: moduleBool(false)})
	if _, err = s.FindWorkflowProject(t.Context(), project.ID, query, hybrid); err == nil {
		t.Fatal("searched despite disabled Lab")
	}
	ctx, cancel := context.WithCancel(t.Context())
	cancel()
	s.retrievalWorker <- struct{}{}
	defer func() { <-s.retrievalWorker }()
	if _, err = s.FindWorkflowProject(ctx, project.ID, query, hybrid); !errors.Is(err, context.Canceled) {
		t.Fatalf("cancelled search waited behind another lookup: %v", err)
	}
}

func TestWorkflowRetrievalChunksAndDeterministicBuckets(t *testing.T) {
	text := "# Heading\n" + strings.Repeat("🙂", retrievalChunkRunes) + "needle\n" + strings.Repeat("line\n", 85)
	chunks, limited := workflowRetrievalChunks(text, true)
	if limited || len(chunks) != 3 || chunks[1].offset != retrievalChunkRunes || chunks[1].line != 2 ||
		chunks[1].lastLine != 81 || chunks[2].line != 82 || chunks[1].heading != "Heading" ||
		[]rune(text)[chunks[1].offset] != []rune(chunks[1].text)[0] {
		t.Fatalf("lost a source offset across segmentation: %d chunks, bounded=%v", len(chunks), limited)
	}
	// SHA-256("abc") begins ba 78, giving positive Swift bucket 26.
	vec := vectorForRetrieval(retrievalTokens("ABC abc"))
	if vec[26] != 2 || vec.cosine(vectorForRetrieval(retrievalTokens("abc"))) != 1 {
		t.Fatal(vec)
	}
}

func uploadRetrievalMaterial(t *testing.T, s *Service, project, text string) Material {
	t.Helper()
	var body bytes.Buffer
	form := multipart.NewWriter(&body)
	file, err := form.CreateFormFile("file", "fixture.txt")
	if err != nil {
		t.Fatal(err)
	}
	if _, err = fmt.Fprint(file, text); err != nil {
		t.Fatal(err)
	}
	if err = form.Close(); err != nil {
		t.Fatal(err)
	}
	r := httptest.NewRequest("POST", prefix+"/projects/"+project+"/materials", &body)
	r.Header.Set("Content-Type", form.FormDataContentType())
	w := httptest.NewRecorder()
	s.ServeHTTP(w, r)
	if w.Code != 201 {
		t.Fatalf("fixture upload failed: %d %s", w.Code, w.Body.String())
	}
	return decodeResearch[Material](t, w.Body.Bytes())
}
