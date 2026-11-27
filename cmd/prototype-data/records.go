package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"

	"scistation.local/desktop/internal/meeting"
	"scistation.local/desktop/internal/research"
)

const projectDirectory = "research/records"
const paperDirectory = "research/library/records"
const registryFile = "projects.json"

type projectRecord struct {
	Project   research.Project             `json:"project"`
	Notes     map[string]research.Note     `json:"notes"`
	Tasks     map[string]research.Task     `json:"tasks"`
	Materials map[string]research.Material `json:"materials"`
	NoteKeys  map[string]string            `json:"noteKeys"`
	TaskKeys  map[string]string            `json:"taskKeys"`
}

type pathField struct {
	file string
	id   string
	path string
}

type legacyPaths struct {
	projects []pathField
	meetings []pathField
	registry map[string]json.RawMessage
}

func directJSON(dir, path string) (string, bool) {
	if filepath.ToSlash(filepath.Dir(path)) != dir {
		return "", false
	}
	id, ok := strings.CutSuffix(filepath.Base(path), ".json")
	return id, ok
}

func readPaths(root *os.Root) (legacyPaths, error) {
	var paths legacyPaths
	for _, dir := range []string{projectDirectory, "studio"} {
		parent := root
		if dir == projectDirectory {
			var err error
			parent, err = openSubdirectory(root, "research")
			if err != nil {
				return paths, err
			}
			defer parent.Close()
		}
		subdir, err := openSubdirectory(parent, filepath.Base(dir))
		if err != nil {
			return paths, fmt.Errorf("expected prototype directory %q: %w", dir, err)
		}
		entries, err := fs.ReadDir(subdir.FS(), ".")
		subdir.Close()
		if err != nil {
			return paths, err
		}
		for _, entry := range entries {
			id, ok := strings.CutSuffix(entry.Name(), ".json")
			if !ok || !validID(id) {
				continue
			}
			record := pathField{file: relativePath(dir, entry.Name()), id: id}
			// Read only the field needed to separate application data and
			// external grants. The snapshot itself retains the full record.
			var fields struct {
				Project json.RawMessage `json:"project"`
			}
			if err := readJSON(root, record.file, &fields); err != nil {
				return paths, err
			}
			if dir == projectDirectory {
				var project struct {
					Path string `json:"path"`
				}
				if err := json.Unmarshal(fields.Project, &project); err != nil {
					return paths, fmt.Errorf("cannot read project path in %q: %w", record.file, err)
				}
				record.path = project.Path
				paths.projects = append(paths.projects, record)
			} else {
				if err := json.Unmarshal(fields.Project, &record.path); err != nil {
					return paths, fmt.Errorf("cannot read meeting project in %q: %w", record.file, err)
				}
				paths.meetings = append(paths.meetings, record)
			}
		}
	}
	if err := readJSON(root, registryFile, &paths.registry); err != nil && !errors.Is(err, os.ErrNotExist) {
		return paths, err
	}
	return paths, nil
}

func managedPath(root, id string) string {
	return filepath.Join(root, "research", "workspaces", id)
}

func managedPaths(paths legacyPaths, originalRoot string) map[string]string {
	managed := make(map[string]string)
	for _, project := range paths.projects {
		if project.path == managedPath(originalRoot, project.id) {
			managed[project.path] = project.id
		}
	}
	return managed
}

// Protected destinations include every linked external project. Listing these
// recorded paths requires no traversal or access to the external folders.
func protectedDirectories(root *os.Root, originalRoot string) ([]string, error) {
	paths, err := readPaths(root)
	if err != nil {
		return nil, err
	}
	managed := managedPaths(paths, originalRoot)
	protected := []string{originalRoot}
	add := func(path string, owned bool) error {
		if path == "" || owned {
			return nil
		}
		if !absoluteDirectoryName(path) {
			return errors.New("cannot identify an external project directory")
		}
		if within(originalRoot, path) {
			return errors.New("an external project is nested inside the application data directory; back it up separately")
		}
		protected = append(protected, path)
		return nil
	}
	for _, record := range paths.projects {
		if err := add(record.path, record.path == managedPath(originalRoot, record.id)); err != nil {
			return nil, err
		}
	}
	for _, record := range paths.meetings {
		if err := add(record.path, managed[record.path] != ""); err != nil {
			return nil, err
		}
	}
	for path, body := range paths.registry {
		var grant struct {
			Path string `json:"path"`
		}
		if err := json.Unmarshal(body, &grant); err != nil || grant.Path != path {
			return nil, errors.New("cannot distinguish project registry paths")
		}
		if err := add(path, managed[path] != ""); err != nil {
			return nil, err
		}
	}
	return protected, nil
}

