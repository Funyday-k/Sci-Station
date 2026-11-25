package research

import (
	"net/http"
	"slices"
	"strings"
)

type dashboardProjectFacts struct {
	NoteCount     int      `json:"noteCount"`
	GapCount      int      `json:"gapCount"`
	ArtifactKinds []string `json:"artifactKinds"`
}

func (s *Service) dashboardProjects(w http.ResponseWriter, _ *http.Request) {
	projects := make(map[string]dashboardProjectFacts)
	s.mu.RLock()
	for id, project := range s.projects {
		if project.Archived {
			continue
		}
		facts := dashboardProjectFacts{ArtifactKinds: []string{}}
		for _, note := range project.Notes {
			facts.NoteCount++
			if dashboardNoteIsGap(note) {
				facts.GapCount++
			}
			for _, tag := range note.Tags {
				kind := strings.ToLower(strings.TrimSpace(tag))
				switch kind {
				case "research_plan", "related_work", "writing_revision", "reviewer_response":
					if !slices.Contains(facts.ArtifactKinds, kind) {
						facts.ArtifactKinds = append(facts.ArtifactKinds, kind)
					}
				}
			}
		}
		slices.Sort(facts.ArtifactKinds)
		projects[id] = facts
	}
	s.mu.RUnlock()
	jsonReply(w, http.StatusOK, projects)
}

func dashboardNoteIsGap(note Note) bool {
	for _, tag := range note.Tags {
		switch strings.ToLower(strings.TrimSpace(tag)) {
		case "gap", "research_gap":
			return true
		}
	}
	return false
}
