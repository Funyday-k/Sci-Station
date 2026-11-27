package main

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"testing"

	"scistation.local/desktop/internal/meeting"
	"scistation.local/desktop/internal/research"
	"scistation.local/desktop/internal/workspace"
)

const (
	projectID           = "11111111111111111111111111111111"
	externalProjectID   = "22222222222222222222222222222222"
	paperID             = "33333333333333333333333333333333"
	meetingID           = "44444444444444444444444444444444"
	externalMeetingID   = "55555555555555555555555555555555"
	meetingAttachmentID = "66666666666666666666666666666666"
	projectAttachmentID = "77777777777777777777777777777777"
	paperPath           = paperDirectory + "/" + paperID + ".json"
	pdfPath             = "research/library/pdf/" + paperID + ".pdf"
	projectPath         = projectDirectory + "/" + projectID + ".json"
	passage             = "Synthetic source excerpt"
)

func testParent(t *testing.T) string {
	t.Helper()
	path, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	return path
}

func putFile(t *testing.T, dir, name, text string) {
	t.Helper()
	path := filepath.Join(dir, name)
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(text), 0600); err != nil {
		t.Fatal(err)
	}
}

func getFile(t *testing.T, dir, path string) string {
	t.Helper()
	b, err := os.ReadFile(filepath.Join(dir, path))
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

func absent(t *testing.T, path string) {
	t.Helper()
	if _, err := os.Lstat(path); !os.IsNotExist(err) {
		t.Fatalf("%s exists or could not be checked: %v", path, err)
	}
}

func fixture(t *testing.T, dir string) string {
	t.Helper()
	prototype := filepath.Join(dir, "prototype")
	external := filepath.Join(dir, "external")
	putFile(t, external, "external.md", "synthetic external file")
	putFile(t, prototype, processLock, "")
	putFile(t, prototype, "studio/.meeting.lock", "")
	pdf := "%PDF-1.4\n" + passage + "\n%%EOF\n"
	putFile(t, prototype, pdfPath, pdf)
	hash := sha256.Sum256([]byte(pdf))
	putFile(t, prototype, paperPath, fmt.Sprintf(`{"id":%q,"revision":1,"title":"Synthetic paper","has_pdf":true,"file_sha256":"%x","project_ids":[%q,%q],"annotations":[{"id":"sample","page":2,"selected_text":%q}]}`, paperID, hash, projectID, externalProjectID, passage))
	for id, path := range map[string]string{projectID: managedPath(prototype, projectID), externalProjectID: external} {
		doc := fmt.Sprintf(`{"project":{"id":%q,"revision":1,"name":"Example","path":%q,"future":{"x":[1,2]}},"notes":{},"tasks":{},"materials":{},"noteKeys":{},"taskKeys":{}}`, id, path)
		if id == projectID {
			doc = strings.Replace(doc, `"notes":{}`, fmt.Sprintf(`"notes":{"note":{"id":"note","projectId":%q,"title":"Example note","paperId":%q,"evidence":[{"paperId":%q,"page":2,"quote":%q,"sourceHash":"%x","meetingId":%q}]}}`, id, paperID, paperID, passage, hash, meetingID), 1)
			doc = strings.Replace(doc, `"materials":{}`, fmt.Sprintf(`"materials":{%q:{"id":%q,"projectId":%q,"size":4}}`, projectAttachmentID, projectAttachmentID, id), 1)
		}
		putFile(t, prototype, projectDirectory+"/"+id+".json", doc)
	}
	putFile(t, prototype, "research/workspaces/"+projectID+"/analysis.md", "synthetic managed file")
	putFile(t, prototype, "research/blobs/"+projectAttachmentID, "data")
	putFile(t, prototype, "studio/"+meetingID+".json", fmt.Sprintf(`{"id":%q,"project":%q,"status":"running","topic":"Example discussion","materials":[{"id":%q,"size":4}]}`, meetingID, managedPath(prototype, projectID), meetingAttachmentID))
	putFile(t, prototype, "studio/"+externalMeetingID+".json", fmt.Sprintf(`{"id":%q,"project":%q,"status":"ready","topic":"Example external discussion"}`, externalMeetingID, external))
	putFile(t, prototype, "studio/materials/"+meetingAttachmentID+"/metadata.json", fmt.Sprintf(`{"id":%q,"size":4}`, meetingAttachmentID))
	putFile(t, prototype, "studio/materials/"+meetingAttachmentID+"/original", "text")
	putFile(t, prototype, registryFile, fmt.Sprintf(`{%q:{"path":%q,"rules":[]}}`, external, external))
	putFile(t, prototype, "settings.json", fmt.Sprintf(`{"cli_paths":{"codex":%q},"appearance":"dark","future":{"keep":[true]}}`, filepath.Join(external, "cli")))
	return prototype
}

func TestRecoveryReopensIsolatedData(t *testing.T) {
	parent := testParent(t)
	prototype := fixture(t, parent)
	archive := filepath.Join(parent, "archive")
	destination := filepath.Join(parent, "recovered")
	originalRecord := getFile(t, prototype, projectPath)
	originalMeeting := getFile(t, prototype, "studio/"+meetingID+".json")
	originalPDF := getFile(t, prototype, pdfPath)
	var output bytes.Buffer
	if err := run([]string{"backup", "-source", prototype, "-destination", archive}, &output); err != nil {
		t.Fatal(err)
	}
	if err := run([]string{"verify", "-source", archive}, &output); err != nil {
		t.Fatal(err)
	}
	if err := run([]string{"restore", "-source", archive, "-destination", destination}, &output); err != nil {
		t.Fatal(err)
	}
	for root, expected := range map[string]string{prototype: originalRecord, filepath.Join(archive, payloadName): originalRecord} {
		if got := getFile(t, root, projectPath); got != expected {
			t.Fatalf("original project record changed in %s", root)
		}
	}
	absent(t, filepath.Join(archive, payloadName, processLock))
	absent(t, filepath.Join(archive, payloadName, workspace.RootMarker))
	absent(t, filepath.Join(prototype, workspace.RootMarker))
	absent(t, filepath.Join(destination, "external"))
	if getFile(t, destination, workspace.RootMarker) != workspace.RootFormat {
		t.Fatal("the isolated destination is not eligible for explicit opening")
	}

	var restored struct {
		Project struct {
			Path   string           `json:"path"`
			Future map[string][]int `json:"future"`
		} `json:"project"`
	}
	if err := json.Unmarshal([]byte(getFile(t, destination, projectPath)), &restored); err != nil ||
		restored.Project.Path != managedPath(destination, projectID) || len(restored.Project.Future["x"]) != 2 {
		t.Fatalf("restored project path or unknown fields did not survive: %+v %v", restored, err)
	}
	if err := json.Unmarshal([]byte(getFile(t, destination, projectDirectory+"/"+externalProjectID+".json")), &restored); err != nil || restored.Project.Path != "" {
		t.Fatalf("external project is still accessible: %+v %v", restored, err)
	}
	var historical map[string]map[string]json.RawMessage
	if err := json.Unmarshal([]byte(getFile(t, destination, registryFile)), &historical); err != nil || len(historical) != 1 || historical[filepath.Join(parent, "external")]["rules"] == nil || historical[filepath.Join(parent, "external")]["directoryGrant"] != nil {
		t.Fatal("external rule archive or grant cleanup changed", historical, err)
	}
	if restoredSettings := getFile(t, destination, "settings.json"); strings.Contains(restoredSettings, "cli_paths") || !strings.Contains(restoredSettings, "future") {
		t.Fatal("local executable override was replayed or unknown settings were lost")
	}

	for id, owner := range map[string]string{meetingID: projectID, externalMeetingID: externalProjectID} {
		var binding struct {
			ProjectID string `json:"project_id"`
		}
		if err := json.Unmarshal([]byte(getFile(t, destination, "studio/"+id+".json")), &binding); err != nil || binding.ProjectID != owner {
			t.Fatalf("restored meeting lost its project reference: %+v %v", binding, err)
		}
	}

	// Reopen with the application's actual stores. No provider or user folder
	// participates. The recovered session handler exercises its startup repair.
	lab, err := research.New(filepath.Join(destination, "research"))
	if err != nil {
		t.Fatal(err)
	}
	pdf, err := lab.PaperPDFPath(paperID)
	if err != nil {
		t.Fatal(err)
	}
	if data, err := os.ReadFile(pdf); err != nil || string(data) != originalPDF {
		t.Fatalf("PDF changed: %v", err)
	}
	recorder := httptest.NewRecorder()
	lab.ServeHTTP(recorder, httptest.NewRequest(http.MethodGet, "/api/research/papers/"+paperID, nil))
	var restoredPaper research.Paper
	if err := json.Unmarshal(recorder.Body.Bytes(), &restoredPaper); recorder.Code != http.StatusOK ||
		err != nil || len(restoredPaper.Annotations) != 1 || restoredPaper.Annotations[0].Page != 2 ||
		restoredPaper.Annotations[0].SelectedText != passage || len(restoredPaper.ProjectIDs) != 2 {
		t.Fatalf("paper membership and annotation did not reopen: HTTP %v (%v)", recorder.Code, err)
	}
	recorder = httptest.NewRecorder()
	lab.ServeHTTP(recorder, httptest.NewRequest(http.MethodGet, "/api/research/projects/"+projectID+"/notes", nil))
	if recorder.Code != http.StatusOK || !strings.Contains(recorder.Body.String(), passage) {
		t.Fatalf("note evidence did not reopen: HTTP %v", recorder.Code)
	}
	recorder = httptest.NewRecorder()
	lab.ServeHTTP(recorder, httptest.NewRequest(http.MethodGet, "/api/research/projects/"+projectID+"/files?path=analysis.md", nil))
	if recorder.Code != http.StatusOK || !strings.Contains(recorder.Body.String(), "synthetic managed file") {
		t.Fatalf("managed project file did not reopen: HTTP %v", recorder.Code)
	}
	engine, err := meeting.New(filepath.Join(destination, "studio"), func(context.Context, string, string, string, string) (string, error) {
		panic("reopening must not call a provider")
	}, func() meeting.Settings { return meeting.Settings{} })
	if err != nil {
		t.Fatal(err)
	}
	s, err := engine.Get(meetingID)
	if err != nil || s.Status != "ready" || s.Project != managedPath(destination, projectID) || len(s.Materials) != 1 {
		t.Fatalf("meeting did not reopen: %+v %v", s, err)
	}
	s, err = engine.Get(externalMeetingID)
	if err != nil || s.Project != "" {
		t.Fatalf("external meeting path is active: %+v %v", s, err)
	}
	if getFile(t, prototype, "studio/"+meetingID+".json") != originalMeeting ||
		getFile(t, archive, payloadName+"/studio/"+meetingID+".json") != originalMeeting {
		t.Fatal("recovery wrote to the original meeting or its backup")
	}
	if got := getFile(t, filepath.Join(parent, "external"), "external.md"); got != "synthetic external file" {
		t.Fatalf("external fixture changed: %q", got)
	}
}

func TestRecoveryKeepsOnlyRecordedExternalDirectoryIdentity(t *testing.T) {
	for _, scenario := range []string{"recorded grant", "previous identity", "invalid grant", "legacy path only"} {
		t.Run(scenario, func(t *testing.T) {
			parent := testParent(t)
			prototype := fixture(t, parent)
			archive, destination := filepath.Join(parent, "archive"), filepath.Join(parent, "restored")
			external := filepath.Join(parent, "external")
			verified, err := research.IdentifyDirectory(external)
			if err != nil {
				t.Fatal(err)
			}
			recordPath := projectDirectory + "/" + externalProjectID + ".json"
			var document, project map[string]json.RawMessage
			if err := json.Unmarshal([]byte(getFile(t, prototype, recordPath)), &document); err != nil {
				t.Fatal(err)
			}
			if err := json.Unmarshal(document["project"], &project); err != nil {
				t.Fatal(err)
			}
			var want *research.DirectoryGrant
			switch scenario {
			case "recorded grant":
				want = &verified
				project["directoryGrant"], _ = json.Marshal(verified)
				document["previousDirectoryIdentity"] = json.RawMessage(`{"device":0,"inode":1}`)
			case "previous identity":
				want = &verified
				document["previousDirectoryIdentity"], _ = json.Marshal(verified)
			case "invalid grant":
				project["directoryGrant"] = json.RawMessage(`{"device":42,"inode":0}`)
			}
			document["project"], _ = json.Marshal(project)
			original, err := json.Marshal(document)
			if err != nil {
				t.Fatal(err)
			}
			putFile(t, prototype, recordPath, string(original))
			// The recorded path now belongs to a different directory. The
			// offline tool must not treat its identity as project history.
			if err := os.Rename(external, filepath.Join(parent, "formerly-external")); err != nil {
				t.Fatal(err)
			}
			putFile(t, external, "replacement.md", "different directory")
			occupied, err := research.IdentifyDirectory(external)
			if err != nil || occupied == verified {
				t.Fatalf("replacement did not have its own identity: %+v, %v", occupied, err)
			}
			if err := backup(prototype, archive); err != nil {
				t.Fatal(err)
			}
			if err := restore(archive, destination); err != nil {
				t.Fatal(err)
			}
			var restored struct {
				Project                   research.Project
				PreviousDirectoryIdentity *research.DirectoryGrant `json:"previousDirectoryIdentity"`
			}
			if err := json.Unmarshal([]byte(getFile(t, destination, recordPath)), &restored); err != nil {
				t.Fatal(err)
			}
			if restored.Project.Path != "" || restored.Project.DirectoryGrant != nil {
				t.Fatalf("restored project still has an external grant: %+v", restored.Project)
			}
			identity := restored.PreviousDirectoryIdentity
			if (want == nil && identity != nil) || (want != nil && (identity == nil || *identity != *want)) {
				t.Fatalf("restored identity %+v, want %+v", identity, want)
			}
			lab, err := research.New(filepath.Join(destination, "research"))
			if err != nil {
				t.Fatal(err)
			}
			if path, err := lab.ProjectDirectory(externalProjectID); path != "" || !errors.Is(err, os.ErrPermission) {
				t.Fatalf("external directory is available in recovered copy: %q, %v", path, err)
			}
			if getFile(t, prototype, recordPath) != string(original) || getFile(t, archive, payloadName+"/"+recordPath) != string(original) {
				t.Fatal("restoration changed the source or backup project record")
			}
		})
	}
}

func TestRecoveryRetainsSupportedResearchRecordVersions(t *testing.T) {
	for _, version := range []string{"legacy", "v1"} {
		t.Run(version, func(t *testing.T) {
			parent := testParent(t)
			prototype := fixture(t, parent)
			archive := filepath.Join(parent, "archive")
			destination := filepath.Join(parent, "restored")
			originals := make(map[string]string)
			for _, path := range []string{projectPath, paperPath} {
				raw := getFile(t, prototype, path)
				if version == "v1" {
					raw = strings.Replace(raw, "{", "{\n  \"schema_version\": 1,\n  ", 1)
					putFile(t, prototype, path, raw)
				}
				originals[path] = raw
			}
			for _, args := range [][]string{
				{"backup", "-source", prototype, "-destination", archive},
				{"verify", "-source", archive},
				{"restore", "-source", archive, "-destination", destination},
			} {
				if err := run(args, &bytes.Buffer{}); err != nil {
					t.Fatal(err)
				}
			}
			if _, err := research.New(filepath.Join(destination, "research")); err != nil {
				t.Fatalf("restored records did not open: %v", err)
			}
			for path, original := range originals {
				if getFile(t, prototype, path) != original || getFile(t, archive, payloadName+"/"+path) != original {
					t.Fatalf("original or backup record changed: %s", path)
				}
				var record map[string]json.RawMessage
				if err := json.Unmarshal([]byte(getFile(t, destination, path)), &record); err != nil {
					t.Fatal(err)
				}
				want := ""
				if version == "v1" {
					want = "1"
				}
				if got := string(record["schema_version"]); got != want {
					t.Fatalf("%s has version %q, want %q", path, got, want)
				}
			}
		})
	}
}

func TestVerifyAndRestoreRejectUnsupportedResearchRecordVersions(t *testing.T) {
	for _, record := range []struct{ name, path string }{{"project", projectPath}, {"paper", paperPath}} {
		for _, version := range []struct{ name, field string }{
			{"future", `"schema_version":2`},
			{"malformed", `"schema_version":null`},
			{"duplicate", `"schema_version":1,"schema\u005fversion":1`},
		} {
			t.Run(record.name+"/"+version.name, func(t *testing.T) {
				parent := testParent(t)
				prototype := fixture(t, parent)
				archive := filepath.Join(parent, "archive")
				destination := filepath.Join(parent, "restored")
				body := strings.Replace(getFile(t, prototype, record.path), "{", "{"+version.field+",", 1)
				putFile(t, prototype, record.path, body)
				if err := backup(prototype, archive); err != nil {
					t.Fatalf("byte-preserving backup failed: %v", err)
				}
				savedManifest := getFile(t, archive, manifestName)
				for _, args := range [][]string{
					{"verify", "-source", archive},
					{"restore", "-source", archive, "-destination", destination},
				} {
					err := run(args, &bytes.Buffer{})
					if err == nil || !strings.Contains(err.Error(), "schema_version") || !strings.Contains(err.Error(), record.path) {
						t.Fatalf("expected a schema error for %s, got %v", record.path, err)
					}
				}
				absent(t, destination)
				if getFile(t, prototype, record.path) != body || getFile(t, archive, payloadName+"/"+record.path) != body ||
					getFile(t, archive, manifestName) != savedManifest {
					t.Fatal("verification or restoration changed the original or the backup")
				}
			})
		}
	}
}

func TestBackupRefusesInUseLinkedAndNestedData(t *testing.T) {
	t.Run("lock", func(t *testing.T) {
		parent := testParent(t)
		prototype := fixture(t, parent)
		f, err := os.OpenFile(filepath.Join(prototype, processLock), os.O_RDWR, 0)
		if err != nil {
			t.Fatal(err)
		}
		defer f.Close()
		if err = syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
			t.Fatal(err)
		}
		dest := filepath.Join(parent, "archive")
		if err := backup(prototype, dest); err == nil || !strings.Contains(err.Error(), "process lock") {
			t.Fatalf("expected a locked source error, got %v", err)
		}
		absent(t, dest)
	})
	for _, link := range []struct {
		name string
		make func(string, string) error
	}{{"symlink", os.Symlink}, {"hardlink", os.Link}} {
		t.Run(link.name, func(t *testing.T) {
			parent := testParent(t)
			prototype := fixture(t, parent)
			if err := link.make(filepath.Join(parent, "external", "external.md"), filepath.Join(prototype, "linked")); err != nil {
				t.Fatal(err)
			}
			dest := filepath.Join(parent, "archive")
			if err := backup(prototype, dest); err == nil || !strings.Contains(err.Error(), "link") {
				t.Fatalf("expected link rejection, got %v", err)
			}
			absent(t, dest)
		})
	}
	t.Run("nested grant", func(t *testing.T) {
		parent := testParent(t)
		prototype := fixture(t, parent)
		nested := filepath.Join(prototype, "nested")
		putFile(t, nested, "file.txt", "synthetic nested file")
		putFile(t, prototype, registryFile, fmt.Sprintf(`{%q:{"path":%q,"rules":[]}}`, nested, nested))
		dest := filepath.Join(parent, "archive")
		if err := backup(prototype, dest); err == nil || !strings.Contains(err.Error(), "nested") {
			t.Fatalf("expected nested grant rejection, got %v", err)
		}
		absent(t, dest)
	})
}