func restorePaths(stage *os.Root, m manifest, destination string) error {
	paths, err := readPaths(stage)
	if err != nil {
		return err
	}
	managed := managedPaths(paths, m.Source)
	projectByPath := make(map[string]string)
	for _, project := range paths.projects {
		if project.path == "" {
			continue
		}
		if _, duplicate := projectByPath[project.path]; duplicate {
			projectByPath[project.path] = ""
		} else {
			projectByPath[project.path] = project.id
		}
	}
	relocate := func(path string) string {
		if id, ok := managed[path]; ok {
			return managedPath(destination, id)
		}
		return ""
	}
	for _, record := range paths.projects {
		var document, project map[string]json.RawMessage
		if err := readJSON(stage, record.file, &document); err != nil {
			return err
		}
		if err := json.Unmarshal(document["project"], &project); err != nil || project == nil {
			return fmt.Errorf("cannot restore project %q", record.file)
		}
		newPath := ""
		if record.path == managedPath(m.Source, record.id) {
			newPath = managedPath(destination, record.id)
			project["managedDirectory"] = json.RawMessage("true")
		} else {
			// Compare against the saved identity if the project is rebound.
			// The old path may already refer to a different directory.
			var grant research.DirectoryGrant
			if json.Unmarshal(project["directoryGrant"], &grant) == nil && grant.Inode != 0 {
				document["previousDirectoryIdentity"], _ = json.Marshal(grant)
			}
			delete(project, "managedDirectory")
		}
		delete(project, "directoryGrant")
		project["path"], _ = json.Marshal(newPath)
		document["project"], err = json.Marshal(project)
		if err != nil {
			return err
		}
		if err = writeJSON(stage, record.file, document); err != nil {
			return err
		}
	}
	for _, record := range paths.meetings {
		var document map[string]json.RawMessage
		if err := readJSON(stage, record.file, &document); err != nil {
			return err
		}
		var id string
		if raw := document["project_id"]; raw != nil {
			if err := json.Unmarshal(raw, &id); err != nil {
				return err
			}
		}
		// An explicit identity survives even if another project now owns the
		// old path. Only a legacy meeting with no ID needs inference.
		if id == "" {
			id = projectByPath[record.path]
			if id != "" {
				document["project_id"], _ = json.Marshal(id)
			}
		}
		newPath := ""
		if id != "" && id == managed[record.path] {
			newPath = relocate(record.path)
		}
		if id == "" && record.path != "" {
			// Preserve an unbound historical session as such. An empty path
			// and no ID would incorrectly convert it into a global session.
			newPath = record.path
		}
		document["project"], _ = json.Marshal(newPath)
		if err := writeJSON(stage, record.file, document); err != nil {
			return err
		}
	}
	if len(paths.registry) > 0 {
		// A restored archive has no approved paths outside the isolated copy.
		registry := make(map[string]json.RawMessage)
		for path, record := range paths.registry {
			newPath := relocate(path)
			if newPath == "" {
				newPath = path
			}
			if _, exists := registry[newPath]; exists {
				return errors.New("conflicting restored rule snapshot paths")
			}
			var fields map[string]json.RawMessage
			if err := json.Unmarshal(record, &fields); err != nil || fields == nil {
				return errors.New("cannot restore the project registry")
			}
			delete(fields, "directoryGrant")
			fields["path"], _ = json.Marshal(newPath)
			registry[newPath], err = json.Marshal(fields)
			if err != nil {
				return err
			}
		}
		if err := writeJSON(stage, registryFile, registry); err != nil {
			return err
		}
	}
	// Executable overrides are local to the original installation. Saved
	// round settings are historical and are never used to replay a turn.
	var settings map[string]json.RawMessage
	if err := readJSON(stage, "settings.json", &settings); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	if _, ok := settings["cli_paths"]; ok {
		delete(settings, "cli_paths")
		return writeJSON(stage, "settings.json", settings)
	}
	return nil
}

func writeJSON(root *os.Root, path string, value any) error {
	body, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return err
	}
	return writePrivate(root, path, append(body, '\n'))
}

func readResearchRecord(root *os.Root, path string, out any) error {
	var data json.RawMessage
	if err := readJSON(root, path, &data); err != nil {
		return err
	}
	if err := research.DecodeRecordJSON(data, out); err != nil {
		return fmt.Errorf("invalid research record %q: %w", path, err)
	}
	return nil
}

