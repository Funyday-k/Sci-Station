package research

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

type paperCollection struct {
	Name     string `json:"name"`
	ParentID string `json:"parent_id,omitempty"`
}

type paperTagDefinition struct {
	Color     string `json:"color"`
	TextColor string `json:"text_color,omitempty"`
}

type paperOrganization struct {
	Version     int                           `json:"version"`
	Revision    int                           `json:"revision"`
	Collections map[string]paperCollection    `json:"collections"`
	Tags        map[string]paperTagDefinition `json:"tags"`
	Library     *paperLibraryPreferences      `json:"library,omitempty"`
}

type paperLibraryPreferences struct {
	DefaultCollection string   `json:"default_collection,omitempty"`
	VisibleColumns    []string `json:"visible_columns"`
	SortColumn        string   `json:"sort_column,omitempty"`
	SortDescending    bool     `json:"sort_descending,omitempty"`
}

var libraryColumns = []string{"title", "authors", "year", "projects", "coreProjects", "collection",
	"publication", "itemType", "doi", "arxiv", "wiki", "tags", "status", "priority", "rating", "updated"}

var sortableLibraryColumns = []string{"title", "authors", "year", "status", "priority", "rating", "updated"}

func (o paperOrganization) validateLibraryPreferences(preferences paperLibraryPreferences) error {
	if preferences.DefaultCollection != "" {
		if _, exists := o.Collections[preferences.DefaultCollection]; !exists {
			return fmt.Errorf("%w：默认导入集合不存在", errInvalidPaper)
		}
	}
	if len(preferences.VisibleColumns) < 1 || len(preferences.VisibleColumns) > len(libraryColumns) {
		return fmt.Errorf("%w：至少保留一个文献列", errInvalidPaper)
	}
	seen := map[string]bool{}
	for _, column := range preferences.VisibleColumns {
		if seen[column] || !paperContains(libraryColumns, column) {
			return fmt.Errorf("%w：文献列无效", errInvalidPaper)
		}
		seen[column] = true
	}
	if preferences.SortColumn != "" && (!seen[preferences.SortColumn] || !paperContains(sortableLibraryColumns, preferences.SortColumn)) {
		return fmt.Errorf("%w：文献排序字段无效", errInvalidPaper)
	}
	return nil
}

// Expose association status without returning project note bodies.
func (s *Service) paperWikiStatus(w http.ResponseWriter, _ *http.Request) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	papers := map[string]bool{}
	for _, project := range s.projects {
		if project.Trashed || project.Archived {
			continue
		}
		for _, note := range project.Notes {
			if note.PaperID != "" && !note.Archived {
				papers[note.PaperID] = true
			}
		}
	}
	jsonReply(w, http.StatusOK, papers)
}

var tagColor = regexp.MustCompile(`^#[0-9a-fA-F]{6}$`)
var errPaperOrganizationConflict = errors.New("文献集合或标签已更新，请重新打开后保存")
var errUnreadablePaperOrganization = errors.New("无法读取文献集合与标签记录，请从备份恢复")

func (s *PaperLibrary) organizationPath() string {
	return filepath.Join(s.dir, "organization.json")
}

func (s *PaperLibrary) readOrganization() (paperOrganization, []byte, error) {
	var organization paperOrganization
	path := s.organizationPath()
	info, err := os.Lstat(path)
	if errors.Is(err, os.ErrNotExist) {
		return paperOrganization{
			Version:     1,
			Collections: map[string]paperCollection{},
			Tags:        map[string]paperTagDefinition{},
		}, nil, nil
	}
	if err != nil {
		return organization, nil, err
	}
	if !info.Mode().IsRegular() {
		return organization, nil, errUnreadablePaperOrganization
	}
	body, err := os.ReadFile(path)
	if err != nil {
		return organization, nil, err
	}
	if err = json.Unmarshal(body, &organization); err != nil ||
		organization.Version != 1 || organization.Revision < 1 ||
		organization.Collections == nil || organization.Tags == nil {
		return organization, nil, errUnreadablePaperOrganization
	}
	if err = organization.validate(); err != nil {
		return organization, nil, errUnreadablePaperOrganization
	}
	return organization, body, nil
}