func TestRestoreRefusesBadSnapshotAndPreservesDestination(t *testing.T) {
	for _, scenario := range []string{"tampered PDF", "missing referenced PDF", "wrong evidence hash", "unknown manifest"} {
		t.Run(scenario, func(t *testing.T) {
			parent := testParent(t)
			prototype := fixture(t, parent)
			archive := filepath.Join(parent, "archive")
			destination := filepath.Join(parent, "recovery")
			if scenario == "missing referenced PDF" {
				if err := os.Remove(filepath.Join(prototype, pdfPath)); err != nil {
					t.Fatal(err)
				}
			}
			if scenario == "wrong evidence hash" {
				record := getFile(t, prototype, projectPath)
				digest := sha256.Sum256([]byte(getFile(t, prototype, pdfPath)))
				putFile(t, prototype, projectPath, strings.Replace(record, fmt.Sprintf("%x", digest), strings.Repeat("0", 64), 1))
			}
			if err := backup(prototype, archive); err != nil {
				t.Fatal(err)
			}
			switch scenario {
			case "tampered PDF":
				putFile(t, archive, payloadName+"/"+pdfPath, "changed")
			case "unknown manifest":
				putFile(t, archive, manifestName, strings.Replace(getFile(t, archive, manifestName), `"version": 1`, `"version": 999`, 1))
			}
			if err := run([]string{"verify", "-source", archive}, &bytes.Buffer{}); err == nil {
				t.Fatal("invalid archive verified")
			}
			if err := restore(archive, destination); err == nil {
				t.Fatal("invalid archive restored")
			}
			absent(t, destination)
		})
	}
	t.Run("concurrent destination", func(t *testing.T) {
		parent := testParent(t)
		prototype := fixture(t, parent)
		source, err := openDirectory(prototype)
		if err != nil {
			t.Fatal(err)
		}
		defer source.Close()
		destination := filepath.Join(parent, "recovery")
		err = publish(destination, []string{source.Name()}, func(stage *os.Root, _ string) error {
			if err := writePrivate(stage, "published", []byte("stage")); err != nil {
				return err
			}
			// An empty directory is otherwise silently replaceable by rename.
			return os.Mkdir(destination, 0700)
		})
		if err == nil {
			t.Fatal("concurrently created destination was overwritten")
		}
		absent(t, filepath.Join(destination, "published"))
		entries, err := filepath.Glob(filepath.Join(parent, ".prototype-data-*"))
		if err != nil || len(entries) != 0 {
			t.Fatalf("failed restore left a staging directory: %v %v", entries, err)
		}
	})
}

