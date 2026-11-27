package research

import (
	"errors"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"syscall"

	"scistation.local/desktop/internal/workspace"
)

// A grant is tied to the selected directory, including its filesystem identity.
// Replacing a directory at the same spelling requires a new explicit selection.
type DirectoryGrant struct {
	Device uint64 `json:"device"`
	Inode  uint64 `json:"inode"`
}

func IdentifyDirectory(path string) (DirectoryGrant, error) {
	if path == "" || filepath.Clean(path) != path {
		return DirectoryGrant{}, os.ErrPermission
	}
	if _, err := workspace.Validate(path); err != nil {
		return DirectoryGrant{}, fmt.Errorf("%w: %v", os.ErrPermission, err)
	}
	info, err := os.Lstat(path)
	if err != nil {
		return DirectoryGrant{}, err
	}
	st, ok := info.Sys().(*syscall.Stat_t)
	if !ok || !info.IsDir() {
		return DirectoryGrant{}, os.ErrPermission
	}
	return DirectoryGrant{Device: uint64(st.Dev), Inode: uint64(st.Ino)}, nil
}

func (s *Service) managedDirectory(id string, trashed bool) string {
	if trashed {
		return filepath.Join(s.dir, "trash", id)
	}
	return filepath.Join(s.dir, "workspaces", id)
}

func (s *Service) isManaged(p Project) bool {
	return p.ManagedDirectory || p.Path == s.managedDirectory(p.ID, false)
}

func (s *Service) externalDirectory(path string) (DirectoryGrant, error) {
	grant, err := IdentifyDirectory(path)
	if err != nil {
		return DirectoryGrant{}, err
	}
	root := s.dir
	if filepath.Base(s.dir) == "research" {
		root = filepath.Dir(s.dir)
	}
	// A grant must not include a workspace's private database or include an
	// ancestor of this active root. This also protects other marked roots.
	if path == root || strings.HasPrefix(root, path+string(filepath.Separator)) {
		return DirectoryGrant{}, os.ErrPermission
	}
	for curr := path; ; curr = filepath.Dir(curr) {
		if curr == root {
			return DirectoryGrant{}, os.ErrPermission
		}
		for _, marker := range []string{workspace.RootMarker, ".sci-station"} {
			if _, err := os.Lstat(filepath.Join(curr, marker)); !os.IsNotExist(err) {
				return DirectoryGrant{}, os.ErrPermission
			}
		}
		if filepath.Dir(curr) == curr {
			break
		}
	}
	return grant, nil
}

func (s *Service) directory(d projectData) (string, error) {
	if d.Project.ConversationResetPending {
		return "", errResetPending
	}
	if s.isManaged(d.Project) {
		path := s.managedDirectory(d.Project.ID, false)
		if _, err := IdentifyDirectory(path); err != nil {
			return "", err
		}
		return path, nil
	}
	if d.Project.DirectoryGrant == nil {
		return "", os.ErrPermission
	}
	grant, err := s.externalDirectory(d.Project.Path)
	if err != nil {
		return "", err
	}
	if grant != *d.Project.DirectoryGrant {
		return "", os.ErrPermission
	}
	return d.Project.Path, nil
}

func (s *Service) WithProjectDirectory(id string, operation func(string) error) error {
	s.mu.RLock()
	defer s.mu.RUnlock()
	d, ok := s.projects[id]
	if !ok || d.Archived {
		return os.ErrNotExist
	}
	path, err := s.directory(d)
	if err != nil {
		return err
	}
	return operation(path)
}

func (s *Service) ProjectDirectory(id string) (string, error) {
	var path string
	err := s.WithProjectDirectory(id, func(dir string) error { path = dir; return nil })
	return path, err
}

func (s *Service) ProjectForDirectory(path string) (Project, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	var match Project
	for _, d := range s.projects {
		if d.Archived || d.Project.Path != path {
			continue
		}
		if _, err := s.directory(d); err == nil {
			if match.ID != "" {
				return Project{}, false
			}
			match = d.Project
		}
	}
	return match, match.ID != ""

}

func newProjectData(p Project) projectData {
	return projectData{Project: p, Notes: map[string]Note{}, Tasks: map[string]Task{}, Materials: map[string]Material{}, NoteKeys: map[string]string{}, TaskKeys: map[string]string{}}
}

// Resolve an explicit Add/Import selection. A prior project at this path
// must pass its current grant; historical rows cannot reactivate it.
func (s *Service) selectedRuleFolder(path, expectedID string) (projectData, DirectoryGrant, error) {
	var owner projectData
	known := false
	for _, d := range s.projects {
		if d.Project.Path != path {
			continue
		}
		known = true
		if d.Archived || (expectedID != "" && d.Project.ID != expectedID) {
			continue
		}
		if owner.Project.ID != "" {
			return projectData{}, DirectoryGrant{}, fmt.Errorf("%w: 请选择明确的科研项目", workspace.ErrConflict)
		}
		owner = d
	}
	if owner.Project.ID != "" {
		current, err := s.directory(owner)
		if err != nil {
			return projectData{}, DirectoryGrant{}, err
		}
		if !s.isManaged(owner.Project) {
			return owner, *owner.Project.DirectoryGrant, nil
		}
		grant, err := IdentifyDirectory(current)
		return owner, grant, err
	}
	if known || expectedID != "" {
		return projectData{}, DirectoryGrant{}, os.ErrNotExist
	}
	grant, err := s.externalDirectory(path)
	return projectData{}, grant, err
}