func (o paperOrganization) validate() error {
	names := map[string]bool{}
	for id, item := range o.Collections {
		if !validID(id) || !collectionName(item.Name) {
			return errInvalidPaper
		}
		name := item.ParentID + "/" + strings.ToLower(item.Name)
		if names[name] {
			return errInvalidPaper
		}
		names[name] = true
		ancestors := map[string]bool{id: true}
		for parent := item.ParentID; parent != ""; parent = o.Collections[parent].ParentID {
			if _, exists := o.Collections[parent]; !exists || ancestors[parent] {
				return errInvalidPaper
			}
			ancestors[parent] = true
		}
	}
	for name, tag := range o.Tags {
		if !label(name, 128) || !tagColor.MatchString(tag.Color) ||
			(tag.TextColor != "" && !tagColor.MatchString(tag.TextColor)) {
			return errInvalidPaper
		}
	}
	if o.Library != nil {
		return o.validateLibraryPreferences(*o.Library)
	}
	return nil
}

func collectionName(name string) bool {
	return label(name, 128) && !strings.ContainsAny(name, "/\\") && name != "." && name != ".."
}

type paperOrganizationEdit struct {
	Revision     *int                     `json:"revision"`
	Operation    string                   `json:"operation"`
	CollectionID string                   `json:"collection_id"`
	ParentID     string                   `json:"parent_id"`
	Name         string                   `json:"name"`
	Color        string                   `json:"color"`
	TextColor    string                   `json:"text_color"`
	Library      *paperLibraryPreferences `json:"library"`
}

func (o *paperOrganization) nameCollection(id, parent, name string) error {
	if !collectionName(name) {
		return fmt.Errorf("%w：集合名称无效", errInvalidPaper)
	}
	if parent != "" {
		if _, exists := o.Collections[parent]; !exists {
			return fmt.Errorf("%w：上级集合不存在", errInvalidPaper)
		}
	}
	for otherID, other := range o.Collections {
		if otherID != id && other.ParentID == parent && strings.EqualFold(other.Name, name) {
			return fmt.Errorf("%w：该位置已有同名集合", errPaperOrganizationConflict)
		}
	}
	o.Collections[id] = paperCollection{Name: name, ParentID: parent}
	return nil
}

func (s *PaperLibrary) editOrganization(edit paperOrganizationEdit) (paperOrganization, error) {
	// Collection removal and paper assignment share the paper-record lock.
	// Renaming changes only this file and leaves all paper and PDF paths stable.
	lock, err := s.lockRecords()
	if err != nil {
		return paperOrganization{}, err
	}
	defer lock.Close()
	organization, disk, err := s.readOrganization()
	if err != nil {
		return paperOrganization{}, err
	}
	if edit.Revision == nil || *edit.Revision != organization.Revision {
		return paperOrganization{}, errPaperOrganizationConflict
	}
	before, err := json.Marshal(organization)
	if err != nil {
		return paperOrganization{}, err
	}
	name := strings.TrimSpace(edit.Name)
	switch edit.Operation {
	case "create_collection":
		err = organization.nameCollection(makeID(), edit.ParentID, name)
	case "rename_collection":
		item, exists := organization.Collections[edit.CollectionID]
		if !exists {
			return paperOrganization{}, os.ErrNotExist
		}
		err = organization.nameCollection(edit.CollectionID, item.ParentID, name)
	case "delete_collection":
		err = s.deletePaperCollection(&organization, edit.CollectionID)
	case "set_tag":
		if !label(name, 128) || !tagColor.MatchString(edit.Color) ||
			(edit.TextColor != "" && !tagColor.MatchString(edit.TextColor)) {
			return paperOrganization{}, fmt.Errorf("%w：标签名称或颜色无效", errInvalidPaper)
		}
		organization.Tags[name] = paperTagDefinition{Color: edit.Color, TextColor: edit.TextColor}
	case "delete_tag":
		if _, exists := organization.Tags[name]; !exists {
			return paperOrganization{}, os.ErrNotExist
		}
		delete(organization.Tags, name)
	case "set_library_preferences":
		if edit.Library == nil {
			return paperOrganization{}, errInvalidPaper
		}
		if err := organization.validateLibraryPreferences(*edit.Library); err != nil {
			return paperOrganization{}, err
		}
		organization.Library = edit.Library
	default:
		return paperOrganization{}, errInvalidPaper
	}
	if err != nil {
		return paperOrganization{}, err
	}
	organization.Revision++
	body, err := json.Marshal(organization)
	if err != nil {
		return paperOrganization{}, err
	}
	if disk != nil {
		body = mergeRecordFields(disk, before, body)
	}
	if err = atomicWrite(s.organizationPath(), body); err != nil {
		return paperOrganization{}, err
	}
	return organization, nil
}

