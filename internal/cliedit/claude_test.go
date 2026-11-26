package cliedit

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"scistation.local/desktop/internal/workspace"
)

type fixtureClaudeSink struct {
	thread, turn, result string
	review               func(Request) (bool, error)
}

func (s *fixtureClaudeSink) Running(thread, turn string) error {
	s.thread, s.turn = thread, turn
	return nil
}
func (s *fixtureClaudeSink) Approval(_ context.Context, r Request) (bool, error) { return s.review(r) }
func (s *fixtureClaudeSink) Result(detail string)                                { s.result = detail }

func TestClaudeReviewBlocksUnselectedAndLinkedFiles(t *testing.T) {
	dir, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	doc := filepath.Join(dir, "paper.md")
	if err := os.WriteFile(doc, []byte("original\n"), 0600); err != nil {
		t.Fatal(err)
	}
	scope := Scope{Directory: dir, Paths: []string{"paper.md", "alias.md"}}
	path := func(file string) json.RawMessage {
		p, _ := json.Marshal(map[string]string{"file_path": file})
		return p
	}
	if _, _, err := selectedClaudeFile(scope, path(doc)); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(doc, filepath.Join(dir, "alias.md")); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"paper.md", filepath.Join(dir, "alias.md"), filepath.Join(dir, "unselected.md"), dir + "/../" + filepath.Base(dir) + "/paper.md"} {
		if _, _, err := selectedClaudeFile(scope, path(name)); err == nil {
			t.Fatalf("accepted %q", name)
		}
	}
	if err := os.Link(doc, filepath.Join(dir, "hardlink.md")); err != nil {
		t.Fatal(err)
	}
	if _, _, err := selectedClaudeFile(scope, path(doc)); err == nil {
		t.Fatal("accepted a multiply linked file")
	}
}

func TestClaudeExactProposal(t *testing.T) {
	p := claudePacket{RequestID: "req"}
	p.Request.ID = "tool"
	draft := func(text string, all bool, find string) (claudeEdit, Request, error) {
		p.Request.Input, _ = json.Marshal(map[string]any{"file_path": "/work/a.md", "old_string": find, "new_string": "new", "replace_all": all})
		return claudeProposal(p, "thread", "turn", "a.md", workspace.File{Text: text})
	}
	e, r, err := draft("one\nold\nold\n", true, "old")
	if err != nil || e.after != "one\nnew\nnew\n" || r.ItemID != "tool" || len(r.Changes) != 1 || !strings.Contains(r.Changes[0].Diff, "+new") {
		t.Fatal(e, r, err)
	}
	for _, s := range []string{"\n", "old\nold\n"} {
		if _, _, err := draft(s, false, "old"); err == nil {
			t.Fatal("accepted absent or ambiguous search")
		}
	}
}

func TestClaudePreviewPreservesCRLFAndBOM(t *testing.T) {
	p := claudePacket{RequestID: "r"}
	p.Request.Input = json.RawMessage(`{"file_path":"/work/a.md","old_string":"original","new_string":"reviewed\nnext"}`)
	edit, _, err := claudeProposal(p, "s", "t", "a.md", workspace.File{Text: "\ufefforiginal\r\n"})
	if err != nil || edit.after != "\ufeffreviewed\r\nnext\r\n" {
		t.Fatal(edit, err)
	}
	if _, _, err = claudeProposal(p, "s", "t", "a.md", workspace.File{Text: "original\r\nnext\n"}); err == nil {
		t.Fatal("approved ambiguous mixed endings")
	}
}

func TestClaudeSessionRequiresOnlyManualReadAndEdit(t *testing.T) {
	p := claudePacket{SessionID: "s", Cwd: "/work", PermissionMode: "default", Tools: []string{"Read", "Edit"}}
	if !p.validSession("/work") {
		t.Fatal("valid CLI rejected")
	}
	for _, bad := range []func(*claudePacket){
		func(p *claudePacket) { p.PermissionMode = "acceptEdits" }, func(p *claudePacket) { p.Tools = []string{"Read", "Bash"} }, func(p *claudePacket) { p.Cwd = "/other" }, func(p *claudePacket) { p.MCP = []json.RawMessage{json.RawMessage(`{}`)} }, func(p *claudePacket) { p.Directories = []string{"/other"} },
	} {
		m := p
		bad(&m)
		if m.validSession("/work") {
			t.Fatal("accepted broader permissions")
		}
	}
	for _, exe := range []string{"", "/fixture/cursor-agent"} {
		if available, reason := CursorAvailable(exe); available || reason == "" {
			t.Fatal("Cursor advertised writable")
		}
	}
}

func TestClaudeProtocolDeclinesUnselectedRead(t *testing.T) {
	var output bytes.Buffer
	lines := `{"type":"system","subtype":"init","session_id":"s","cwd":"/work","tools":["Read","Edit"],"permissionMode":"default"}
{"type":"assistant","session_id":"s","message":{"id":"turn","content":[{"type":"tool_use","name":"Read","id":"x"}]}}
{"type":"control_request","request_id":"r","request":{"subtype":"can_use_tool","tool_name":"Read","tool_use_id":"x","input":{"file_path":"/other/file.md"}}}
{"type":"result","session_id":"s"}`
	c := claudePipe{bufio.NewScanner(strings.NewReader(lines)), json.NewEncoder(&output)}
	if err := c.review(t.Context(), Scope{Directory: "/work", Paths: []string{"paper.md"}}, &fixtureClaudeSink{}); err == nil || !strings.Contains(output.String(), `"behavior":"deny"`) {
		t.Fatal(output.String(), err)
	}
}

