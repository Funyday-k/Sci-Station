package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"

	"scistation.local/desktop/internal/meeting"
	"scistation.local/desktop/internal/research"
)

const paperExcerptMarker = "Sci-Station · 论文原文摘录 v1\n"

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
	for i, round := range s.Rounds {
		if i == len(s.Rounds)-1 && s.Status == "running" {
			break
		}
		for _, turn := range round.Turns {
			if key == fmt.Sprintf("round-%d-%s", round.Number, turn.Seat) && turn.Status == "done" && turn.Error == "" && strings.TrimSpace(turn.Text) != "" {
				return turn.Text, round.Number, nil
			}
		}
	}
	return "", 0, errors.New("所选会议输出尚未公开，或已不存在")
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
		text, isPaper := strings.CutPrefix(m.Excerpt, paperExcerptMarker)
		if !isPaper || m.AddedRound > round || seen[text] {
			continue
		}
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
		if !ok || json.Unmarshal([]byte(meta), &loc) != nil || loc.ProjectID != s.ProjectID || loc.Page < 1 || loc.PaperID == "" || loc.Fingerprint == "" || strings.TrimSpace(quote) == "" {
			return source, errors.New("会议中存在不完整或不属于此项目的论文证据")
		}
		source.Evidence = append(source.Evidence, research.Evidence{PaperID: loc.PaperID, Page: loc.Page, SourceHash: loc.Fingerprint, Quote: quote, MeetingID: s.ID, TurnID: key, AnnotationID: loc.AnnotationID, SelectionStart: loc.SelectionStart, SelectionEnd: loc.SelectionEnd, OCR: loc.OCR})
		seen[text] = true
	}
	return source, nil
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
		lab.ServeMeetingReview(w, r, s.ProjectID, s.ID, command, func(key string) (research.ReviewSource, error) { return recordedReviewSource(s, key) })
	})
	if err != nil {
		fail(w, err)
	}
}
