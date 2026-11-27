package desktop

import (
	"bytes"
	"context"
	"encoding/json"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"slices"
	"strings"
	"testing"
	"time"

	"scistation.local/desktop/internal/credentials"
	"scistation.local/desktop/internal/research"
)

type connectorFixture struct {
	t                   *testing.T
	api                 *apiServer
	project, other, dir string
	client              *http.Client
}

func setupConnector(t *testing.T) *connectorFixture {
	t.Helper()
	a, dir, p, q := labSettingsFixture(t)
	a.desktop = true
	a.minerCreds = newMinerCredentials(&mockMinerKeychain{})
	stores := map[string]*mockMinerKeychain{}
	a.labConnect.key = func(id, endpoint string) credentials.Store {
		key := id + " " + endpoint
		if stores[key] == nil {
			stores[key] = &mockMinerKeychain{}
		}
		return stores[key]
	}
	return &connectorFixture{t, a, p.ID, q.ID, dir, nil}
}
func (f *connectorFixture) request(path string, in labConnectorRequest, proof string, code int) []byte {
	f.t.Helper()
	b, err := json.Marshal(in)
	if err != nil {
		f.t.Fatal(err)
	}
	r := httptest.NewRequest("POST", "/api/research/lab/connectors/"+path, bytes.NewReader(b))
	r.Header.Set("X-Sci-Station-Connector-Session", proof)
	w := httptest.NewRecorder()
	f.api.serveLabConnector(w, r, path, f.client)
	if w.Code != code {
		f.t.Fatalf("%s: got %d expected %d: %s", path, w.Code, code, w.Body.String())
	}
	return w.Body.Bytes()
}
func (f *connectorFixture) post(path string, in labConnectorRequest, code int) []byte {
	f.t.Helper()
	return f.request(path, in, f.api.minerCreds.labProof, code)
}
func (f *connectorFixture) configure(c research.LabConnector) labConnectorRequest {
	f.t.Helper()
	in := labConnectorRequest{ProjectID: f.project, ID: c.ID, Connection: &c, Revision: 1, Confirmed: true}
	f.request("save", in, f.api.minerCreds.proof, 403)
	cfg := scienceWorkflowDecode[labContextResponse](f.t, f.post("save", in, 200))
	if len(cfg.Connections) != 1 {
		f.t.Fatal(cfg)
	}
	return labConnectorRequest{ProjectID: f.project, ID: c.ID, Revision: cfg.Revision}
}
func (f *connectorFixture) prepare(in labConnectorRequest) labConnectorRequest {
	f.t.Helper()
	v := scienceWorkflowDecode[map[string]string](f.t, f.post("prepare", in, 200))
	if v["ticket"] == "" || !strings.Contains(v["summary"], in.ID) {
		f.t.Fatal(v)
	}
	in.Ticket = v["ticket"]
	in.Confirmed = true
	return in
}

const connectorScript = `import json, sys, os
log = sys.argv[1]
assert "SCI_FIXTURE_PARENT_TOKEN" not in os.environ
assert os.path.samefile(os.getcwd(), os.environ["HOME"])
for line in sys.stdin:
    msg = json.loads(line)
    method, params = msg["method"], msg.get("params", {})
    with open(log,"a") as f: f.write(method+"\n")
    if method == "notifications/initialized": continue
    if method == "initialize":
        out={"protocolVersion":"2025-06-18","capabilities":{"resources":{},"tools":{}}}
    elif method == "resources/list":
        out={"resources":[{"uri":"fixture:paper","name":"Paper"}]}
    elif method == "resources/read":
        out={"contents":[{"uri":params["uri"],"text":"Verified fixture text"}]}
    elif method == "tools/list":
        out={"tools":[{"name":name,"annotations":hint,"inputSchema":{"type":"object"}} for name,hint in [
            ("lookup",{"readOnlyHint":True}),("write",{}),("unsafe",{"readOnlyHint":True,"destructiveHint":True}),("other",{"readOnlyHint":True})]]}
    elif method == "tools/call": out={"content":[{"type":"text","text":params["arguments"]["query"]}]}
    else: raise RuntimeError("unexpected request")
    print(json.dumps({"jsonrpc":"2.0","id":msg["id"],"result":out}),flush=True)
`