// Reply with the Anthropic SSE fixture expected by the installed, unmodified CLI.
// No model, account, credentials, or project outside t.TempDir is used.
func serveClaudeFixture(w http.ResponseWriter, n int, path string) {
	w.Header().Set("Content-Type", "text/event-stream")
	event := func(kind string, fields map[string]any) {
		fields["type"] = kind
		b, _ := json.Marshal(fields)
		fmt.Fprintf(w, "event: %s\ndata: %s\n\n", kind, b)
	}
	usage := map[string]int{"input_tokens": 10, "output_tokens": 1}
	event("message_start", map[string]any{"message": map[string]any{"id": fmt.Sprintf("msg_fixture_%d", n), "type": "message", "role": "assistant", "model": "claude-sonnet-4-6", "content": []any{}, "usage": usage}})
	stop := "tool_use"
	if n <= 2 {
		name := "Read"
		input := map[string]string{"file_path": path}
		if n == 2 {
			name = "Edit"
			input["old_string"] = "original"
			input["new_string"] = "reviewed"
		}
		raw, _ := json.Marshal(input)
		event("content_block_start", map[string]any{"index": 0, "content_block": map[string]any{"type": "tool_use", "id": fmt.Sprintf("toolu_fixture_%d", n), "name": name, "input": map[string]any{}}})
		event("content_block_delta", map[string]any{"index": 0, "delta": map[string]string{"type": "input_json_delta", "partial_json": string(raw)}})
	} else {
		stop = "end_turn"
		event("content_block_start", map[string]any{"index": 0, "content_block": map[string]string{"type": "text", "text": ""}})
		event("content_block_delta", map[string]any{"index": 0, "delta": map[string]string{"type": "text_delta", "text": "Finished offline fixture."}})
	}
	event("content_block_stop", map[string]any{"index": 0})
	event("message_delta", map[string]any{"delta": map[string]any{"stop_reason": stop, "stop_sequence": nil}, "usage": map[string]int{"output_tokens": 5}})
	event("message_stop", map[string]any{})
}

func TestInstalledClaudeEditApproval(t *testing.T) {
	exe := os.Getenv("SCI_STATION_TEST_CLAUDE")
	if exe == "" {
		t.Skip("set SCI_STATION_TEST_CLAUDE to an installed Claude Code executable to run the offline CLI smoke")
	}
	if available, reason := ClaudeAvailable(exe); !available {
		t.Fatal(reason)
	}
	for _, accept := range []bool{false, true} {
		t.Run(fmt.Sprintf("allow_%t", accept), func(t *testing.T) {
			home := t.TempDir()
			dir, err := filepath.EvalSymlinks(t.TempDir())
			if err != nil {
				t.Fatal(err)
			}
			path := filepath.Join(dir, "paper.md")
			if err = os.WriteFile(path, []byte("original\n"), 0600); err != nil {
				t.Fatal(err)
			}
			// Project/user allow rules must not override the host's ask rule.
			for _, settings := range []string{filepath.Join(dir, ".claude"), filepath.Join(home, "config")} {
				if err = os.MkdirAll(settings, 0700); err != nil {
					t.Fatal(err)
				}
				if err = os.WriteFile(filepath.Join(settings, "settings.json"), []byte(`{"permissions":{"allow":["Edit","Bash"],"defaultMode":"acceptEdits"}}`), 0600); err != nil {
					t.Fatal(err)
				}
			}
			var requests atomic.Int32
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.URL.Path != "/v1/messages" {
					http.NotFound(w, r)
					return
				}
				var req struct{ Tools []struct{ Name string } }
				if err := json.NewDecoder(io.LimitReader(r.Body, 2<<20)).Decode(&req); err != nil {
					t.Error(err)
					return
				}
				for _, tool := range req.Tools {
					if !slices.Contains([]string{"Read", "Edit", "DeferredToolPlaceholder"}, tool.Name) {
						t.Errorf("unexpected model tool %s", tool.Name)
					}
				}
				serveClaudeFixture(w, int(requests.Add(1)), path)
			}))
			defer server.Close()
			ctx, cancel := context.WithTimeout(t.Context(), 18*time.Second)
			defer cancel()
			cmd := claudeCommand(ctx, exe)
			cmd.Dir = dir
			cmd.Env = []string{"HOME=" + home, "PATH=/usr/bin:/bin:/opt/homebrew/bin", "CLAUDE_CONFIG_DIR=" + filepath.Join(home, "config"), "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1", "ANTHROPIC_BASE_URL=" + server.URL, "ANTHROPIC_API_KEY=" + t.Name()}
			cmd.Args = append(cmd.Args, "--model", "sonnet")
			scope := Scope{Directory: dir, Paths: []string{"paper.md"}, Prompt: "Review the selected text."}
			var called int
			sink := &fixtureClaudeSink{}
			sink.review = func(r Request) (bool, error) {
				called++
				content, err := os.ReadFile(path)
				if err != nil || string(content) != "original\n" {
					t.Fatalf("file changed before approval: %s", content)
				}
				if r.ThreadID != sink.thread || r.TurnID != sink.turn || r.ItemID != "toolu_fixture_2" || len(r.Changes) != 1 || r.Changes[0].Path != "paper.md" || !strings.Contains(r.Changes[0].Diff, "+reviewed") {
					t.Fatal("incorrect native approval", r)
				}
				return accept, nil
			}
			if err := runClaudeCommand(ctx, cmd, scope, sink); err != nil {
				t.Fatal(err)
			}
			got, err := os.ReadFile(path)
			want := "original\n"
			if accept {
				want = "reviewed\n"
			}
			if err != nil || string(got) != want || called != 1 || sink.result == "" {
				t.Fatal(string(got), called, sink.result, err)
			}
		})
	}
}
