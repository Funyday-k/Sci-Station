package research

import (
	"context"
	"net/http"
	"slices"
	"strings"
	"time"
)

type dashboardProjectFacts struct {
	NoteCount             int      `json:"noteCount"`
	GapCount              int      `json:"gapCount"`
	ArtifactKinds         []string `json:"artifactKinds"`
	UnsupportedClaimCount int      `json:"unsupportedClaimCount"`
	LastResearchActivity  string   `json:"lastResearchActivity,omitempty"`
}

type DashboardClaimKey struct {
	MeetingID string
	OutputID  string
	Digest    [32]byte
}

type DashboardPublishedResearch struct {
	Claims map[DashboardClaimKey]struct{}
	Latest time.Time
}

// ServeDashboardProjects combines active project facts with the published
// research outputs selected by the host. Claim identities never leave the host.
func (s *Service) ServeDashboardProjects(w http.ResponseWriter, r *http.Request,
	published func(context.Context, map[string]struct{}) (map[string]DashboardPublishedResearch, error),
) {
	projectScope := r.URL.Query().Get("project")
	projects := make(map[string]dashboardProjectFacts)
	eligible := make(map[string]struct{})
	claims := make(map[string]map[DashboardClaimKey]struct{})
	s.mu.RLock()
	for id, project := range s.projects {
		if project.Archived || project.Trashed || (projectScope != "" && id != projectScope) {
			continue
		}
		eligible[id] = struct{}{}
		claims[id] = make(map[DashboardClaimKey]struct{})
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
						key := DashboardClaimKey{MeetingID: artifact.review.MeetingID, OutputID: artifact.review.TurnID, Digest: claim.digest}
						claims[id][key] = struct{}{}
					}
				}
			}
		}
		projects[id] = facts
	}
	s.mu.RUnlock()
	if projectScope != "" && len(projects) == 0 {
		jsonFail(w, http.StatusNotFound, "未找到此科研项目")
		return
	}
	var fromDiscussion map[string]DashboardPublishedResearch
	if published != nil && len(projects) > 0 {
		var err error
		fromDiscussion, err = published(r.Context(), eligible)
		if r.Context().Err() != nil {
			return
		}
		if err != nil {
			jsonFail(w, http.StatusInternalServerError, "无法读取已公开的研究记录")
			return
		}
	}
	for id, facts := range projects {
		publishedFacts := fromDiscussion[id]
		for key := range publishedFacts.Claims {
			claims[id][key] = struct{}{}
		}
		facts.UnsupportedClaimCount = len(claims[id])
		if !publishedFacts.Latest.IsZero() {
			facts.LastResearchActivity = publishedFacts.Latest.UTC().Format(time.RFC3339Nano)
		}
		projects[id] = facts
	}
	w.Header().Set("Cache-Control", "no-store")
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