func TestRecoveryRequiresAnIndependentDestination(t *testing.T) {
	parent := testParent(t)
	prototype := fixture(t, parent)
	backupDir := filepath.Join(parent, "snapshot")
	if err := backup(prototype, backupDir); err != nil {
		t.Fatal(err)
	}
	inGrant := filepath.Join(parent, "external", "recovery")
	if err := restore(backupDir, inGrant); err == nil {
		t.Fatal("restored into a linked project")
	}
	if err := backup(prototype, inGrant); err == nil {
		t.Fatal("backed up into a linked project")
	}
	absent(t, inGrant)
	current := filepath.Join(parent, "current")
	putFile(t, current, workspace.RootMarker, workspace.RootFormat)
	copy := filepath.Join(current, "restore-here")
	if err := restore(backupDir, copy); err == nil {
		t.Fatal("restored inside an existing workspace")
	}
	absent(t, copy)
	actual := filepath.Join(parent, "copies")
	if err := os.Mkdir(actual, 0700); err != nil {
		t.Fatal(err)
	}
	alias := filepath.Join(parent, "shortcut")
	if err := os.Symlink("copies", alias); err != nil {
		t.Fatal(err)
	}
	if err := restore(backupDir, filepath.Join(alias, "restored")); err == nil {
		t.Fatal("published through an alias")
	}
	absent(t, filepath.Join(actual, "restored"))
}