// Validate references to records and bytes owned by the prototype. Historical
// note/task evidence can point to deliberately removed papers or meetings.
func validateRecords(root *os.Root, m manifest) error {
	projects := make(map[string]bool)
	for path := range m.Entries {
		if id, ok := directJSON(projectDirectory, path); ok {
			var d projectRecord
			if err := readResearchRecord(root, path, &d); err != nil {
				return err
			}
			if !validID(id) || d.Project.ID != id || d.Project.Revision < 1 || d.Notes == nil ||
				d.Tasks == nil || d.Materials == nil || d.NoteKeys == nil || d.TaskKeys == nil {
				return fmt.Errorf("invalid project record %q", path)
			}
			projects[id] = true
			if d.Project.Path == managedPath(m.Source, id) && !m.Entries[relativePath("research/workspaces", id)].Directory {
				return fmt.Errorf("%q refers to a missing managed project directory", path)
			}
			for key, note := range d.Notes {
				if key != note.ID || note.ProjectID != id {
					return fmt.Errorf("%q contains a note with an invalid owner or ID", path)
				}
				for _, source := range note.Evidence {
					if !validID(source.PaperID) || source.SourceHash == "" {
						continue
					}
					paper := m.Entries[relativePath(paperDirectory, source.PaperID+".json")]
					pdf := m.Entries[relativePath("research/library/pdf", source.PaperID+".pdf")]
					if paper.SHA256 != "" && pdf.SHA256 != source.SourceHash {
						return fmt.Errorf("%q contains a note with a mismatched PDF source hash", path)
					}
				}
			}
			for key, task := range d.Tasks {
				if key != task.ID || task.ProjectID != id {
					return fmt.Errorf("%q contains a task with an invalid owner or ID", path)
				}
			}
			for key, item := range d.Materials {
				blob := m.Entries[relativePath("research/blobs", key)]
				if !validID(key) || key != item.ID || item.ProjectID != id || blob.SHA256 == "" || blob.Size != item.Size {
					return fmt.Errorf("%q refers to a missing or invalid project material %q", path, key)
				}
			}
		}
	}
	for path := range m.Entries {
		switch {
		case filepath.Dir(path) == paperDirectory && strings.HasSuffix(path, ".json"):
			if err := validatePaper(root, m.Entries, path, projects); err != nil {
				return err
			}
		case filepath.Dir(path) == "studio" && strings.HasSuffix(path, ".json"):
			id, _ := directJSON("studio", path)
			if validID(id) {
				if err := validateMeeting(root, m.Entries, path, id, projects); err != nil {
					return err
				}
			}
		}
	}
	return validatePlugins(root, m.Entries)
}

func validatePaper(root *os.Root, entries map[string]treeEntry, path string, projects map[string]bool) error {
	id, _ := directJSON(paperDirectory, path)
	var p research.Paper
	if err := readResearchRecord(root, path, &p); err != nil {
		return err
	}
	if !validID(id) || p.ID != id || p.Revision < 1 {
		return fmt.Errorf("invalid paper record %q", path)
	}
	if p.HasPDF {
		pdf := entries[relativePath("research/library/pdf", id+".pdf")]
		if pdf.SHA256 == "" || pdf.SHA256 != p.FileSHA256 {
			return fmt.Errorf("%q refers to a missing PDF or one with an incorrect SHA-256", path)
		}
	}
	for _, ids := range [][]string{p.ProjectIDs, p.CoreProjectIDs} {
		for _, project := range ids {
			if !projects[project] {
				return fmt.Errorf("%q refers to missing project %q", path, project)
			}
		}
	}
	for project := range p.ProjectLinks {
		if !projects[project] {
			return fmt.Errorf("%q refers to missing project %q", path, project)
		}
	}
	return nil
}

func validateMeeting(root *os.Root, entries map[string]treeEntry, path, id string, projects map[string]bool) error {
	var s struct {
		meeting.Session
		ProjectID string `json:"project_id"`
	}
	if err := readJSON(root, path, &s); err != nil {
		return err
	}
	if s.ID != id {
		return fmt.Errorf("invalid meeting record %q", path)
	}
	if s.ProjectID != "" && !projects[s.ProjectID] {
		return fmt.Errorf("%q refers to missing project %q", path, s.ProjectID)
	}
	for _, item := range s.Materials {
		if !validID(item.ID) {
			return fmt.Errorf("%q has an invalid meeting material ID", path)
		}
		dir := relativePath("studio/materials", item.ID)
		var metadata meeting.Material
		if err := readJSON(root, relativePath(dir, "metadata.json"), &metadata); err != nil {
			return err
		}
		file := entries[relativePath(dir, "original")]
		if metadata.ID != item.ID || file.SHA256 == "" || file.Size != metadata.Size || item.Size != metadata.Size {
			return fmt.Errorf("%q refers to a missing or invalid meeting material %q", path, item.ID)
		}
	}
	return nil
}

func validatePlugins(root *os.Root, entries map[string]treeEntry) error {
	const path = "plugins/registry.json"
	var registry struct {
		SchemaVersion int                        `json:"schema_version"`
		Sources       map[string]json.RawMessage `json:"sources"`
		Installed     map[string]struct {
			ID     string `json:"id"`
			SHA256 string `json:"sha256"`
		} `json:"installed"`
	}
	if err := readJSON(root, path, &registry); err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil
		}
		return err
	}
	if registry.SchemaVersion != 1 || registry.Sources == nil || registry.Installed == nil {
		return errors.New("unsupported prototype plugin registry")
	}
	for id, plugin := range registry.Installed {
		digest := plugin.SHA256
		if id != plugin.ID || len(digest) != 64 || !validDigest(digest) ||
			entries[relativePath("plugins/packages", digest)].SHA256 != digest {
			return fmt.Errorf("installed plugin %q refers to a missing package or one with an incorrect SHA-256", id)
		}
	}
	return nil
}
