package desktop

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"scistation.local/desktop/internal/meeting"
	"scistation.local/desktop/internal/research"
)

func TestOldRestorePromptsForDraftWithoutAnyMeeting(t *testing.T) {
	root := t.TempDir()
	host := openNavigationFixture(t, root)
	a, b := projectTestDir(t), projectTestDir(t)
	p, err := registerFixtureDirectory(host.research, a)
	if err != nil {
		t.Fatal(err)
	}
	archive := filepath.Join(root, "studio")
	model := func(context.Context, string, string, string, string) (string, error) {
		t.Error("unexpected model request")
		return "", nil
	}
	rooms, err := meeting.New(archive, model, func() meeting.Settings { return meeting.Settings{} })
	if err != nil {
		t.Fatal(err)
	}
	if _, err = rooms.LabDraft(meeting.LabScope{ProjectID: p.ID}, "", &meeting.LabDraft{Text: "Original project draft"}); err != nil {
		t.Fatal(err)
	}
	if err = rooms.Shutdown(context.Background()); err != nil {
		t.Fatal(err)
	}

	// Model a previous release's restored record. The stable project ID and
	// draft survived, but the external grant and its path were cleared.
	filename := filepath.Join(root, "research", "records", p.ID+".json")
	data, err := os.ReadFile(filename)
	if err != nil {
		t.Fatal(err)
	}
	var fields map[string]json.RawMessage
	if err = json.Unmarshal(data, &fields); err != nil {
		t.Fatal(err)
	}
	var project map[string]json.RawMessage
	if err = json.Unmarshal(fields["project"], &project); err != nil {
		t.Fatal(err)
	}
	project["path"] = json.RawMessage(`""`)
	delete(project, "directoryGrant")
	fields["project"], err = json.Marshal(project)
	if err != nil {
		t.Fatal(err)
	}
	data, err = json.Marshal(fields)
	if err != nil {
		t.Fatal(err)
	}
	if err = os.WriteFile(filename, data, 0600); err != nil {
		t.Fatal(err)
	}

	host = openNavigationFixture(t, root)
	host.meetings, err = meeting.New(archive, model, func() meeting.Settings { return meeting.Settings{} })
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = host.meetings.Shutdown(context.Background()) })
	host.research.SetPathValidator(host.approvedResearchPath)
	chosen, err := research.IdentifyDirectory(b)
	if err != nil {
		t.Fatal(err)
	}
	host.selectedPaths.Store(b, chosen)
	dirAPI := "/api/research/projects/" + p.ID + "/directory"
	request := map[string]any{"path": b, "revision": p.Revision}
	var confirmation map[string]string
	rootFixtureRequest(t, host, "POST", dirAPI, request, 409, &confirmation)
	if confirmation["code"] != "confirmation_required" {
		t.Fatal(confirmation)
	}
	url := "/api/research/lab/draft?project=" + p.ID
	var draft meeting.LabDraft
	rootFixtureRequest(t, host, "GET", url, nil, 200, &draft)
	if draft.Text != "Original project draft" {
		t.Fatal(draft)
	}
	request["resetConversations"] = true
	var bound research.Project
	rootFixtureRequest(t, host, "POST", dirAPI, request, 200, &bound)
	if bound.Path != b || bound.ConversationGeneration != 1 {
		t.Fatal(bound)
	}
	rootFixtureRequest(t, host, "GET", url, nil, 409, nil)
	rootFixtureRequest(t, host, "GET", url+"&conversationGeneration=1", nil, 200, &draft)
	if draft.Text != "" || draft.Revision != 0 {
		t.Fatal("restored draft survived confirmed reset", draft)
	}
}