func TestRestoreKeepsRecordedMeetingOwnerAcrossFolderRebinding(t *testing.T) {
	parent := testParent(t)
	prototype := fixture(t, parent)
	archive := filepath.Join(parent, "backup")
	restored := filepath.Join(parent, "restored")
	file := "studio/" + externalMeetingID + ".json"
	var session map[string]any
	if err := json.Unmarshal([]byte(getFile(t, prototype, file)), &session); err != nil {
		t.Fatal(err)
	}
	// The project ID is historical. Later the directory belongs to a
	// different project, just as after a user's explicit folder change.
	session["project_id"] = externalProjectID
	session["project"] = managedPath(prototype, projectID)
	data, err := json.Marshal(session)
	if err != nil {
		t.Fatal(err)
	}
	putFile(t, prototype, file, string(data))
	var out bytes.Buffer
	if err := run([]string{"backup", "-source", prototype, "-destination", archive}, &out); err != nil {
		t.Fatal(err)
	}
	if err := run([]string{"restore", "-source", archive, "-destination", restored}, &out); err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal([]byte(getFile(t, restored, file)), &session); err != nil {
		t.Fatal(err)
	}
	if session["project_id"] != externalProjectID || session["project"] != "" {
		t.Fatal("restored meeting changed project ownership", session["project_id"], session["project"])
	}
}
