package research

import (
	"bytes"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"maps"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"slices"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode"
	"unicode/utf8"

	"scistation.local/desktop/internal/workspace"
)

const prefix = "/api/research"

type Entity struct {
	ID        string `json:"id"`
	Revision  int    `json:"revision"`
	CreatedAt string `json:"createdAt"`
	UpdatedAt string `json:"updatedAt"`
}

type Project struct {
	ManagedDirectory bool            `json:"managedDirectory,omitempty"`
	DirectoryGrant   *DirectoryGrant `json:"directoryGrant,omitempty"`
	Entity
	Name        string `json:"name"`
	Description string `json:"description"`
	Path        string `json:"path"`
}

type Evidence struct {
	PaperID        string `json:"paperId,omitempty"`
	Page           int    `json:"page,omitempty"`
	Quote          string `json:"quote"`
	SourceHash     string `json:"sourceHash,omitempty"`
	MeetingID      string `json:"meetingId,omitempty"`
	TurnID         string `json:"turnId,omitempty"`
	AnnotationID   string `json:"annotationId,omitempty"`
	SelectionStart *int   `json:"selectionStart,omitempty"`
	SelectionEnd   *int   `json:"selectionEnd,omitempty"`
	OCR            bool   `json:"ocr,omitempty"`
}

type Note struct {
	Entity
	ProjectID       string     `json:"projectId"`
	Title           string     `json:"title"`
	Namespace       string     `json:"namespace,omitempty"`
	Aliases         []string   `json:"aliases,omitempty"`
	PreviousPaths   []string   `json:"previousPaths,omitempty"`
	Archived        bool       `json:"archived,omitempty"`
	Template        string     `json:"template,omitempty"`
	Body            string     `json:"body"`
	Tags            []string   `json:"tags"`
	PaperID         string     `json:"paperId,omitempty"`
	Evidence        []Evidence `json:"evidence"`
	SourceMeetingID string     `json:"sourceMeetingId,omitempty"`
	SourceTurnID    string     `json:"sourceTurnId,omitempty"`
}

type Task struct {
	Entity
	ProjectID          string     `json:"projectId"`
	ProjectIDs         []string   `json:"projectIds"`
	Title              string     `json:"title"`
	Description        string     `json:"description"`
	Status             string     `json:"status"`
	Kind               string     `json:"kind"`
	Priority           string     `json:"priority"`
	Tags               []string   `json:"tags"`
	StartDate          string     `json:"startDate,omitempty"`
	DueDate            string     `json:"dueDate"`
	DueTime            string     `json:"dueTime,omitempty"`
	CompletedAt        string     `json:"completedAt,omitempty"`
	PaperID            string     `json:"paperId,omitempty"`
	RelatedPaperIDs    []string   `json:"relatedPaperIds"`
	ExternalSource     string     `json:"externalSource,omitempty"`
	ExternalIdentifier string     `json:"externalIdentifier,omitempty"`
	AppleReminderID    string     `json:"appleReminderId,omitempty"`
	ReminderRevision   int        `json:"reminderRevision,omitempty"`
	Evidence           []Evidence `json:"evidence,omitempty"`
	extra              map[string]json.RawMessage
}

type Material struct {
	Entity
	ProjectID string `json:"projectId"`
	Name      string `json:"name"`
	MediaType string `json:"mediaType"`
	Size      int64  `json:"size"`
}

type projectData struct {
	Trashed     bool                     `json:"trashed,omitempty"`
	Reviews     map[string]MeetingReview `json:"reviews,omitempty"`
	Project     Project                  `json:"project"`
	Archived    bool                     `json:"archived,omitempty"`
	Notes       map[string]Note          `json:"notes"`
	Tasks       map[string]Task          `json:"tasks"`
	Materials   map[string]Material      `json:"materials"`
	NoteKeys    map[string]string        `json:"noteKeys"`
	TaskKeys    map[string]string        `json:"taskKeys"`
	Relations   map[string]GraphRelation `json:"relations,omitempty"`
	disk        json.RawMessage
	WikiFolders []string `json:"wikiFolders,omitempty"`
}

// Published project snapshots are immutable. Each mutation copies only its own map
// and installs the new snapshot after the single on-disk replacement succeeds.
type Service struct {
	dir             string
	mux             *http.ServeMux
	papers          *PaperLibrary
	mu              sync.RWMutex
	projects        map[string]projectData
	workspaceTasks  workspaceTaskData
	pathValidator   func(string) bool
	newTaskReminder func(Task) (string, error)
}

