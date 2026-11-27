package desktop

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"math"
	"mime"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"testing"

	"scistation.local/desktop/internal/meeting"
	"scistation.local/desktop/internal/research"
)

type openAPIMedia struct {
	Schema *openAPISchema `json:"schema"`
}

// OpenAPI 3.1 uses JSON Schema's string or array forms for type.
type openAPITypes []string

func (types *openAPITypes) UnmarshalJSON(data []byte) error {
	if len(data) > 0 && data[0] == '"' {
		var name string
		if err := json.Unmarshal(data, &name); err != nil {
			return err
		}
		*types = openAPITypes{name}
		return nil
	}
	return json.Unmarshal(data, (*[]string)(types))
}

func (types openAPITypes) match(value any) bool {
	if len(types) == 0 {
		return true
	}
	switch value := value.(type) {
	case nil:
		return slices.Contains(types, "null")
	case string:
		return slices.Contains(types, "string")
	case bool:
		return slices.Contains(types, "boolean")
	case float64:
		return slices.Contains(types, "number") || (math.Trunc(value) == value && slices.Contains(types, "integer"))
	case map[string]any:
		return slices.Contains(types, "object")
	case []any:
		return slices.Contains(types, "array")
	default:
		return false
	}
}

type openAPISchema struct {
	Ref                  string                    `json:"$ref"`
	Types                openAPITypes              `json:"type"`
	Required             []string                  `json:"required"`
	Properties           map[string]*openAPISchema `json:"properties"`
	AdditionalProperties json.RawMessage           `json:"additionalProperties"`
	Items                *openAPISchema            `json:"items"`
	AllOf                []*openAPISchema          `json:"allOf"`
	AnyOf                []*openAPISchema          `json:"anyOf"`
	OneOf                []*openAPISchema          `json:"oneOf"`
}