func TestLabConnectorRealStdioScopedConsentAndVersion(t *testing.T) {
	f := setupConnector(t)
	t.Setenv("SCI_FIXTURE_PARENT_TOKEN", "fixture-only")
	script, log := filepath.Join(t.TempDir(), "read.py"), filepath.Join(t.TempDir(), "calls")
	py, err := exec.LookPath("python3")
	if err != nil {
		t.Fatal(err)
	}
	if err = os.WriteFile(script, []byte(connectorScript), 0600); err != nil {
		t.Fatal(err)
	}
	c := research.LabConnector{ID: "papers", Transport: "stdio", Enabled: true, Program: py, Arguments: []string{script, log}, Tools: []string{"lookup", "write", "unsafe"}}
	in := f.configure(c)
	query := in
	query.Action = "tools/list"
	f.post("prepare", query, 403)
	if _, e := os.Stat(log); !os.IsNotExist(e) {
		t.Fatal("untrusted connector started")
	}
	op := in
	op.Confirmed = true
	f.post("trust", op, 200)
	wrong := query
	wrong.ProjectID = f.other
	wrong.Revision = 1
	f.post("prepare", wrong, 404)
	pending := f.prepare(query)
	if _, e := os.Stat(log); !os.IsNotExist(e) {
		t.Fatal("process started before confirmation")
	}
	f.post("untrust", op, 200)
	f.post("trust", op, 200)
	f.post("execute", pending, 403)
	pending = f.prepare(query)
	result := scienceWorkflowDecode[struct {
		Data    []labToolView
		Receipt map[string]string
	}](t, f.post("execute", pending, 200))
	if len(result.Data) != 1 || result.Data[0].Name != "lookup" || result.Receipt["projectId"] != f.project {
		t.Fatal(result)
	}
	f.post("execute", pending, 403)
	query.Action = "tools/call"
	query.Target = "lookup"
	query.Definition = result.Data[0].Definition
	query.Arguments = map[string]any{"query": "one"}
	pending = f.prepare(query)
	pending.Arguments = map[string]any{"query": "changed"}
	f.post("execute", pending, 403)
	pending = f.prepare(query)
	out := scienceWorkflowDecode[struct{ Data, Receipt map[string]string }](t, f.post("execute", pending, 200))
	if out.Data["text"] != "one" || out.Receipt["argumentsHash"] != labJSONDigest(query.Arguments) {
		t.Fatal(out)
	}
	bad := query
	bad.Target = "other"
	f.post("prepare", bad, 422)
	bad = query
	bad.Definition = strings.Repeat("0", 64)
	f.post("execute", f.prepare(bad), 422)
	bad = query
	bad.Target = "unsafe"
	f.post("execute", f.prepare(bad), 422)
	resources := in
	resources.Action = "resources/list"
	f.post("execute", f.prepare(resources), 200)
	resources.Action = "resources/read"
	resources.Target = "fixture:missing"
	f.post("execute", f.prepare(resources), 422)
	resources.Target = "fixture:paper"
	f.post("execute", f.prepare(resources), 200)
	raw, _ := os.ReadFile(log)
	if strings.Count(string(raw), "tools/call") != 1 || strings.Count(string(raw), "resources/read") != 1 {
		t.Fatal(string(raw))
	}
	srv, err := research.New(f.dir)
	if err != nil {
		t.Fatal(err)
	}
	f.api.research = srv
	before := f.prepare(query)
	if err = os.WriteFile(script, []byte(connectorScript+"\n# updated"), 0600); err != nil {
		t.Fatal(err)
	}
	f.post("execute", before, 422)
	after, _ := os.ReadFile(log)
	if !bytes.Equal(after, raw) {
		t.Fatal("replaced script launched")
	}
	old := c
	c.Enabled = false
	op.Connection = &c
	f.post("save", op, 200)
	query.Revision++
	f.post("prepare", query, 403)
	op.Revision++
	op.Connection = &old
	f.post("save", op, 200)
	query.Revision++
	f.post("prepare", query, 403)
	op.Connection = nil
	op.Revision++
	f.post("remove", op, 200)
}

