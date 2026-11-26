package main

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"

	"scistation.local/desktop/internal/meeting"
)

func TestBoardHTTPRequiresTargetVersionAndReturnsWinningSnapshot(t *testing.T) {
	e, err := meeting.New(t.TempDir(), func(context.Context, string, string, string, string) (string, error) {
		t.Error("board edits must not request a model")
		return "", nil
	}, func() meeting.Settings { return meeting.Settings{} })
	if err != nil {
		t.Fatal(err)
	}
	project, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	s, err := e.Create("Board HTTP", project, nil)
	if err != nil {
		t.Fatal(err)
	}
	handler := (&apiServer{meetings: e}).serve(8765)
	request := func(method, body string, status int) *httptest.ResponseRecorder {
		t.Helper()
		req := httptest.NewRequest(method, "http://127.0.0.1:8765/api/studio/sessions/"+s.ID+"/board", strings.NewReader(body))
		req.Header.Set("X-Roundtable", "1")
		req.Header.Set("Content-Type", "application/json")
		resp := httptest.NewRecorder()
		handler.ServeHTTP(resp, req)
		if resp.Code != status {
			t.Fatalf("%s %s: got %d, want %d: %s", method, body, resp.Code, status, resp.Body)
		}
		return resp
	}
	if request("GET", "", http.StatusMethodNotAllowed).Header().Get("Allow") != "POST" {
		t.Fatal("missing allowed method")
	}
	for _, invalid := range []string{
		`{"op":"rename_board","title":"No version"}`,
		`{"op":"rename_board","title":"One","title":"Two","expected_version":0}`,
		`{"op":"rename_board","title":"Forged","source_seat":"chair","expected_version":0}`,
		`{"op":"revise_module","module_id":"materials","body":null,"expected_version":0}`,
		`{"op":"annotate_point","point_id":"missing","body":"text","expected_version":0}`,
		`{"op":"annotate_material","material_id":"missing","body":"text","expected_version":0}`,
		`{"op":"revise_module","module_id":"materials","material_ids":["foreign"],"expected_version":0}`,
	} {
		request("POST", invalid, 400)
	}
	first := request("POST", `{"op":"rename_board","title":"Winner","expected_version":0}`, 200)
	var committed meeting.Session
	if err := json.Unmarshal(first.Body.Bytes(), &committed); err != nil || committed.Title != "Winner" || committed.Board.Version != 1 {
		t.Fatal(committed, err)
	}
	response := request("POST", `{"op":"rename_board","title":"Other tab","expected_version":0}`, 409)
	var stale struct {
		Error   string          `json:"error"`
		Session meeting.Session `json:"session"`
	}
	if err := json.Unmarshal(response.Body.Bytes(), &stale); err != nil || stale.Error == "" || stale.Session.ID != s.ID || stale.Session.Board.Title != "Winner" {
		t.Fatal(stale, err)
	}
	request("POST", `{"op":"rename_board","title":"Winner","expected_version":0}`, 200)
}

func TestBoardPresenceHTTPIsReadOnlyAndEphemeral(t *testing.T) {
	e, err := meeting.New(t.TempDir(), func(context.Context, string, string, string, string) (string, error) {
		t.Fatal("reading live cursors must not request a model")
		return "", nil
	}, func() meeting.Settings { return meeting.Settings{} })
	if err != nil {
		t.Fatal(err)
	}
	project, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	s, err := e.Create("Private meeting content", project, nil)
	if err != nil {
		t.Fatal(err)
	}
	serve := (&apiServer{meetings: e}).serve(8765)
	url := "http://127.0.0.1:8765/api/studio/sessions/" + s.ID + "/board-presence"
	for _, tc := range []struct {
		method, suffix string
		code           int
	}{
		{"GET", "", 200}, {"GET", "?after=-1", 400}, {"GET", "?after=0&after=0", 400}, {"POST", "", 405},
	} {
		req := httptest.NewRequest(tc.method, url+tc.suffix, nil)
		req.Header.Set("X-Roundtable", "1")
		req.Header.Set("Content-Type", "application/json")
		res := httptest.NewRecorder()
		serve.ServeHTTP(res, req)
		if res.Code != tc.code {
			t.Fatalf("%s %s: %d %s", tc.method, tc.suffix, res.Code, res.Body)
		}
		if tc.code == 200 {
			var body struct {
				SessionID string                `json:"session_id"`
				Cursors   []meeting.BoardCursor `json:"cursors"`
			}
			if err := json.Unmarshal(res.Body.Bytes(), &body); err != nil || body.SessionID != s.ID || body.Cursors == nil || len(body.Cursors) != 0 || strings.Contains(res.Body.String(), s.Topic) || res.Header().Get("Cache-Control") != "no-store" {
				t.Fatal("endpoint leaked session data or omitted snapshot", res.Body, err)
			}
		}
	}
}
