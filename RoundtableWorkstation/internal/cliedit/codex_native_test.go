package cliedit

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// A real installed CLI handles local fixture responses and performs the edit.
// The fixture supplies no account, production service or remote inference.
func TestInstalledCodexFileReview(t *testing.T) {
	exe := os.Getenv("SCI_STATION_TEST_CODEX")
	if exe == "" {
		t.Skip("set SCI_STATION_TEST_CODEX to an installed Codex executable")
	}
	for _, allow := range []bool{false, true} {
		t.Run(fmt.Sprintf("allow-%t", allow), func(t *testing.T) {
			home := t.TempDir()
			project, err := filepath.EvalSymlinks(t.TempDir())
			if err != nil {
				t.Fatal(err)
			}
			var toolNames []string
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.Method != "POST" || !strings.HasSuffix(r.URL.Path, "/responses") {
					http.NotFound(w, r)
					return
				}
				body, _ := io.ReadAll(io.LimitReader(r.Body, 4<<20))
				var request struct {
					Tools []struct {
						Name  string
						Type  string
						Tools []struct{ Name string }
					}
				}
				_ = json.Unmarshal(body, &request)
				if len(toolNames) == 0 {
					for _, v := range request.Tools {
						toolNames = append(toolNames, v.Name+":"+v.Type)
						for _, inner := range v.Tools {
							toolNames = append(toolNames, v.Name+"."+inner.Name)
						}
					}
				}

				w.Header().Set("Content-Type", "text/event-stream")
				send := func(typ string, entry map[string]any) {
					entry["type"] = typ
					b, _ := json.Marshal(entry)
					fmt.Fprintf(w, "event: %s\ndata: %s\n\n", typ, b)
				}
				send("response.created", map[string]any{"response": map[string]any{"id": "resp_fixture", "status": "in_progress"}})
				if !bytes.Contains(body, []byte(`"custom_tool_call_output"`)) && !bytes.Contains(body, []byte(`"function_call_output"`)) {
					item := map[string]any{"type": "custom_tool_call", "name": "apply_patch", "call_id": "fixture_patch", "id": "ct_fixture", "input": "*** Begin Patch\n*** Update File: result.md\n@@\n-original\n+reviewed\n*** End Patch"}
					send("response.output_item.done", map[string]any{"output_index": 0, "item": item})
				} else {
					send("response.output_item.done", map[string]any{"output_index": 0, "item": map[string]any{"type": "message", "id": "msg_fixture", "role": "assistant", "content": []any{map[string]string{"type": "output_text", "text": "Finished."}}}})
				}
				send("response.completed", map[string]any{"response": map[string]any{"id": "resp_fixture", "status": "completed", "output": []any{}}})
			}))
			defer server.Close()
			config := fmt.Sprintf("model_provider='offline_fixture'\nmodel='gpt-6.2-sol'\napproval_policy='on-request'\n[model_providers.offline_fixture]\nname='Offline fixture'\nbase_url=%q\nwire_api='responses'\nrequires_openai_auth=false\nsupports_websockets=false\n[mcp_servers.fixture_tool]\ncommand='/usr/bin/false'\n", server.URL)
			if err := os.WriteFile(filepath.Join(home, "config.toml"), []byte(config), 0600); err != nil {
				t.Fatal(err)
			}
			path := filepath.Join(project, "result.md")
			if err := os.WriteFile(path, []byte("original\n"), 0600); err != nil {
				t.Fatal(err)
			}
			ctx, cancel := context.WithTimeout(context.Background(), 35*time.Second)
			defer cancel()
			env := []string{"HOME=" + home, "CODEX_HOME=" + home, "PATH=/usr/bin:/bin", "RUST_LOG=off", "TMPDIR=" + home, "NO_PROXY=127.0.0.1,localhost"}
			cmd, err := scopedCodexCommand(ctx, exe, project, env)
			if err != nil {
				t.Fatal(err)
			}

			// No real credential can be inherited through the test child's environment.
			sink := &fixtureSink{scope: Scope{Directory: project, Paths: []string{"result.md"}, Prompt: "Revise the selected text."}, allow: allow}
			err = withConnection(ctx, cmd, func(c conn) error { return c.edit(sink.scope, sink) })
			if err != nil {
				t.Fatalf("%v; observed requests=%d; model tools=%v", err, sink.requests, toolNames)
			}
			if sink.requests != 1 {
				t.Fatalf("wanted one real CLI approval, got %d; tools=%v, detail=%s", sink.requests, toolNames, sink.detail)
			}
			data, err := os.ReadFile(path)
			if err != nil {
				t.Fatal(err)
			}
			want := "original\n"
			if allow {
				want = "reviewed\n"
			}
			if string(data) != want {
				t.Fatalf("after native decision: %q", data)
			}
		})
	}
}

type fixtureSink struct {
	scope    Scope
	allow    bool
	requests int
	detail   string
}

func (s *fixtureSink) Running(thread, turn string) error {
	if thread == "" || turn == "" {
		return fmt.Errorf("missing IDs")
	}
	return nil
}
func (s *fixtureSink) Approval(ctx context.Context, r Request) (bool, error) {
	s.requests++
	if len(r.Changes) != 1 || r.Changes[0].Path != "result.md" || !strings.Contains(r.Changes[0].Diff, "reviewed") {
		return false, fmt.Errorf("unexpected fixture change")
	}
	return s.allow, nil
}
func (s *fixtureSink) Result(detail string) { s.detail = detail }

// This opt-in diagnostic opens an ephemeral, read-only CLI thread with the
// installed settings. It sends no turn, prompt or model request.
func TestInstalledCodexConfiguredScope(t *testing.T) {
	exe := os.Getenv("SCI_STATION_TEST_CONFIGURED_CODEX")
	if exe == "" {
		t.Skip("set SCI_STATION_TEST_CONFIGURED_CODEX to probe installed CLI configuration")
	}
	dir, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(t.Context(), 20*time.Second)
	defer cancel()
	cmd, err := scopedCodexCommand(ctx, exe, dir, nil)
	if err != nil {
		t.Fatal(err)
	}
	if err = withConnection(ctx, cmd, func(c conn) error { _, err := c.startThread(dir); return err }); err != nil {
		t.Fatal(err)
	}
}
