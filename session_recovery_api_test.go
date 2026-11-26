package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"scistation.local/desktop/internal/meeting"
	"scistation.local/desktop/internal/sessionstore"
)

func TestSessionStorageRecoveryAPI(t *testing.T) {
	const (
		good = "10000000000000000000000000000000"
		bad  = "20000000000000000000000000000000"
	)
	for _, variant := range []struct {
		name, route, lock string
		start             func(string) (http.Handler, error)
	}{
		{"Studio", "/api/studio/sessions", ".meeting.lock", func(dir string) (http.Handler, error) {
			engine, err := meeting.New(dir, func(context.Context, string, string, string, string) (string, error) {
				return "", fmt.Errorf("interrupted work was replayed")
			}, func() meeting.Settings { return meeting.Settings{} })
			if err != nil {
				return nil, err
			}
			return (&apiServer{meetings: engine}).serve(8765), nil
		}},
	} {
		t.Run(variant.name, func(t *testing.T) {
			dir, err := filepath.EvalSymlinks(t.TempDir())
			if err != nil {
				t.Fatal(err)
			}
			goodPath := filepath.Join(dir, good+".json")
			goodData := fmt.Appendf(nil, `{"id":%q,"topic":"healthy meeting","seats":["codex","cursor"],"status":"running","rounds":[{"number":1,"turns":[{"seat":"codex","model":"codex","status":"done","text":"preserved"},{"seat":"cursor","model":"cursor","status":"running","text":"partial reply"}]}]}`, good)
			if err := os.WriteFile(goodPath, goodData, 0600); err != nil {
				t.Fatal(err)
			}
			badPath := filepath.Join(dir, bad+".json")
			badData := []byte(`{"topic":"truncated`)
			if err := os.WriteFile(badPath, badData, 0600); err != nil {
				t.Fatal(err)
			}

			handler, err := variant.start(dir)
			if err != nil {
				t.Fatalf("single invalid file blocked startup: %v", err)
			}
			get := func(path string, status int, out any) {
				t.Helper()
				r := httptest.NewRequest(http.MethodGet, "http://localhost:8765"+path, nil)
				w := httptest.NewRecorder()
				handler.ServeHTTP(w, r)
				if w.Code != status {
					t.Fatalf("GET %s = %d; want %d; %s", path, w.Code, status, w.Body)
				}
				if out != nil {
					if err := json.Unmarshal(w.Body.Bytes(), out); err != nil {
						t.Fatal(err)
					}
				}
			}
			var list struct {
				Sessions   []meeting.Summary         `json:"sessions"`
				Unreadable []sessionstore.Unreadable `json:"unreadable_sessions"`
			}
			get(variant.route, http.StatusOK, &list)
			if len(list.Sessions) != 1 || list.Sessions[0].ID != good || list.Sessions[0].Status != "partial" {
				t.Fatalf("healthy interrupted session missing or unrecovered: %+v", list.Sessions)
			}
			if len(list.Unreadable) != 1 || list.Unreadable[0].ID != bad || list.Unreadable[0].Path != badPath || list.Unreadable[0].Reason == "" {
				t.Fatalf("bad session location missing: %+v", list.Unreadable)
			}
			var detail struct {
				Unreadable sessionstore.Unreadable `json:"unreadable_session"`
			}
			get(variant.route+"/"+bad, http.StatusUnprocessableEntity, &detail)
			if detail.Unreadable != list.Unreadable[0] {
				t.Fatalf("bad session detail differs from list: %+v", detail)
			}
			var healthy meeting.Session
			get(variant.route+"/"+good, http.StatusOK, &healthy)
			turns := healthy.Rounds[0].Turns
			if healthy.Status != "partial" || turns[0].Text != "preserved" || turns[1].Text != "partial reply" || turns[1].Status != "error" {
				t.Fatalf("interrupted work recovered incorrectly: %+v", turns)
			}
			contents, err := os.ReadFile(badPath)
			if err != nil || !bytes.Equal(contents, badData) {
				t.Fatalf("bad archive changed: %q, %v", contents, err)
			}
			if _, err := os.Stat(filepath.Join(dir, bad+".run.lock")); !os.IsNotExist(err) {
				t.Fatalf("bad archive unexpectedly acquired a run lease: %v", err)
			}

			lockPath := filepath.Join(dir, variant.lock)
			if err := os.Remove(lockPath); err != nil {
				t.Fatal(err)
			}
			if err := os.Mkdir(lockPath, 0700); err != nil {
				t.Fatal(err)
			}
			get(variant.route, http.StatusInternalServerError, nil)
			if _, err := variant.start(dir); err == nil {
				t.Fatal("startup ignored a storage lock failure")
			}
		})
	}
}