func (s *PaperLibrary) deletePaperCollection(organization *paperOrganization, id string) error {
	if _, exists := organization.Collections[id]; !exists {
		return os.ErrNotExist
	}
	for _, item := range organization.Collections {
		if item.ParentID == id {
			return fmt.Errorf("%w：请先移出子集合", errInvalidPaper)
		}
	}
	dir := filepath.Join(s.dir, "records")
	entries, err := os.ReadDir(dir)
	if err != nil {
		return err
	}
	// Read committed records so a second library instance's recent assignment
	// cannot be overlooked by an older in-memory snapshot.
	for _, entry := range entries {
		paperID, record := strings.CutSuffix(entry.Name(), ".json")
		if !record {
			continue
		}
		if !validID(paperID) || !entry.Type().IsRegular() {
			return fmt.Errorf("无效的文献记录 %q", entry.Name())
		}
		body, err := os.ReadFile(filepath.Join(dir, entry.Name()))
		if err != nil {
			return err
		}
		paper, err := decodePaperRecord(paperID, body)
		if err != nil {
			return err
		}
		if paper.CollectionID == id {
			return fmt.Errorf("%w：请先移出集合中的文献", errInvalidPaper)
		}
	}
	delete(organization.Collections, id)
	if organization.Library != nil && organization.Library.DefaultCollection == id {
		organization.Library.DefaultCollection = ""
	}
	return nil
}

func (s *PaperLibrary) organizationHTTP(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case "GET":
		organization, _, err := s.readOrganization()
		if err != nil {
			paperError(w, err)
			return
		}
		paperReply(w, 200, organization)
	case "PATCH":
		var edit paperOrganizationEdit
		if !payload(w, r, &edit) {
			return
		}
		if edit.Revision == nil || *edit.Revision < 0 {
			paperError(w, fmt.Errorf("%w：缺少集合或标签版本", errInvalidPaper))
			return
		}
		organization, err := s.editOrganization(edit)
		if err != nil {
			paperError(w, err)
			return
		}
		paperReply(w, 200, organization)
	default:
		paperMethod(w, "GET, PATCH")
	}
}

func (s *PaperLibrary) libraryPapers(query url.Values) ([]Paper, error) {
	items := filterPapers(s.all(), query.Get("project"), query.Get("q"), query.Get("status"))
	collection := query.Get("collection")
	tag := query.Get("tag")
	selected := map[string]bool{}
	for _, id := range query["paper"] {
		if !validID(id) {
			return nil, errInvalidPaper
		}
		selected[id] = true
	}
	var collections map[string]paperCollection
	if collection != "" && collection != "unfiled" {
		organization, _, err := s.readOrganization()
		if err != nil {
			return nil, err
		}
		collections = organization.Collections
		if _, exists := collections[collection]; !exists {
			return nil, os.ErrNotExist
		}
	}
	out := items[:0]
	for _, item := range items {
		if (tag != "" && !paperContains(item.Tags, tag)) || (len(selected) > 0 && !selected[item.ID]) {
			continue
		}
		if collection == "unfiled" && item.CollectionID != "" {
			continue
		}
		if collections != nil {
			id := item.CollectionID
			for id != "" && id != collection {
				id = collections[id].ParentID
			}
			if id != collection {
				continue
			}
		}
		out = append(out, item)
	}
	return out, nil
}