func New(dir string) (*Service, error) {
	absolute, err := filepath.Abs(dir)
	if err != nil {
		return nil, err
	}
	if err = workspace.ManagedMkdirAll(absolute, 0700); err != nil {
		return nil, err
	}
	absolute, err = filepath.EvalSymlinks(absolute)
	if err != nil {
		return nil, err
	}
	s := &Service{dir: absolute, mux: http.NewServeMux(), projects: map[string]projectData{}}
	for _, name := range []string{"records", "workspaces", "blobs", "trash"} {
		if err = workspace.ManagedMkdirAll(filepath.Join(s.dir, name), 0700); err != nil {
			return nil, err
		}
	}
	entries, err := workspace.ManagedReadDir(filepath.Join(s.dir, "records"))
	if err != nil {
		return nil, err
	}
	for _, e := range entries {
		name := e.Name()
		if !strings.HasSuffix(name, ".json") {
			continue
		}
		id := strings.TrimSuffix(name, ".json")
		if !validID(id) || !e.Type().IsRegular() {
			return nil, fmt.Errorf("无效的科研项目文件 %q", name)
		}
		b, err := workspace.ManagedReadFile(s.recordPath(id))
		if err != nil {
			return nil, err
		}
		var d projectData
		if err = json.Unmarshal(b, &d); err != nil || d.Project.ID != id || d.Project.Revision < 1 || d.Notes == nil || d.Tasks == nil || d.Materials == nil || d.NoteKeys == nil || d.TaskKeys == nil {
			return nil, fmt.Errorf("科研项目文件无法读取 %q", name)
		}
		d.disk = b
		if err = s.recoverManagedDirectory(&d); err != nil {
			return nil, err
		}
		s.projects[id] = d
	}
	if err = s.loadWorkspaceTasks(); err != nil {
		return nil, err
	}
	s.papers, err = NewPaperLibrary(filepath.Join(s.dir, "library"))
	if err != nil {
		return nil, err
	}
	s.papers.SetProjectValidator(s.projectExists)
	s.mux.Handle(prefix+"/papers", s.papers)
	s.mux.Handle(prefix+"/papers/", s.papers)
	s.mux.HandleFunc("GET "+prefix+"/paper-wiki-status", s.paperWikiStatus)
	s.mux.HandleFunc("GET "+prefix+"/projects", s.listProjects)
	s.mux.HandleFunc("POST "+prefix+"/projects", s.createProject)
	for _, method := range []string{"GET", "PATCH", "DELETE"} {
		s.mux.HandleFunc(method+" "+prefix+"/projects/{project}", s.project)
	}
	s.mux.HandleFunc("POST "+prefix+"/projects/{project}/restore", s.restoreProject)
	s.mux.HandleFunc("POST "+prefix+"/projects/{project}/trash", s.trashProject)
	s.mux.HandleFunc("POST "+prefix+"/projects/{project}/directory", s.changeDirectory)
	s.registerReviews()
	s.registerNotes()
	s.mux.HandleFunc("GET "+prefix+"/dashboard/projects", s.dashboardProjects)
	s.registerTasks()
	s.registerMaterials()
	s.registerModules()
	s.registerInterface()
	s.mux.HandleFunc("GET "+prefix+"/projects/{project}/files", s.files)
	s.mux.HandleFunc("PATCH "+prefix+"/projects/{project}/files", s.files)
	s.mux.HandleFunc("GET "+prefix+"/projects/{project}/graph", s.graph)
	s.mux.HandleFunc("POST "+prefix+"/projects/{project}/graph/relations", s.relations)
	s.mux.HandleFunc("DELETE "+prefix+"/projects/{project}/graph/relations/{relation}", s.relations)
	return s, nil
}

func (s *Service) ServeHTTP(w http.ResponseWriter, r *http.Request) { s.mux.ServeHTTP(w, r) }

// SetPathValidator is set by the desktop host after the native project registry is open.
func (s *Service) SetPathValidator(allowed func(string) bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.pathValidator = allowed
}

// Archived projects remain valid identities for existing shared library records.
func (s *Service) projectExists(id string) bool {
	s.mu.RLock()
	defer s.mu.RUnlock()
	_, exists := s.projects[id]
	return exists
}

