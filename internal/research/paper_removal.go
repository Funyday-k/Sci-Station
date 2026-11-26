package research

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"maps"
	"net/http"
	"slices"
)

type paperRemovalProject struct {
	ID                string `json:"id"`
	Name              string `json:"name"`
	Archived          bool   `json:"archived"`
	Trashed           bool   `json:"trashed"`
	Member            bool   `json:"member"`
	WikiPages         int    `json:"wikiPages"`
	ArchivedWikiPages int    `json:"archivedWikiPages"`
}

type paperRemovalImpact struct {
	Title          string                `json:"title"`
	Revision       int                   `json:"revision"`
	HasPDF         bool                  `json:"hasPDF"`
	HasMarkdown    bool                  `json:"hasMarkdown"`
	Annotations    int                   `json:"annotations"`
	RelatedTasks   int                   `json:"relatedTasks"`
	ProjectIDs     []string              `json:"projectIds"`
	CoreProjectIDs []string              `json:"coreProjectIds"`
	Projects       []paperRemovalProject `json:"projects"`
	Confirmation   string                `json:"confirmation,omitempty"`
}

func evidenceUsesPaper(evidence []Evidence, id string) bool {
	return slices.ContainsFunc(evidence, func(e Evidence) bool {
		return e.PaperID == id || (e.Source != nil && e.Source.Kind == "paper-markdown" && e.Source.ID == id)
	})
}

// The caller holds the service lock so the preview represents one set of references.
func (s *Service) paperRemovalImpact(p Paper) paperRemovalImpact {
	impact := paperRemovalImpact{
		Title: p.Title, Revision: p.Revision, HasPDF: p.HasPDF, HasMarkdown: p.Markdown != nil,
		Annotations: len(p.Annotations), ProjectIDs: p.ProjectIDs, CoreProjectIDs: p.CoreProjectIDs,
		Projects: []paperRemovalProject{},
	}
	projects := map[string]paperRemovalProject{}
	for _, id := range p.ProjectIDs {
		projects[id] = paperRemovalProject{ID: id, Member: true}
	}
	tasks := map[string]bool{}
	countTasks := func(records map[string]Task) {
		for _, task := range records {
			if task.PaperID == p.ID || slices.Contains(task.RelatedPaperIDs, p.ID) || evidenceUsesPaper(task.Evidence, p.ID) {
				tasks[task.ID] = true
			}
		}
	}
	countTasks(s.workspaceTasks.Tasks)
	for id, d := range s.projects {
		item := projects[id]
		for _, note := range d.Notes {
			if note.PaperID == p.ID || evidenceUsesPaper(note.Evidence, p.ID) {
				if note.Archived {
					item.ArchivedWikiPages++
				} else {
					item.WikiPages++
				}
			}
		}
		if item.Member || item.WikiPages > 0 || item.ArchivedWikiPages > 0 {
			item.ID, item.Name, item.Archived, item.Trashed = id, d.Project.Name, d.Archived, d.Trashed
			projects[id] = item
		}
		countTasks(d.Tasks)
	}
	for _, id := range slices.Sorted(maps.Keys(projects)) {
		impact.Projects = append(impact.Projects, projects[id])
	}
	impact.RelatedTasks = len(tasks)
	encoded, _ := json.Marshal(impact)
	digest := sha256.Sum256(append([]byte(p.ID), encoded...))
	impact.Confirmation = hex.EncodeToString(digest[:])
	return impact
}

func (s *Service) paperRemoval(w http.ResponseWriter, r *http.Request) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	p, ok := s.papers.Snapshot(r.PathValue("paper"))
	if !found(w, ok) {
		return
	}
	impact := s.paperRemovalImpact(p)
	if r.Method == http.MethodDelete {
		query := r.URL.Query()
		if queryRevision(query) != p.Revision || query.Get("confirmation") != impact.Confirmation {
			jsonFail(w, http.StatusConflict, "文献或引用范围已变化，请重新打开确认并核对影响")
			return
		}
		if err := s.papers.remove(p.ID, p.Revision); err != nil {
			paperError(w, err)
			return
		}
		w.WriteHeader(http.StatusNoContent)
		return
	}
	jsonReply(w, http.StatusOK, impact)
}
