package research

import (
	"maps"
	"net/http"
	"slices"
	"strings"
)

type taskTagDefinition struct {
	Color     string `json:"color"`
	TextColor string `json:"textColor,omitempty"`
}

func (t taskTagDefinition) valid() bool {
	return tagColor.MatchString(t.Color) && (t.TextColor == "" || tagColor.MatchString(t.TextColor))
}

func (d workspaceTaskData) validTaskTags() bool {
	if d.TagRevision < 0 || (len(d.TagDefinitions) > 0 && d.TagRevision == 0) {
		return false
	}
	for name, definition := range d.TagDefinitions {
		if !label(name, 80) || name != strings.TrimSpace(name) || !definition.valid() {
			return false
		}
	}
	return true
}

type taskTag struct {
	Name       string             `json:"name"`
	Definition *taskTagDefinition `json:"definition,omitempty"`
	InUse      bool               `json:"inUse"`
}

type taskTagCatalog struct {
	Revision int       `json:"revision"`
	Tags     []taskTag `json:"tags"`
}

func (s *Service) taskTagCatalogLocked() taskTagCatalog {
	definitions := s.workspaceTasks.TagDefinitions
	tags := make(map[string]taskTag, len(definitions))
	for name, definition := range definitions {
		tags[name] = taskTag{Name: name, Definition: &definition}
	}
	for _, task := range s.visibleTasksLocked("") {
		for _, name := range task.Tags {
			tag := tags[name]
			tag.Name, tag.InUse = name, true
			tags[name] = tag
		}
	}
	catalog := taskTagCatalog{Revision: s.workspaceTasks.TagRevision, Tags: make([]taskTag, 0, len(tags))}
	for _, name := range slices.Sorted(maps.Keys(tags)) {
		catalog.Tags = append(catalog.Tags, tags[name])
	}
	return catalog
}

type taskTagEdit struct {
	Revision  *int   `json:"revision"`
	Operation string `json:"operation"`
	Name      string `json:"name"`
	taskTagDefinition
}

func (s *Service) taskTags(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodGet || r.Method == http.MethodHead {
		s.mu.RLock()
		defer s.mu.RUnlock()
		jsonReply(w, http.StatusOK, s.taskTagCatalogLocked())
		return
	}
	var edit taskTagEdit
	if !payload(w, r, &edit) {
		return
	}
	name := strings.TrimSpace(edit.Name)
	edit.Color = strings.ToUpper(strings.TrimSpace(edit.Color))
	edit.TextColor = strings.ToUpper(strings.TrimSpace(edit.TextColor))
	if !label(name, 80) || (edit.Operation == "set" && !edit.taskTagDefinition.valid()) {
		jsonFail(w, http.StatusBadRequest, "任务标签名称或颜色无效")
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	record := s.workspaceTasks
	if edit.Revision == nil {
		jsonFail(w, http.StatusPreconditionRequired, "请携带已读取的任务标签目录修订")
		return
	}
	if *edit.Revision != record.TagRevision {
		jsonFail(w, http.StatusConflict, "任务标签目录已更改，请重新打开")
		return
	}
	definitions := make(map[string]taskTagDefinition, len(record.TagDefinitions)+1)
	maps.Copy(definitions, record.TagDefinitions)
	switch edit.Operation {
	case "set":
		definitions[name] = edit.taskTagDefinition
	case "delete":
		if !found(w, record.TagDefinitions[name].Color != "") {
			return
		}
		// A task's tags are strings. Deleting a definition removes its custom
		// styling without rewriting task assignments or their revisions.
		delete(definitions, name)
	default:
		jsonFail(w, http.StatusBadRequest, "未知的任务标签操作")
		return
	}
	record.TagDefinitions = definitions
	record.TagRevision++
	if savedTaskData(w, s.commitWorkspaceTaskData(record)) {
		jsonReply(w, http.StatusOK, s.taskTagCatalogLocked())
	}
}
