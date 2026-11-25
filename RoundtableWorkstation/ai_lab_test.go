package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
)

func labTestRequest(t *testing.T, s *apiServer, method, path, body string) *httptest.ResponseRecorder {
	t.Helper()
	r := httptest.NewRequest(method, "/api/research/lab/"+path, strings.NewReader(body))
	w := httptest.NewRecorder()
	s.serveAILab(w, r)
	return w
}
func TestPersonalLabPresetsPersistAndRejectStaleEdit(t *testing.T) {
	dir := t.TempDir()
	prefs, err := openSettings(dir)
	if err != nil {
		t.Fatal(err)
	}
	service := &apiServer{prefs: prefs}
	w := labTestRequest(t, service, "GET", "presets", "")
	if w.Code != 200 {
		t.Fatal(w.Code)
	}
	const body = `{"title":"Derivation","mode":"review","seats":2,"prompt":"Review limiting cases."}`
	w = labTestRequest(t, service, "POST", "presets", body)
	if w.Code != 201 {
		t.Fatal(w.Code, w.Body.String())
	}
	var p labPreset
	if e := json.Unmarshal(w.Body.Bytes(), &p); e != nil {
		t.Fatal(e)
	}
	if p.ID == "" || p.Revision != 1 || p.Builtin {
		t.Fatal(p)
	}
	prefs, err = openSettings(dir)
	if err != nil {
		t.Fatal(err)
	}
	service = &apiServer{prefs: prefs}
	w = labTestRequest(t, service, "GET", "presets", "")
	if !strings.Contains(w.Body.String(), p.ID) {
		t.Fatal(w.Body.String())
	}
	edit := strings.Replace(body, "{", `{"revision":1,`, 1)
	w = labTestRequest(t, service, "PUT", "presets/"+p.ID, edit)
	if w.Code != 200 {
		t.Fatal(w.Code, w.Body.String())
	}
	w = labTestRequest(t, service, "PUT", "presets/"+p.ID, edit)
	if w.Code != 409 {
		t.Fatal(w.Code)
	}
	w = labTestRequest(t, service, "DELETE", "presets/"+p.ID, `{"revision":2}`)
	if w.Code != 204 {
		t.Fatal(w.Code)
	}
	w = labTestRequest(t, service, "DELETE", "presets/paper-reading", `{"revision":1}`)
	if w.Code != 404 {
		t.Fatal(w.Code)
	}
}

type labTestTransport http.HandlerFunc

func (h labTestTransport) RoundTrip(r *http.Request) (*http.Response, error) {
	w := httptest.NewRecorder()
	h(w, r)
	return w.Result(), nil
}

func TestReadOnlyMCPResourceSelection(t *testing.T) {
	var mu sync.Mutex
	var methods []string
	client := &http.Client{Transport: labTestTransport(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == "DELETE" {
			w.WriteHeader(204)
			return
		}
		var req struct {
			Method string
			ID     int
		}
		if json.NewDecoder(r.Body).Decode(&req) != nil {
			t.Error("malformed rpc")
			return
		}
		mu.Lock()
		methods = append(methods, req.Method)
		mu.Unlock()
		if req.Method != "initialize" && (r.Header.Get("Mcp-Session-Id") != "fixture-session" || r.Header.Get("MCP-Protocol-Version") != "2025-06-18") {
			t.Error("missing session negotiation")
		}
		switch req.Method {
		case "initialize":
			w.Header().Set("Mcp-Session-Id", "fixture-session")
			fmt.Fprint(w, `{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18","capabilities":{"resources":{}}}}`)
		case "notifications/initialized":
			w.WriteHeader(202)
		case "resources/list":
			w.Header().Set("Content-Type", "text/event-stream")
			fmt.Fprintf(w, "event: message\ndata: %s\n\n", `{"jsonrpc":"2.0","id":2,"result":{"resources":[{"uri":"urn:paper:x","name":"Paper abstract"}]}}`)
		case "resources/read":
			fmt.Fprint(w, `{"jsonrpc":"2.0","id":9,"result":{"contents":[{"uri":"urn:paper:x","text":"Quoted source text."}]}}`)
		default:
			t.Errorf("unexpected MCP call: %s", req.Method)
			w.WriteHeader(400)
		}
	})}
	const endpoint = "https://mcp.example/resource"
	x, err := labReadResources(context.Background(), client, endpoint, "urn:paper:x")
	if err != nil {
		t.Fatal(err)
	}
	result := x.(map[string]string)
	if result["uri"] != "urn:paper:x" || len(result["sha256"]) != 64 || result["text"] != "Quoted source text." {
		t.Fatal(result)
	}
	if _, err = labReadResources(context.Background(), client, endpoint, "urn:private:other"); err == nil {
		t.Fatal("accepted unlisted resource")
	}
	mu.Lock()
	defer mu.Unlock()
	if strings.Count(strings.Join(methods, ","), "resources/read") != 1 {
		t.Fatal(methods)
	}
}
