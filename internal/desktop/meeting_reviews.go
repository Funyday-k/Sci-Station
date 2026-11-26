package desktop

import (
	"encoding/json"
	"errors"
	"fmt"
	"iter"
	"net/http"
	"strings"
	"unicode/utf8"

	"scistation.local/desktop/internal/meeting"
	"scistation.local/desktop/internal/research"
)

// Review the selected public output, excluding a round until publication has
// completed. Material.AddedRound excludes sources introduced after that turn.
func meetingOutput(s *meeting.Session, key string) (string, int, error) {
	if key == "report" && s.Report != nil && s.Report.Status == "ready" && strings.TrimSpace(s.Report.Markdown) != "" {
		return s.Report.Markdown, len(s.Rounds), nil
	}
	for _, item := range s.Agenda {
		if key == "agenda-"+item.ID && strings.TrimSpace(item.Title) != "" {
			text := item.Title
			if item.Reason != "" {
				text += "\n\n" + item.Reason
			}
			return text, item.SourceRound, nil
		}
	}
	for round, turn := range publishedRoomTurns(s) {
		if key == roomTurnOutput(round.Number, turn.Seat) {
			return turn.Text, round.Number, nil
		}
	}
	return "", 0, errors.New("所选会议输出尚未公开，或已不存在")
}

func roomTurnOutput(round int, seat string) string {
	return fmt.Sprintf("round-%d-%s", round, seat)
}

func publishedRoomTurns(room *meeting.Session) iter.Seq2[meeting.Round, meeting.Turn] {
	return func(yield func(meeting.Round, meeting.Turn) bool) {
		for i, round := range room.Rounds {
			if i == len(room.Rounds)-1 && room.Status == "running" {
				return
			}
			for _, turn := range round.Turns {
				if turn.Status == "done" && turn.Error == "" && strings.TrimSpace(turn.Text) != "" && !yield(round, turn) {
					return
				}
			}
		}
	}
}

func recordedReviewSource(s *meeting.Session, key string) (research.ReviewSource, error) {
	source := research.ReviewSource{Evidence: []research.Evidence{}}
	body, round, err := meetingOutput(s, key)
	if err != nil {
		return source, err
	}
	source.Text = body
	seen := map[string]bool{}
	for _, m := range s.Materials {
		if m.AddedRound > round || seen[m.Excerpt] {
			continue
		}
		if text, ok := strings.CutPrefix(m.Excerpt, meeting.ProjectExcerptMarker); ok {
			evidence, err := recordedProjectEvidence(text, s.ProjectID)
			if err != nil {
				return source, err
			}
			evidence.MeetingID, evidence.TurnID = s.ID, key
			source.Evidence = append(source.Evidence, evidence)
			seen[m.Excerpt] = true
			continue
		}
		text, isPaper := strings.CutPrefix(m.Excerpt, meeting.PaperExcerptMarker)
		if !isPaper {
			continue
		}
		evidence, err := recordedPaperEvidence(text, s.ProjectID)
		if err != nil {
			return source, err
		}
		evidence.MeetingID, evidence.TurnID = s.ID, key
		source.Evidence = append(source.Evidence, evidence)
		seen[m.Excerpt] = true
	}
	return source, nil
}

func recordedPaperEvidence(text, project string) (research.Evidence, error) {
	var loc struct {
		ProjectID      string `json:"projectId"`
		PaperID        string `json:"paperId"`
		Page           int    `json:"page"`
		Fingerprint    string `json:"fingerprint"`
		AnnotationID   string `json:"annotationId"`
		SelectionStart *int   `json:"selectionStart"`
		SelectionEnd   *int   `json:"selectionEnd"`
		OCR            bool   `json:"ocr"`
	}
	meta, quote, ok := strings.Cut(text, "\n\n")
	if !ok || json.Unmarshal([]byte(meta), &loc) != nil || loc.ProjectID != project || loc.Page < 1 || loc.PaperID == "" || loc.Fingerprint == "" || strings.TrimSpace(quote) == "" {
		return research.Evidence{}, errors.New("会议中存在不完整或不属于此项目的论文证据")
	}
	return research.Evidence{PaperID: loc.PaperID, Page: loc.Page, SourceHash: loc.Fingerprint, Quote: quote,
		AnnotationID: loc.AnnotationID, SelectionStart: loc.SelectionStart, SelectionEnd: loc.SelectionEnd, OCR: loc.OCR}, nil
}

func recordedProjectEvidence(text, project string) (research.Evidence, error) {
	var anchor struct {
		ProjectID string `json:"projectId"`
		Kind      string `json:"kind"`
		ID        string `json:"id"`
		Hash      string `json:"sha256"`
		Offset    *int   `json:"offset"`
		End       *int   `json:"end"`
	}
	meta, quote, ok := strings.Cut(text, "\n\n")
	length := utf8.RuneCountInString(quote)
	if !ok || json.Unmarshal([]byte(meta), &anchor) != nil || anchor.ProjectID != project ||
		anchor.Kind != "note" && anchor.Kind != "material" && anchor.Kind != "paper-markdown" || anchor.ID == "" || len(anchor.Hash) != 64 ||
		anchor.Offset == nil || *anchor.Offset < 0 || length == 0 || length > 1000 || strings.TrimSpace(quote) == "" {
		return research.Evidence{}, errors.New("会议中存在不完整或不属于此项目的 Wiki／材料证据")
	}
	loc := research.ProjectEvidenceLocation{ProjectID: anchor.ProjectID, Kind: anchor.Kind, ID: anchor.ID,
		Offset: *anchor.Offset, End: *anchor.Offset + length}
	if loc.End <= loc.Offset || anchor.End != nil && *anchor.End != loc.End {
		return research.Evidence{}, errors.New("项目原文选段范围与已记录文本不一致")
	}
	return research.Evidence{Source: &loc, SourceHash: anchor.Hash, Quote: quote}, nil
}

func (a *apiServer) meetingReviews(w http.ResponseWriter, r *http.Request, id string) {
	lab, ok := a.research.(*research.Service)
	if !ok || a.meetings == nil {
		reject(w, 503, "科研或会议服务不可用")
		return
	}
	if r.Method != http.MethodPost {
		reject(w, 405, "请提交审核决定")
		return
	}
	var command research.ReviewRequest
	if !jsonBody(w, r, &command) {
		return
	}
	err := a.meetings.WithReviewSession(id, func(s *meeting.Session) {
		if s.ProjectID == "" {
			reject(w, 403, "此会议没有绑定科研项目")
			return
		}
		lab.ServeMeetingReview(w, r, s.ProjectID, s.ID, command, func(key string) (research.ReviewSource, error) { return labReviewSource(s, key) })
	})
	if err != nil {
		fail(w, err)
	}
}
