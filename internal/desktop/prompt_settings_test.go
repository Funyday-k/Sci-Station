package desktop

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"scistation.local/desktop/internal/deliberation"
	"scistation.local/desktop/internal/meeting"
)

func settingsRequest(t *testing.T, h http.Handler, method, path string, payload any, want int) []byte {
	t.Helper()
	body, err := json.Marshal(payload)
	if err != nil {
		t.Fatal(err)
	}
	r := httptest.NewRequest(method, "http://127.0.0.1:8765/api/studio/"+path, bytes.NewReader(body))
	r.Header.Set("X-Roundtable", "1")
	r.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	if w.Code != want {
		t.Fatalf("%s %s: got %d; want %d: %s", method, path, w.Code, want, w.Body.Bytes())
	}
	return w.Body.Bytes()
}

func TestPromptSettingsReviewRestoreAndRuntime(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "settings.json"), []byte(`{"appearance":"dark","timeout":90,"allow_edits":true}`), 0600); err != nil {
		t.Fatal(err)
	}
	prefs, err := openSettings(dir)
	if err != nil {
		t.Fatal(err)
	}
	h := (&apiServer{prefs: prefs}).serve(8765)
	library := func() promptLibrary {
		return scienceWorkflowDecode[promptLibrary](t, settingsRequest(t, h, "GET", "prompt-settings", nil, 200))
	}
	preview := func(v int, action string, tmpl promptTemplate, want int) promptPatchReview {
		resp := settingsRequest(t, h, "POST", "prompt-settings/preview", promptPatchInput{v, action, tmpl}, want)
		if want != 200 {
			return promptPatchReview{}
		}
		return scienceWorkflowDecode[promptPatchReview](t, resp)
	}
	decide := func(id, action string, want int) {
		settingsRequest(t, h, "POST", "prompt-settings/decision", map[string]string{"id": id, "action": action}, want)
	}
	agenda := promptTemplate{PromptOverride: meeting.PromptOverride{Surface: meeting.PromptPlanner, Body: "Planner fixture instruction."},
		Title: "Agenda workspace", Enabled: true, Active: true}
	base := library()
	if base.Revision != 0 || len(base.Templates) != 0 || prefs.get().AllowEdits || !prefs.get().ToolBudget.AutoRead {
		t.Fatal(base)
	}
	first := preview(base.Revision, "suggest", agenda, 200)
	if !strings.Contains(first.Changes[0].After.Body, "scientific claims") || len(library().Templates) != 0 {
		t.Fatal("preview should provide a concrete proposal without writing settings")
	}
	decide(first.ID, "discard", 200)
	decide(first.ID, "apply", 409)
	afterDiscard, err := openSettings(dir)
	if err != nil || afterDiscard.get().PromptLibrary != nil {
		t.Fatal("discard persisted a draft", err)
	}
	first = preview(base.Revision, "edit", agenda, 200)
	decide(first.ID, "apply", 200)
	preview(base.Revision, "edit", agenda, 409)
	decide(first.ID, "apply", 409)
	for _, sample := range []struct {
		surface meeting.PromptSurface
		body    string
	}{
		{meeting.PromptToolLoop, "Tool-loop fixture instruction."},
		{meeting.PromptPaperSummary, "Paper-summary fixture instruction."},
	} {
		input := agenda
		input.Surface, input.Body = sample.surface, sample.body
		next := preview(library().Revision, "edit", input, 200)
		decide(next.ID, "apply", 200)
	}
	saved, err := openSettings(dir)
	if err != nil {
		t.Fatal(err)
	}
	if saved.get().Appearance != "dark" || saved.get().Timeout != 90 || saved.get().AllowEdits {
		t.Fatal("prompt confirmation changed unrelated preferences")
	}
	called := make(chan string, 6)
	engine, err := meeting.New(filepath.Join(dir, "sessions"), func(ctx context.Context, _, _, prompt, _ string) (string, error) {
		called <- deliberation.InstructionsFrom(ctx)
		if strings.HasPrefix(prompt, "AGENDA DRAFT REQUEST") {
			return `{"agenda":[{"title":"Review assumptions","kind":"discussion"}]}`, nil
		}
		return `{"action":"say","text":"Fixture completed."}`, nil
	}, saved.meetingSettings)
	if err != nil {
		t.Fatal(err)
	}
	defer engine.Shutdown(context.Background())
	workspaceScope := meeting.ProjectScope{Global: true}
	newSession := func(topic string) *meeting.Session {
		t.Helper()
		room, err := engine.CreateScopedConfiguredWithMaterials(topic, workspaceScope, []meeting.Member{{Model: "test-model", Effort: "auto"}}, "review", nil, nil)
		if err != nil {
			t.Fatal(err)
		}
		return room
	}
	requireInstructions := func(want string, absent ...string) {
		t.Helper()
		select {
		case instructions := <-called:
			if !strings.Contains(instructions, want) {
				t.Fatalf("request did not include %q: %s", want, instructions)
			}
			for _, part := range absent {
				if strings.Contains(instructions, part) {
					t.Fatalf("request included guidance from the wrong surface %q", part)
				}
			}
		case <-time.After(5 * time.Second):
			t.Fatal("model request timed out")
		}
	}
	room := newSession("General fixture discussion")
	if _, err = engine.StartAgendaDraft(room.ID, &room.AgendaVersion); err != nil {
		t.Fatal(err)
	}
	requireInstructions("Planner fixture instruction.", "Tool-loop fixture instruction.", "Paper-summary fixture instruction.")
	room = newSession("General fixture discussion after restart")
	started, err := engine.Start(room.ID, "", "", 0)
	if err != nil || started.Rounds[0].PromptOverride.Digest == "" || started.Rounds[0].PromptOverride.Version != 1 {
		t.Fatal("missing captured override identity", err)
	}
	requireInstructions("Tool-loop fixture instruction.", "Planner fixture instruction.", "Paper-summary fixture instruction.")
	room = newSession("科研工作流 · 单席论文精读\n工作流 ID：paper-reading\nRead this paper.")
	if _, err = engine.Start(room.ID, "", "", 0); err != nil {
		t.Fatal(err)
	}
	requireInstructions("Paper-summary fixture instruction.", "Planner fixture instruction.", "Tool-loop fixture instruction.")

	updated := library()
	restore := preview(updated.Revision, "restore", promptTemplate{PromptOverride: meeting.PromptOverride{Surface: meeting.PromptToolLoop}}, 200)
	decide(restore.ID, "apply", 200)
	restored, err := openSettings(dir)
	if err != nil || restored.meetingSettings().PromptOverrides[meeting.PromptToolLoop] != nil ||
		restored.meetingSettings().PromptOverrides[meeting.PromptPaperSummary] == nil || len(library().Templates) != 3 {
		t.Fatal("restore should deactivate only the selected surface", err)
	}
	secret := agenda
	// Use a synthetic private-key header recognized without a real credential.
	secret.Body = "-----BEGIN PRIVATE KEY-----"
	preview(library().Revision, "edit", secret, 400)
}