func TestLabConnectorAuthenticatedTLSAndFailure(t *testing.T) {
	f := setupConnector(t)
	const credential = "local-fixture-0123456789"
	methods := make(chan string, 64)
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer "+credential {
			http.Error(w, "unauthorized", 401)
			return
		}
		if r.Method == "DELETE" {
			methods <- "DELETE"
			w.WriteHeader(204)
			return
		}
		var in struct {
			Method string
			ID     int
			Params struct {
				URI       string
				Name      string
				Arguments map[string]any
			}
		}
		if json.NewDecoder(r.Body).Decode(&in) != nil {
			t.Error("invalid JSON")
			return
		}
		methods <- in.Method
		var result any
		switch in.Method {
		case "initialize":
			w.Header().Set("Mcp-Session-Id", "fixture")
			result = map[string]any{"protocolVersion": "2025-06-18", "capabilities": map[string]any{"tools": map[string]any{}}}
		case "notifications/initialized":
			w.WriteHeader(202)
			return
		case "tools/list":
			result = map[string]any{"tools": []any{map[string]any{"name": "lookup", "annotations": map[string]any{"readOnlyHint": true}, "inputSchema": map[string]any{"type": "object"}}}}
		case "tools/call":
			text := in.Params.Arguments["query"]
			if text == "echo-key" {
				text = credential
			}
			result = map[string]any{"content": []any{map[string]any{"type": "text", "text": text}}}
		default:
			t.Errorf("unexpected method %s", in.Method)
			w.WriteHeader(400)
			return
		}
		if in.Method != "initialize" && r.Header.Get("Mcp-Session-Id") != "fixture" {
			t.Error("missing session")
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"jsonrpc": "2.0", "id": in.ID, "result": result})
	}))
	defer server.Close()
	fixtureURL, _ := url.Parse(server.URL)
	transport := server.Client().Transport.(*http.Transport).Clone()
	transport.DialContext = func(ctx context.Context, network, _ string) (net.Conn, error) {
		return (&net.Dialer{}).DialContext(ctx, network, fixtureURL.Host)
	}
	f.client = &http.Client{Transport: transport, CheckRedirect: research.PublicResourceClient().CheckRedirect}
	defer transport.CloseIdleConnections()
	c := research.LabConnector{ID: "fixtures", Transport: "https", Endpoint: "https://example.com/mcp", Bearer: true, Enabled: true, Tools: []string{"lookup"}}
	in := f.configure(c)
	op := in
	op.Confirmed = true
	f.post("trust", op, 200)
	list := in
	list.Action = "tools/list"
	f.post("execute", f.prepare(list), 422)
	if len(methods) != 0 {
		t.Fatal("missing credential contacted server")
	}
	op.Token = credential
	f.post("set-token", op, 200)
	op.Token = ""
	status := scienceWorkflowDecode[map[string]bool](t, f.post("status", in, 200))
	if !status["configured"] || !status["trusted"] {
		t.Fatal(status)
	}
	got := scienceWorkflowDecode[struct{ Data []labToolView }](t, f.post("execute", f.prepare(list), 200))
	if len(got.Data) != 1 {
		t.Fatal(got)
	}
	call := in
	call.Action = "tools/call"
	call.Target = "lookup"
	call.Definition = got.Data[0].Definition
	call.Arguments = map[string]any{"query": "offline text"}
	f.post("execute", f.prepare(call), 200)
	call.Arguments = map[string]any{"query": "echo-key"}
	if out := f.post("execute", f.prepare(call), 422); bytes.Contains(out, []byte(credential)) {
		t.Fatal("leaked bearer in result")
	}
	names := []string{}
	for len(methods) > 0 {
		names = append(names, <-methods)
	}
	if !slices.Contains(names, "tools/call") || !slices.Contains(names, "DELETE") {
		t.Fatal(names)
	}
	files, _ := filepath.Glob(filepath.Join(f.dir, "records", "*.json"))
	for _, file := range files {
		b, _ := os.ReadFile(file)
		if bytes.Contains(b, []byte(credential)) {
			t.Fatal("persisted credential")
		}
	}
	f.post("clear-token", op, 200)
	f.post("execute", f.prepare(list), 422)
	server.Close()
	op.Token = "valid-fixture"
	f.post("set-token", op, 200)
	f.post("execute", f.prepare(list), 422)
	op.Token = ""
	f.post("remove", op, 409)
	f.post("clear-token", op, 200)
	f.post("remove", op, 200)
}

