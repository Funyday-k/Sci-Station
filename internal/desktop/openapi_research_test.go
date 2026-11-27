package desktop

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"mime"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	"scistation.local/desktop/internal/meeting"
	"scistation.local/desktop/internal/research"
)

type openAPIMedia struct {
	Schema *openAPISchema `json:"schema"`
}

type openAPISchema struct {
	Ref      string           `json:"$ref"`
	Type     string           `json:"type"`
	Required []string         `json:"required"`
	Items    *openAPISchema   `json:"items"`
	AllOf    []*openAPISchema `json:"allOf"`
}

// TestPublishedResearchOpenAPI follows the downloaded contract through the
// ordinary desktop listener. It checks every documented research operation
// against isolated state, without a provider or a native dialog.
func TestPublishedResearchOpenAPI(t *testing.T) {
	const host = "http://127.0.0.1:8765"
	dir := t.TempDir()
	prefs, err := openSettings(dir)
	if err != nil {
		t.Fatal(err)
	}
	lab, err := research.New(filepath.Join(dir, "research"))
	if err != nil {
		t.Fatal(err)
	}
	engine, err := meeting.New(filepath.Join(dir, "studio"), func(context.Context, string, string, string, string) (string, error) {
		return "", errors.New("contract fixture must not call a model")
	}, func() meeting.Settings { return prefs.get().Settings })
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = engine.Shutdown(context.Background()) })
	externalDir, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	lab.SetPathValidator(func(path string) bool { return path == externalDir })
	api := (&apiServer{prefs: prefs, research: lab, meetings: engine}).serve(8765)

	guide := httptest.NewRecorder()
	api.ServeHTTP(guide, httptest.NewRequest(http.MethodGet, host+"/api-docs", nil))
	if guide.Code != http.StatusOK || !strings.Contains(guide.Body.String(), `href="/openapi.json" download="sci-station-openapi.json"`) {
		t.Fatalf("render local API guide with contract download: %d", guide.Code)
	}
	download := httptest.NewRecorder()
	api.ServeHTTP(download, httptest.NewRequest(http.MethodGet, host+"/openapi.json", nil))
	if download.Code != http.StatusOK {
		t.Fatalf("download OpenAPI: %d", download.Code)
	}
	type responseContract struct {
		Ref     string                  `json:"$ref"`
		Content map[string]openAPIMedia `json:"content"`
	}
	type operationContract struct {
		Path        string
		Method      string
		OperationID string `json:"operationId"`
		RequestBody struct {
			Required bool                    `json:"required"`
			Content  map[string]openAPIMedia `json:"content"`
		} `json:"requestBody"`
		Responses map[string]responseContract `json:"responses"`
	}
	doc := scienceWorkflowDecode[struct {
		Paths      map[string]map[string]json.RawMessage `json:"paths"`
		Components struct {
			Schemas   map[string]*openAPISchema   `json:"schemas"`
			Responses map[string]responseContract `json:"responses"`
		} `json:"components"`
	}](t, download.Body.Bytes())
	published := make(map[string]operationContract)
	for path, methods := range doc.Paths {
		if !strings.HasPrefix(path, "/api/research/") {
			continue
		}
		for method, raw := range methods {
			if method == "parameters" {
				continue
			}
			operation := scienceWorkflowDecode[operationContract](t, raw)
			id := operation.OperationID
			if id == "" || published[id].Path != "" {
				t.Fatalf("invalid or duplicate operation ID %q at %s %s", id, method, path)
			}
			operation.Path = path
			operation.Method = strings.ToUpper(method)
			published[id] = operation
		}
	}
	t.Cleanup(func() {
		if t.Failed() {
			return
		}
		for id := range published {
			t.Errorf("published operation lacks a live contract check: %s", id)
		}
	})
	var validateShape func(any, *openAPISchema)
	validateShape = func(value any, schema *openAPISchema) {
		t.Helper()
		if schema == nil {
			t.Fatal("JSON response has no schema")
		}
		if schema.Ref != "" {
			validateShape(value, doc.Components.Schemas[strings.TrimPrefix(schema.Ref, "#/components/schemas/")])
		}
		for _, part := range schema.AllOf {
			validateShape(value, part)
		}
		switch schema.Type {
		case "object":
			fields, ok := value.(map[string]any)
			if !ok {
				t.Fatalf("response is not a JSON object: %#v", value)
			}
			for _, key := range schema.Required {
				if _, present := fields[key]; !present {
					t.Fatalf("documented response field %q absent in %#v", key, value)
				}
			}
		case "array":
			items, ok := value.([]any)
			if !ok {
				t.Fatalf("response is not a JSON array: %#v", value)
			}
			for _, item := range items {
				validateShape(item, schema.Items)
			}
		}
	}

	projectID, paperID, noteID, presetID := "", "", "", ""
	run := func(id string, status int, query string, payload any) json.RawMessage {
		t.Helper()
		operation, ok := published[id]
		if !ok {
			t.Fatalf("missing OpenAPI operation %s", id)
		}
		delete(published, id)
		route := strings.NewReplacer("{project}", projectID, "{paper}", paperID, "{note}", noteID, "{preset}", presetID).Replace(operation.Path)
		var requestBody io.Reader
		var media string
		switch data := payload.(type) {
		case nil:
		case []byte:
			var buffer bytes.Buffer
			form := multipart.NewWriter(&buffer)
			file, err := form.CreateFormFile("file", "fixture.pdf")
			if err != nil {
				t.Fatal(err)
			}
			if _, err := file.Write(data); err != nil {
				t.Fatal(err)
			}
			if err := form.Close(); err != nil {
				t.Fatal(err)
			}
			requestBody, media = &buffer, form.FormDataContentType()
		default:
			encoded, err := json.Marshal(data)
			if err != nil {
				t.Fatal(err)
			}
			requestBody, media = bytes.NewReader(encoded), "application/json"
		}
		if media == "" && operation.RequestBody.Required {
			t.Fatalf("%s declares a required request body", id)
		}
		if media != "" {
			base, _, err := mime.ParseMediaType(media)
			if err != nil || operation.RequestBody.Content[base].Schema == nil {
				t.Fatalf("%s has no request schema for %q", id, base)
			}
		}
		r := httptest.NewRequest(operation.Method, host+route+query, requestBody)
		r.Header.Set("X-Roundtable", "1")
		if media != "" {
			r.Header.Set("Content-Type", media)
		}
		w := httptest.NewRecorder()
		api.ServeHTTP(w, r)
		if w.Code != status {
			t.Fatalf("%s %s (%s): got %d, want %d: %s", r.Method, r.URL, id, w.Code, status, w.Body)
		}
		response, ok := operation.Responses[strconv.Itoa(w.Code)]
		if !ok {
			t.Fatalf("%s does not document response %d", id, w.Code)
		}
		if response.Ref != "" {
			response, ok = doc.Components.Responses[strings.TrimPrefix(response.Ref, "#/components/responses/")]
			if !ok {
				t.Fatalf("%s has an unresolved response reference", id)
			}
		}
		if w.Body.Len() == 0 {
			if len(response.Content) > 0 {
				t.Fatalf("%s declares response media for an empty body", id)
			}
			return nil
		}
		base, _, err := mime.ParseMediaType(w.Header().Get("Content-Type"))
		format, ok := response.Content[base]
		if err != nil || !ok {
			t.Fatalf("%s: undocumented response media %q", id, w.Header().Get("Content-Type"))
		}
		if base == "application/json" {
			validateShape(scienceWorkflowDecode[any](t, w.Body.Bytes()), format.Schema)
			return w.Body.Bytes()
		}
		return nil
	}
	type object = map[string]any
	fields := func(raw []byte) object { return scienceWorkflowDecode[object](t, raw) }
	project := fields(run("createResearchProject", 201, "", object{"name": "Contract fixture"}))
	projectID = project["id"].(string)
	projectQuery := "?project=" + projectID
	run("listResearchProjects", 200, "", nil)
	run("getResearchProject", 200, "", nil)
	project = fields(run("updateResearchProject", 200, "", object{"revision": project["revision"], "description": "updated"}))

	run("getResearchDashboardProjects", 200, projectQuery, nil)
	note := fields(run("createResearchNote", 201, "", object{"title": "Observation", "body": "A saved project source."}))
	noteID = note["id"].(string)
	run("listResearchNotes", 200, "", nil)
	run("getResearchNote", 200, "", nil)

	modules := fields(run("getResearchModules", 200, projectQuery, nil))
	run("updateResearchModules", 200, projectQuery, object{"revision": modules["revision"], "action": "set", "id": "ai-lab", "enabled": true})

	metadata := object{"title": "Local API fixture", "skip_metadata_lookup": true, "project_ids": []string{projectID}}
	run("previewResearchPaperImport", 200, "", metadata)
	paper := fields(run("importResearchPaper", 201, "", metadata))
	paperID = paper["id"].(string)
	run("listResearchPapers", 200, projectQuery+"&paper="+paperID, nil)
	run("getResearchPaper", 200, "", nil)
	run("updateResearchPaper", 200, "", object{"revision": paper["revision"], "core_project_ids": []string{projectID}})
	run("getResearchPaperCitation", 200, "?format=ris", nil)
	run("exportResearchLibraryBibtex", 200, projectQuery, nil)
	run("exportResearchPaperBibtex", 200, "", nil)
	run("attachResearchPaperPDF", 200, "", scienceWorkflowPDF("An isolated PDF fixture."))
	run("getResearchPaperPDF", 200, "", nil)
	run("inspectResearchPaperPDF", 200, "", nil)

	preset := object{"title": "Contract fixture", "mode": "review", "seats": 1, "prompt": "Review local evidence."}
	personal := fields(run("createResearchLabPreset", 201, "", preset))
	presetID = personal["id"].(string)
	run("listResearchLabPresets", 200, "", nil)
	preset["revision"] = personal["revision"]
	personal = fields(run("updateResearchLabPreset", 200, "", preset))
	run("deleteResearchLabPreset", 204, "", object{"revision": personal["revision"]})

	config := fields(run("getResearchLabContext", 200, projectQuery, nil))
	run("updateResearchLabContext", 200, "", object{"projectId": projectID, "revision": config["revision"], "operation": "mcp", "confirmed": true, "value": false})
	source := fields(run("previewResearchLabSource", 200, "", object{"projectId": projectID, "location": object{"kind": "note", "id": noteID}}))
	run("prepareResearchLabSourceMaterials", 200, "", object{"projectId": projectID, "citations": []object{
		{"kind": "note", "id": noteID, "hash": source["hash"], "quote": source["text"]},
	}})

	impact := fields(run("previewResearchPaperRemoval", 200, "", nil))
	run("confirmResearchPaperRemoval", 204, "?revision="+strconv.Itoa(int(impact["revision"].(float64)))+"&confirmation="+impact["confirmation"].(string), nil)
	run("archiveResearchProject", 204, "?revision="+strconv.Itoa(int(project["revision"].(float64))), nil)
	project = fields(run("restoreResearchProject", 200, "", object{"revision": project["revision"].(float64) + 1}))
	run("trashResearchProject", 204, "", object{"revision": project["revision"]})

	// This route accepts an existing external directory grant, which is
	// distinct from the managed directory created above.
	req := httptest.NewRequest("POST", host+"/api/research/projects", strings.NewReader(`{"name":"External fixture","path":`+strconv.Quote(externalDir)+`}`))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Roundtable", "1")
	w := httptest.NewRecorder()
	api.ServeHTTP(w, req)
	if w.Code != 201 {
		t.Fatalf("create external project fixture: %d: %s", w.Code, w.Body)
	}
	external := fields(w.Body.Bytes())
	projectID = external["id"].(string)
	run("updateResearchProjectDirectory", 200, "", object{"revision": external["revision"], "path": ""})
}