// TestPublishedResearchOpenAPI follows the downloaded contract through the
// ordinary desktop listener. It checks documented research operations and
// Studio project compatibility against isolated state.
func TestPublishedResearchOpenAPI(t *testing.T) {
	const host = "http://127.0.0.1:8765"
	dir := t.TempDir()
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("CODEX_HOME", filepath.Join(home, ".codex"))
	t.Setenv("CLAUDE_CONFIG_DIR", filepath.Join(home, ".claude"))
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
	lab.SetPathValidator(func(path string, _ research.DirectoryGrant) bool { return path == externalDir })
	server := &apiServer{prefs: prefs, research: lab, meetings: engine}
	api := server.serve(8765)

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
		if !strings.HasPrefix(path, "/api/research/") && !strings.HasPrefix(path, "/api/studio/projects") {
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
	checked := make(map[string]bool, len(published))
	t.Cleanup(func() {
		if t.Failed() {
			return
		}
		for id := range published {
			if !checked[id] {
				t.Errorf("published operation lacks a live contract check: %s", id)
			}
		}
	})
	var matchesShape func(any, *openAPISchema) bool
	matchesShape = func(value any, schema *openAPISchema) bool {
		if schema == nil || !schema.Types.match(value) {
			return false
		}
		if schema.Ref != "" && !matchesShape(value, doc.Components.Schemas[strings.TrimPrefix(schema.Ref, "#/components/schemas/")]) {
			return false
		}
		for _, part := range schema.AllOf {
			if !matchesShape(value, part) {
				return false
			}
		}
		if len(schema.AnyOf) > 0 && !slices.ContainsFunc(schema.AnyOf, func(part *openAPISchema) bool {
			return matchesShape(value, part)
		}) {
			return false
		}
		if len(schema.OneOf) > 0 {
			matches := 0
			for _, option := range schema.OneOf {
				if matchesShape(value, option) {
					matches++
				}
			}
			if matches != 1 {
				return false
			}
		}
		switch value := value.(type) {
		case map[string]any:
			for _, key := range schema.Required {
				if _, present := value[key]; !present {
					return false
				}
			}
			closed := string(schema.AdditionalProperties) == "false"
			for key, field := range value {
				if property, known := schema.Properties[key]; known {
					if !matchesShape(field, property) {
						return false
					}
				} else if closed {
					return false
				}
			}
		case []any:
			for _, item := range value {
				if schema.Items != nil && !matchesShape(item, schema.Items) {
					return false
				}
			}
		}
		return true
	}

	projectID, paperID, noteID, presetID := "", "", "", ""
	run := func(id string, status int, query string, payload any) json.RawMessage {
		t.Helper()
		operation, ok := published[id]
		if !ok {
			t.Fatalf("missing OpenAPI operation %s", id)
		}
		checked[id] = true
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
			if !matchesShape(scienceWorkflowDecode[any](t, encoded), operation.RequestBody.Content["application/json"].Schema) {
				t.Fatalf("%s request does not match the documented JSON shape: %s", id, encoded)
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
			if !matchesShape(scienceWorkflowDecode[any](t, w.Body.Bytes()), format.Schema) {
				t.Fatalf("%s response does not match the documented JSON shape: %s", id, w.Body)
			}
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

	// Use a real external project and a separate historical snapshot.
	var projects struct{ Projects []research.Project }
	projects = scienceWorkflowDecode[struct{ Projects []research.Project }](t,
		run("registerStudioProject", 200, "", object{"path": externalDir}))
	if len(projects.Projects) != 1 || projects.Projects[0].Path != externalDir {
		t.Fatalf("unexpected active project list: %+v", projects)
	}
	projectID = projects.Projects[0].ID
	run("getStudioProjects", 200, "", nil)
	writeProjectTestFile(t, externalDir, "AGENTS.md", "Local project-rule fixture.")
	preview := fields(run("importStudioProjects", 200, "", object{"action": "preview", "paths": []string{externalDir}}))
	row := preview["projects"].([]any)[0].(object)
	if row["id"] != projectID {
		t.Fatalf("preview did not include the active project ID: %+v", row)
	}
	rule := row["rules"].([]any)[0].(object)
	ref := object{"path": rule["path"], "digest": rule["digest"]}
	run("importStudioProjects", 200, "", object{"action": "apply", "selections": []object{
		{"id": projectID, "path": externalDir, "rules": []object{ref}},
	}})
	activeQuery := "?id=" + projectID
	byID := fields(run("getStudioProjectRules", 200, activeQuery, nil))
	saved := byID["rules"].([]any)
	if byID["project"].(object)["id"] != projectID || len(saved) != 1 || saved[0].(object)["digest"] != ref["digest"] {
		t.Fatalf("unexpected rule snapshot for project %s: %+v", projectID, byID)
	}
	run("getStudioProjectRules", 200, "?path="+url.QueryEscape(externalDir), nil)
	disabled := fields(run("disableStudioProjectRule", 200, "", object{"id": projectID, "rule": ref}))
	if len(disabled["rules"].([]any)) != 0 {
		t.Fatalf("disabled rule remains in the active snapshot: %+v", disabled)
	}

	archivePath := filepath.Join(dir, "legacy-fixture")
	const oldText = "Historical project-rule fixture."
	historical := object{archivePath: object{"path": archivePath, "rules": []object{{
		"path": "AGENTS.md", "source": "AGENTS.md", "text": oldText, "digest": research.RoundtableRuleDigest(oldText),
	}}}}
	archive, err := json.Marshal(historical)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(server.projectsFile(), archive, 0600); err != nil {
		t.Fatal(err)
	}
	candidates := fields(run("getProjectImportCandidates", 200, "", nil))
	if legacy := candidates["legacy"].([]any); len(legacy) != 1 || legacy[0].(object)["path"] != archivePath {
		t.Fatalf("unexpected legacy project summaries: %+v", candidates)
	}
	legacyQuery := "?legacy=1&path=" + url.QueryEscape(archivePath)
	run("getStudioProjectRules", 400, legacyQuery+"&id="+projectID, nil)
	run("disableStudioProjectRule", 405, legacyQuery, object{"id": projectID, "rule": ref})
	legacy := fields(run("getStudioProjectRules", 200, legacyQuery, nil))
	oldRules := legacy["rules"].([]any)
	if len(oldRules) != 1 || oldRules[0].(object)["text"] != oldText {
		t.Fatalf("unexpected historical rule snapshot: %+v", legacy)
	}

	external := fields(run("getResearchProject", 200, "", nil))
	run("updateResearchProjectDirectory", 200, "", object{"revision": external["revision"], "path": ""})
	run("getStudioProjectRules", 200, activeQuery, nil)
	run("getStudioProjectRules", 404, "?path="+url.QueryEscape(externalDir), nil)
}