// Hold the current authorization during an explicit preview or import. The
// file reader gets a pinned directory, scoped only to this invocation.
func (s *Service) WithRuleImportDirectory(path, id string, read func(*os.Root, string, DirectoryGrant, []RoundtableRule) error) error {
	s.mu.RLock()
	defer s.mu.RUnlock()
	d, grant, err := s.selectedRuleFolder(path, id)
	if err != nil {
		return err
	}
	root, err := workspace.ManagedOpenDirectory(path)
	if err != nil {
		return err
	}
	defer root.Close()
	info, err := root.Stat(".")
	if err != nil {
		return err
	}
	stat := info.Sys().(*syscall.Stat_t)
	if grant.Device != uint64(stat.Dev) || grant.Inode != uint64(stat.Ino) {
		return os.ErrPermission
	}
	return read(root, d.Project.ID, grant, slices.Clone(d.RoundtableRules))
}

func (s *Service) RegisterDirectoryProject(path, id string, selected DirectoryGrant, rules ...RoundtableRule) (Project, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	d, grant, err := s.selectedRuleFolder(path, id)
	if err != nil {
		return Project{}, err
	}
	if grant != selected {
		return Project{}, os.ErrPermission
	}
	combined, err := MergeRoundtableRules(d.RoundtableRules, rules)
	if err != nil {
		return Project{}, err
	}
	if d.Project.ID == "" {
		p := newProject()
		p.Name, p.Path, p.DirectoryGrant = filepath.Base(path), path, &grant
		d = newProjectData(p)
	} else {
		if slices.Equal(combined, d.RoundtableRules) {
			return d.Project, nil
		}
		d.Project.bump()
	}
	d.RoundtableRules = combined
	if err := s.commit(d); err != nil {
		return Project{}, err
	}
	return d.Project, nil
}

// Recover the data directory if a filesystem move completed before its record
// replacement. The durable project state selects exactly one location.
func (s *Service) recoverManagedDirectory(d *projectData) error {
	p := &d.Project
	legacy := filepath.Join("research", "workspaces", p.ID)
	if !s.isManaged(*p) && !(p.DirectoryGrant == nil && strings.HasSuffix(p.Path, string(filepath.Separator)+legacy)) {
		return nil
	}
	target := s.managedDirectory(p.ID, d.Trashed)
	other := s.managedDirectory(p.ID, !d.Trashed)
	info, err := os.Lstat(target)
	if err == nil && !info.IsDir() {
		return fmt.Errorf("invalid managed directory for %s", p.ID)
	}
	if os.IsNotExist(err) {
		old, issue := os.Lstat(other)
		if issue != nil {
			return fmt.Errorf("cannot recover managed directory: %w", issue)
		}
		if !old.IsDir() {
			return os.ErrPermission
		}
		if err = workspace.ManagedRename(other, target); err != nil {
			return err
		}
	} else if err != nil {
		return err
	}
	p.Path = target
	p.ManagedDirectory = true
	return nil
}

func (s *Service) moveLifecycle(w http.ResponseWriter, d projectData, trash bool) bool {
	if s.isManaged(d.Project) && d.Trashed != trash {
		from, to := s.managedDirectory(d.Project.ID, d.Trashed), s.managedDirectory(d.Project.ID, trash)
		src, err := os.Lstat(from)
		if err != nil || !src.IsDir() {
			jsonFail(w, 409, "无法找到项目的受管文件夹")
			return false
		}
		if _, err := os.Lstat(to); !os.IsNotExist(err) {
			jsonFail(w, 409, "目标目录已存在或不可访问")
			return false
		}
		if err := workspace.ManagedRename(from, to); err != nil {
			jsonFail(w, 500, "无法移动项目目录")
			return false
		}
		d.Project.Path = to
		d.Project.ManagedDirectory = true
		d.Trashed = trash
		if !s.save(w, d) {
			_ = workspace.ManagedRename(to, from)
			return false
		}
		return true
	}
	d.Trashed = trash
	return s.save(w, d)
}

func (s *Service) trashProject(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Revision int `json:"revision"`
	}
	if !payload(w, r, &in) {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	d, ok := s.projects[r.PathValue("project")]
	if !found(w, ok && !d.Trashed) || !revisionOK(w, d.Project.Revision, in.Revision) {
		return
	}
	d.Archived = true
	d.Project.bump()
	if s.moveLifecycle(w, d, true) {
		w.WriteHeader(204)
	}
}

// ValidateExternalDirectory checks a proposed external grant before previewing
// its rules or storing a path registration.
func (s *Service) ValidateExternalDirectory(path string) error {
	_, err := s.externalDirectory(path)
	if errors.Is(err, os.ErrPermission) {
		return fmt.Errorf("%w: 请选择独立的外部项目目录", err)
	}
	return err
}