func TestLabConnectorProtocolAndConfigBoundaries(t *testing.T) {
	for _, c := range []research.LabConnector{
		{ID: "bad", Transport: "other"}, {ID: "bad", Transport: "stdio", Program: "/bin/sh", Arguments: []string{"-c", "true"}},
		{ID: "bad", Transport: "https", Endpoint: "https://example.com/x?token=fixture"}, {ID: "bad", Transport: "https", Endpoint: "https://example.com/x", Program: "/bin/sh"},
		{ID: "?name", Transport: "stdio"}, {ID: "bad", Transport: "stdio", Endpoint: "https://example.com"},
		{ID: "bad", Transport: "stdio", Program: "/usr/bin/python3", Arguments: []string{"-c", "pass"}}, {ID: "bad", Transport: "https", Tools: []string{"bad tool"}},
	} {
		if _, err := cleanLabConnector(c); err == nil {
			t.Fatalf("accepted %+v", c)
		}
	}
	c := research.LabConnector{ID: "ok", Transport: "https", Endpoint: "https://example.com", Tools: []string{"read"}}
	for _, in := range []labConnectorRequest{{Action: "shell"}, {Action: "tools/call", Target: "write"}, {Action: "resources/read"}, {Action: "tools/list", Target: "a"}, {Action: "tools/list", Connection: &c}} {
		if _, err := connectorActionSummary(in, c); err == nil {
			t.Fatal(in)
		}
	}
	a := labConnectorAccess{pending: map[string]labConnectorTicket{"expired": {digest: "first", expires: time.Now().Add(-time.Hour)}}}
	id := a.ticket("p/c", "fresh")
	if _, ok := a.pending["expired"]; ok || !a.consume(id, "fresh") || a.consume(id, "fresh") {
		t.Fatal("incorrect ticket expiry or reuse")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 50*time.Millisecond)
	defer cancel()
	py, _ := exec.LookPath("python3")
	script := filepath.Join(t.TempDir(), "hang.py")
	if err := os.WriteFile(script, []byte("import time\ntime.sleep(20)"), 0600); err != nil {
		t.Fatal(err)
	}
	c = research.LabConnector{ID: "slow", Transport: "stdio", Program: py, Arguments: []string{script}}
	c, err := cleanLabConnector(c)
	if err != nil {
		t.Fatal(err)
	}
	m, err := startLabStdio(ctx, c)
	if err != nil {
		t.Fatal(err)
	}
	if err = m.call([]byte(`{"jsonrpc":"2.0","method":"initialize","id":1}`), 1, &c); err == nil {
		t.Fatal("unresponsive server yielded result")
	}
	m.close()
}

func TestLabConnectorUnknownFieldsAndStaleDisk(t *testing.T) {
	f := setupConnector(t)
	c := research.LabConnector{ID: "paper", Transport: "https", Endpoint: "https://example.com"}
	in := f.configure(c)
	path := filepath.Join(f.dir, "records", f.project+".json")
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var disk map[string]any
	json.Unmarshal(b, &disk)
	conn := disk["lab"].(map[string]any)["connections"].([]any)[0].(map[string]any)
	conn["future"] = map[string]any{"nested": true}
	data, _ := json.Marshal(disk)
	if err = os.WriteFile(path, data, 0600); err != nil {
		t.Fatal(err)
	}
	c.Enabled = true
	in.Connection = &c
	in.Confirmed = true
	f.post("save", in, 409)
	before, _ := os.ReadFile(path)
	if !bytes.Equal(before, data) {
		t.Fatal("conflicted save changed disk")
	}
	lab, err := research.New(f.dir)
	if err != nil {
		t.Fatal(err)
	}
	f.api.research = lab
	f.post("save", in, 200)
	b, _ = os.ReadFile(path)
	json.Unmarshal(b, &disk)
	actual := disk["lab"].(map[string]any)["connections"].([]any)[0].(map[string]any)["future"]
	if !reflect.DeepEqual(actual, conn["future"]) {
		t.Fatal(actual)
	}
}

func TestLabConnectorRejectsRevokedProjectBeforeDispatch(t *testing.T) {
	f := setupConnector(t)
	dir, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	srv := f.api.research
	srv.SetPathValidator(func(path string) bool { return path == dir })
	p, err := srv.EnsureDirectoryProject(dir)
	if err != nil {
		t.Fatal(err)
	}
	f.project = p.ID
	c := research.LabConnector{ID: "papers", Transport: "https", Endpoint: "https://example.com/mcp", Enabled: true}
	op := f.configure(c)
	op.Confirmed = true
	f.post("trust", op, 200)
	op.Confirmed = false
	op.Action = "resources/list"
	staged := f.prepare(op)
	if err = os.Rename(dir, filepath.Join(t.TempDir(), "moved")); err != nil {
		t.Fatal(err)
	}
	if err = os.Mkdir(dir, 0700); err != nil {
		t.Fatal(err)
	}
	f.post("execute", staged, 403)
	f.post("prepare", op, 403)
}
