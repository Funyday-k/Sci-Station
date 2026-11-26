package desktop

import (
	"context"
	"errors"
	"net/http"
	"os"
	"slices"
	"time"

	"scistation.local/desktop/internal/meeting"
	"scistation.local/desktop/internal/research"
)

func (a *apiServer) serveResearchDashboard(w http.ResponseWriter, r *http.Request) {
	lab, ok := a.research.(*research.Service)
	if !ok || a.meetings == nil {
		a.research.ServeHTTP(w, r)
		return
	}
	lab.ServeDashboardProjects(w, r, func(ctx context.Context, projects map[string]struct{}) (map[string]research.DashboardPublishedResearch, error) {
		return a.publishedDashboardResearch(ctx, lab, projects)
	})
}

func (a *apiServer) publishedDashboardResearch(ctx context.Context, lab *research.Service, projects map[string]struct{}) (map[string]research.DashboardPublishedResearch, error) {
	enabled := make(map[string]bool, len(projects))
	for project := range projects {
		allowed, err := lab.ModuleEnabled(project, "ai-lab")
		if err == nil && allowed {
			enabled[project] = true
		}
	}
	results := make(map[string]research.DashboardPublishedResearch)
	if len(enabled) == 0 {
		return results, nil
	}
	sessions, err := a.meetings.List()
	if err != nil {
		return nil, err
	}
	for _, summary := range sessions {
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		if !enabled[summary.ProjectID] || summary.RoundCount == 0 || len(summary.Seats) != 1 {
			continue
		}
		formal := meeting.ResearchWorkflow(summary.Topic) != ""
		if !formal && !summary.HasResearchCitations {
			continue
		}

		room, err := a.meetings.LabRunSession(meeting.LabScope{ProjectID: summary.ProjectID}, summary.ID)
		if err != nil {
			if errors.Is(err, os.ErrNotExist) {
				continue
			}
			return nil, err
		}
		if room.ProjectID != summary.ProjectID {
			continue
		}
		project := results[room.ProjectID]
		if err := addPublishedDashboardClaims(ctx, room, &project); err != nil {
			return nil, err
		}
		results[room.ProjectID] = project
	}
	return results, nil
}

func addPublishedDashboardClaims(ctx context.Context, room *meeting.Session, project *research.DashboardPublishedResearch) error {
	formal := formalLabWorkflow(room) != ""
	for round, turn := range publishedRoomTurns(room) {
		if err := ctx.Err(); err != nil {
			return err
		}
		output := roomTurnOutput(round.Number, turn.Seat)
		sources := labRecordedReferences(room, round.Number, output)
		// An ordinary discussion only enters the check when the round had
		// project sources. The formal workflow also requires citations for
		// core sections when no supporting source was attached.
		if !formal && !slices.ContainsFunc(sources, func(ref labEvidenceReference) bool {
			return ref.Evidence != nil
		}) {
			continue
		}
		at := turn.FinishedAt
		if at == "" {
			at = round.CreatedAt
		}
		if completed, err := time.Parse(time.RFC3339Nano, at); err == nil && completed.After(project.Latest) {
			project.Latest = completed
		}

		claims, _ := labClaims(turn.Text)
		refs := labReferenceIndex(sources)
		for _, claim := range claims {
			if !publishedClaimMissingEvidence(claim, refs, formal) {
				continue
			}
			if project.Claims == nil {
				project.Claims = make(map[research.DashboardClaimKey]struct{})
			}
			key := research.DashboardClaimKey{MeetingID: room.ID, OutputID: output, Digest: claim.Digest}
			project.Claims[key] = struct{}{}
		}
	}
	return nil
}

func publishedClaimMissingEvidence(claim labClaim, refs map[string]labEvidenceReference, formal bool) bool {
	if len(claim.References) == 0 {
		return formal && claim.Core
	}
	// Compare with the immutable attachments the turn could cite. Current
	// source edits are a separate freshness finding in live evidence checks.
	return !slices.ContainsFunc(claim.References, func(id string) bool {
		ref := refs[id]
		return ref.Status == "recorded" && ref.Evidence != nil
	})
}
