package research

import (
	"net/http"
	"slices"
	"strings"
)

type dashboardProjectFacts struct {
	NoteCount             int      `json:"noteCount"`
	GapCount              int      `json:"gapCount"`
	ArtifactKinds         []string `json:"artifactKinds"`
	UnsupportedClaimCount int      `json:"unsupportedClaimCount"`
}

func (s *Service) dashboardProjects(w http.ResponseWriter, r *http.Request) {
	projects := make(map[string]dashboardProjectFacts)
	s.mu.RLock()
	for id, project := range s.projects {
		if project.Archived || project.Trashed {
			continue
		}
		facts := dashboardProjectFacts{ArtifactKinds: []string{}}
		for _, note := range sortedNotes(project, false) {
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
		if len(project.Reviews) > 0 {
			for _, artifact := range graphArtifacts(project, s.visibleTasksLocked(id)) {
				if r.Context().Err() != nil {
					s.mu.RUnlock()
					return
				}
				for _, claim := range artifact.claimFindings("error", nil) {
					if claim.Line > 0 {
						facts.UnsupportedClaimCount++
					}
				}
			}
		}
		projects[id] = facts
	}
	s.mu.RUnlock()
	jsonReply(w, http.StatusOK, projects)
}

func dashboardNoteIsGap(note Note) bool {
	for _, part := range strings.Split(note.Namespace, "/") {
		if strings.EqualFold(part, "gap") || strings.EqualFold(part, "gaps") {
			return true
		}
	}
	for _, tag := range note.Tags {
		switch strings.ToLower(strings.TrimSpace(tag)) {
		case "gap", "research_gap":
			return true
		}
	}
	return false
}