// HasActiveProject resolves an active project before a scoped operation.
func (s *Service) HasActiveProject(id string) bool {
	s.mu.RLock()
	defer s.mu.RUnlock()
	d, ok := s.projects[id]
	return ok && !d.Archived
}
func (s *Service) recordPath(id string) string { return filepath.Join(s.dir, "records", id+".json") }
func (s *Service) commit(d projectData) error {
	path := s.recordPath(d.Project.ID)
	old, exists := s.projects[d.Project.ID]
	info, err := os.Lstat(path)
	if err == nil && !info.Mode().IsRegular() {
		return fmt.Errorf("invalid project record: %s", d.Project.ID)
	}
	disk, err := workspace.ManagedReadFile(path)
	if err != nil && (exists || !errors.Is(err, os.ErrNotExist)) {
		return err
	}
	if (exists && !bytes.Equal(old.disk, disk)) || (!exists && err == nil) {
		return errProjectRecordChanged
	}
	b, err := json.Marshal(d)
	if err != nil {
		return err
	}
	if exists {
		before, err := json.Marshal(old)
		if err != nil {
			return err
		}
		b = mergeRecordFields(disk, before, b)
	}
	if err = atomicWrite(path, b); err != nil {
		return err
	}
	d.disk = b
	s.projects[d.Project.ID] = d
	return nil
}

var errProjectRecordChanged = errors.New("project record changed on disk")

func atomicWrite(path string, b []byte) error { return workspace.ManagedAtomicWrite(path, b) }
func makeID() string                          { var b [16]byte; rand.Read(b[:]); return hex.EncodeToString(b[:]) }
func validID(id string) bool {
	if len(id) != 32 {
		return false
	}
	_, err := hex.DecodeString(id)
	return err == nil && strings.ToLower(id) == id
}
func now() string       { return time.Now().UTC().Format(time.RFC3339Nano) }
func fresh() Entity     { t := now(); return Entity{ID: makeID(), Revision: 1, CreatedAt: t, UpdatedAt: t} }
func (e *Entity) bump() { e.Revision++; e.UpdatedAt = now() }
func jsonReply(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}
func jsonFail(w http.ResponseWriter, status int, message string) {
	jsonReply(w, status, map[string]string{"error": message})
}
func readPayload(r *http.Request, out any) error {
	data, err := io.ReadAll(io.LimitReader(r.Body, (4<<20)+1))
	if err != nil {
		return err
	}
	if len(data) > 4<<20 {
		return errors.New("请求内容过大")
	}
	dec := json.NewDecoder(strings.NewReader(string(data)))
	dec.DisallowUnknownFields()
	if err := dec.Decode(out); err != nil {
		return errors.New("JSON 对象或字段无效")
	}
	if dec.Decode(new(any)) != io.EOF {
		return errors.New("只接受一个 JSON 对象")
	}
	return nil
}
func payload(w http.ResponseWriter, r *http.Request, v any) bool {
	if err := readPayload(r, v); err != nil {
		jsonFail(w, 400, err.Error())
		return false
	}
	return true
}
func label(s string, max int) bool {
	return strings.TrimSpace(s) != "" && utf8.ValidString(s) && utf8.RuneCountInString(s) <= max && strings.IndexFunc(s, unicode.IsControl) < 0
}
func revisionOK(w http.ResponseWriter, actual, provided int) bool {
	if provided < 1 {
		jsonFail(w, 428, "请携带已读取的 revision")
		return false
	}
	if provided != actual {
		jsonFail(w, 409, "内容已改变，请重新加载")
		return false
	}
	return true
}
func queryRevision(q url.Values) int { n, _ := strconv.Atoi(q.Get("revision")); return n }
func found(w http.ResponseWriter, ok bool) bool {
	if !ok {
		jsonFail(w, 404, "未找到这条记录")
	}
	return ok
}
func (s *Service) loadProject(w http.ResponseWriter, id string) (projectData, bool) {
	d, ok := s.projects[id]
	return d, found(w, ok && !d.Archived)
}
func (s *Service) save(w http.ResponseWriter, d projectData) bool {
	if err := s.commit(d); err != nil {
		if errors.Is(err, errProjectRecordChanged) {
			jsonFail(w, 409, "项目文件在应用之外已改变，请重新打开科研工作区")
			return false
		}
		jsonFail(w, 500, "无法保存科研数据")
		return false
	}
	return true
}
func valuesBy[T any](m map[string]T, before func(a, b T) bool) []T {
	out := make([]T, 0, len(m))
	for v := range maps.Values(m) {
		out = append(out, v)
	}
	sort.Slice(out, func(i, j int) bool { return before(out[i], out[j]) })
	return out
}
func (s *Service) listProjects(w http.ResponseWriter, r *http.Request) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := []Project{}
	archived := r.URL.Query().Get("archived") == "1"
	for _, d := range s.projects {
		if d.Trashed == (r.URL.Query().Get("trashed") == "1") && (d.Trashed || d.Archived == archived) {
			out = append(out, d.Project)
		}
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].Name == out[j].Name {
			return out[i].ID < out[j].ID
		}
		return out[i].Name < out[j].Name
	})
	jsonReply(w, 200, out)
}