func TestModelReadReviewAndBudgetThroughStudio(t *testing.T) {
	dir := t.TempDir()
	prefs, err := openSettings(dir)
	if err != nil {
		t.Fatal(err)
	}
	project, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	writeProject := func(name, body string) {
		t.Helper()
		if err := os.WriteFile(filepath.Join(project, name), []byte(body), 0600); err != nil {
			t.Fatal(err)
		}
	}
	writeProject("first.md", "DENIED_PRIVATE_EVIDENCE")
	writeProject("second.md", "APPROVED_EVIDENCE "+strings.Repeat("中", 1200)+"CLIPPED_END")
	writeProject("third.md", "EXTRA_PRIVATE_EVIDENCE")
	prompts := make(chan string, 6)
	var calls atomic.Int32
	engine, err := meeting.New(filepath.Join(dir, "sessions"), func(_ context.Context, _, _, prompt, _ string) (string, error) {
		prompts <- prompt
		switch calls.Add(1) {
		case 1:
			return `{"action":"read","path":"first.md"}`, nil
		case 2:
			return `{"action":"read","path":"second.md"}`, nil
		case 3:
			return `{"action":"read","path":"third.md"}`, nil
		default:
			return `{"action":"say","text":"Checked the approved excerpt."}`, nil
		}
	}, prefs.meetingSettings)
	if err != nil {
		t.Fatal(err)
	}
	defer engine.Shutdown(context.Background())
	h := (&apiServer{prefs: prefs, meetings: engine}).serve(8765)
	settingsRequest(t, h, "POST", "settings", map[string]any{"tool_budget": meeting.ToolBudget{
		MaxCalls: 2, ContextChars: 80000, PerResult: 1000, TotalResults: 5000, AutoRead: false,
	}}, 200)
	room, err := engine.Create("Temporarily inspect a research file", project, []string{"codex"})
	if err != nil {
		t.Fatal(err)
	}
	base := "sessions/" + room.ID + "/"
	settingsRequest(t, h, "POST", base+"run", map[string]int{"expected_round": 0}, 202)
	awaitApproval := func(expected string) meeting.ReadReview {
		t.Helper()
		deadline := time.Now().Add(5 * time.Second)
		for time.Now().Before(deadline) {
			body := settingsRequest(t, h, "GET", base+"read-review", nil, 200)
			if review := scienceWorkflowDecode[*meeting.ReadReview](t, body); review != nil {
				if review.Target != expected || review.Seat != "codex" {
					t.Fatal("review target mismatch", review)
				}
				return *review
			}
			time.Sleep(10 * time.Millisecond)
		}
		t.Fatal("read approval did not appear", expected)
		return meeting.ReadReview{}
	}
	assertNoEarlyReads := func() {
		t.Helper()
		fresh, err := engine.Get(room.ID)
		if err != nil || len(fresh.Rounds[0].Turns[0].Reads) != 0 {
			t.Fatal("read recorded before permission", err)
		}
	}
	declined := awaitApproval("first.md")
	assertNoEarlyReads()
	settingsRequest(t, h, "POST", base+"read-review", map[string]string{"id": declined.ID, "action": "deny"}, 204)
	allowed := awaitApproval("second.md")
	assertNoEarlyReads()
	settingsRequest(t, h, "POST", base+"read-review", map[string]string{"id": declined.ID, "action": "allow"}, 409)
	settingsRequest(t, h, "POST", base+"read-review", map[string]string{"id": allowed.ID, "action": "allow"}, 204)
	settingsRequest(t, h, "POST", base+"read-review", map[string]string{"id": allowed.ID, "action": "allow"}, 409)

	requestPrompt := func() string {
		t.Helper()
		select {
		case prompt := <-prompts:
			return prompt
		case <-time.After(5 * time.Second):
			t.Fatal("model request did not arrive")
			return ""
		}
	}
	requestPrompt()
	afterDeny, afterAllow, afterLimit := requestPrompt(), requestPrompt(), requestPrompt()
	if strings.Contains(afterDeny, "DENIED_PRIVATE_EVIDENCE") || !strings.Contains(afterDeny, "用户拒绝") ||
		!strings.Contains(afterAllow, "APPROVED_EVIDENCE") || !strings.Contains(afterAllow, "truncated") ||
		strings.Contains(afterAllow, "CLIPPED_END") || !strings.Contains(afterLimit, "工具调用上限") ||
		strings.Contains(afterLimit, "EXTRA_PRIVATE_EVIDENCE") || engine.PendingReadReview(room.ID) != nil {
		t.Fatal("manual review, result clipping or call limit was bypassed")
	}
	settingsRequest(t, h, "POST", "settings", map[string]any{"tool_budget": meeting.ToolBudget{
		MaxCalls: 2, ContextChars: 1000, PerResult: 1000, TotalResults: 1000, AutoRead: true,
	}}, 200)
	different, err := engine.Create("Context limit fixture", project, []string{"codex"})
	if err != nil {
		t.Fatal(err)
	}
	settingsRequest(t, h, "POST", "sessions/"+different.ID+"/run", map[string]int{"expected_round": 0}, 202)
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		fresh, err := engine.Get(different.ID)
		if err != nil {
			t.Fatal(err)
		}
		if fresh.Status != "running" {
			if !strings.Contains(fresh.Rounds[0].Turns[0].Error, "上下文超过工具预算") || calls.Load() != 4 {
				t.Fatal("provider received an over-budget request")
			}
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatal("over-budget round did not finish")
}