type projectInput struct {
	Name        *string `json:"name"`
	Description *string `json:"description"`
	Path        *string `json:"path"`
	Revision    int     `json:"revision"`
}

func updateProject(p *Project, in projectInput) bool {
	if in.Name != nil {
		p.Name = strings.TrimSpace(*in.Name)
	}
	if in.Description != nil {
		p.Description = *in.Description
	}
	return label(p.Name, 200) && len(p.Description) <= 128<<10
}
func (s *Service) createProject(w http.ResponseWriter, r *http.Request) {
	var in projectInput
	if !payload(w, r, &in) {
		return
	}
	p := Project{Entity: fresh()}
	if !updateProject(&p, in) {
		jsonFail(w, 400, "项目名称或说明无效")
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	managed := in.Path == nil || strings.TrimSpace(*in.Path) == ""
	if managed {
		p.ManagedDirectory = true
		p.Path = s.managedDirectory(p.ID, false)
		if err := workspace.ManagedMkdir(p.Path, 0700); err != nil {
			jsonFail(w, 500, "无法建立项目文件夹")
			return
		}
	} else {
		path := *in.Path
		if !filepath.IsAbs(path) || filepath.Clean(path) != path || s.pathValidator == nil || !s.pathValidator(path) {
			jsonFail(w, 403, "请先在圆桌登记所选项目文件夹")
			return
		}
		grant, err := s.externalDirectory(path)
		if err != nil {
			jsonFail(w, 400, "项目文件夹不可用")
			return
		}
		for _, existing := range s.projects {
			if !existing.Archived && existing.Project.Path == path {
				jsonFail(w, 409, "这个文件夹已关联科研项目")
				return
			}
		}
		p.Path = path
		p.DirectoryGrant = &grant
	}
	d := newProjectData(p)
	if !s.save(w, d) {
		if managed {
			_ = workspace.ManagedRemove(p.Path)
		}
		return
	}
	jsonReply(w, 201, p)
}
func (s *Service) project(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("project")
	if r.Method == "GET" || r.Method == "HEAD" {
		s.mu.RLock()
		defer s.mu.RUnlock()
		if d, ok := s.loadProject(w, id); ok {
			jsonReply(w, 200, d.Project)
		}
		return
	}
	var in projectInput
	if r.Method == "PATCH" && !payload(w, r, &in) {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	d, ok := s.loadProject(w, id)
	if !ok {
		return
	}
	if r.Method == "DELETE" {
		if !revisionOK(w, d.Project.Revision, queryRevision(r.URL.Query())) {
			return
		}
		d.Archived = true
		d.Project.bump()
		if s.save(w, d) {
			w.WriteHeader(204)
		}
		return
	}
	if !revisionOK(w, d.Project.Revision, in.Revision) {
		return
	}
	if in.Path != nil && *in.Path != d.Project.Path {
		jsonFail(w, 400, "已绑定的目录不可直接修改")
		return
	}
	if !updateProject(&d.Project, in) {
		jsonFail(w, 400, "项目名称或说明无效")
		return
	}
	d.Project.bump()
	if s.save(w, d) {
		jsonReply(w, 200, d.Project)
	}
}

// PaperPDFPath resolves a stored original for the desktop's conversion adapter.
func (s *Service) PaperPDFPath(id string) (string, error) { return s.papers.PDFPath(id) }

// Task resolves a workspace task before a native calendar or reminder operation.
func (s *Service) Task(projectID, taskID string) (Task, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	_, task, ok := s.findTaskLocked(projectID, taskID)
	task.ProjectIDs = slices.Clone(task.ProjectIDs)
	task.RelatedPaperIDs = slices.Clone(task.RelatedPaperIDs)
	task.Tags = slices.Clone(task.Tags)
	task.Evidence = slices.Clone(task.Evidence)
	return task, ok
}

// restoreProject reactivates a project without creating or rewriting its working folder.
func (s *Service) restoreProject(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Revision int `json:"revision"`
	}
	if !payload(w, r, &in) {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	d, ok := s.projects[r.PathValue("project")]
	if !found(w, ok && d.Archived) || !revisionOK(w, d.Project.Revision, in.Revision) {
		return
	}
	for _, other := range s.projects {
		if !other.Archived && other.Project.Path == d.Project.Path {
			jsonFail(w, 409, "同一目录已被另一个活动项目使用")
			return
		}
	}
	d.Archived = false
	d.Project.bump()
	if s.moveLifecycle(w, d, false) {
		jsonReply(w, 200, s.projects[d.Project.ID].Project)
	}
}
