package meeting

import (
	"encoding/json"
	"strings"
	"unicode/utf8"
)

const agendaUpdateInstructions = `Maintain the working agenda as the discussion evolves. Compare the host's latest_instruction and evidence in visible public statements against active_agenda and open_agenda. When new information materially changes what needs examining or delivering, return the appropriate additions or revisions WITH your public say. For example: {"action":"say","text":"…","agenda_updates":[{"op":"add","title":"a concrete uncovered question","kind":"discussion","reason":"the new host constraint or public finding that requires it"},{"op":"revise","item_id":"existing item id","title":"the more precise scope of that same issue","reason":"what changed and why"}]}. Use up to three justified changes. Keep the host's wording and intent where possible, group duplicates, and leave unrelated and completed items alone. Omit agenda_updates when nothing material changed. Never mark tasks done, select the next task, or turn discussion into authorized implementation. Explain the underlying finding in your public text. On a closing round use followups for new next steps, without duplicating them in agenda_updates.`

type AgendaRevision struct {
	Round         int    `json:"round"`
	Seat          string `json:"seat"`
	PreviousTitle string `json:"previous_title"`
	PreviousKind  string `json:"previous_kind"`
	Reason        string `json:"reason"`
}

type agendaProposal struct {
	AgendaInput
	Op     string `json:"op"`
	ItemID string `json:"item_id,omitempty"`
	Reason string `json:"reason"`
	// These values are captured by the engine, never supplied by the speaker.
	BaseVersion   int    `json:"base_version,omitempty"`
	PreviousTitle string `json:"previous_title,omitempty"`
	PreviousKind  string `json:"previous_kind,omitempty"`
}

func parseAgendaUpdates(s *Session, raw json.RawMessage) []agendaProposal {
	var encoded []json.RawMessage
	if json.Unmarshal(raw, &encoded) != nil {
		return nil
	}
	var proposals []agendaProposal
	for _, value := range encoded {
		var p agendaProposal
		if json.Unmarshal(value, &p) != nil {
			continue
		}
		p.Reason = strings.Join(strings.Fields(p.Reason), " ")
		if p.Reason == "" || utf8.RuneCountInString(p.Reason) > 320 {
			continue
		}
		p.BaseVersion, p.PreviousTitle, p.PreviousKind = 0, "", ""
		fallback := defaultKind(s.Preset)
		switch p.Op {
		case "add":
			if p.ItemID != "" {
				continue
			}
		case "revise":
			item := s.findAgenda(p.ItemID)
			if item == nil || item.Status != "pending" {
				continue
			}
			p.BaseVersion, p.PreviousTitle, p.PreviousKind = item.Version, item.Title, item.Kind
			fallback = item.Kind
			if item.ID == s.ActiveAgendaID && item.Kind == "discussion" && p.Kind == "implementation" {
				p.Kind = item.Kind
			}
		default:
			continue
		}
		clean, err := cleanAgendaInput(p.AgendaInput, fallback)
		if err != nil {
			continue
		}
		if strings.EqualFold(clean.Title, p.PreviousTitle) && clean.Kind == p.PreviousKind {
			continue
		}
		duplicate := false
		for _, item := range s.Agenda {
			if item.ID != p.ItemID && strings.EqualFold(clean.Title, item.Title) {
				duplicate = true
				break
			}
		}
		for _, prev := range proposals {
			if strings.EqualFold(prev.Title, clean.Title) || (p.ItemID != "" && prev.ItemID == p.ItemID) {
				duplicate = true
				break
			}
		}
		if duplicate {
			continue
		}
		p.AgendaInput = clean
		proposals = append(proposals, p)
		if len(proposals) == 3 {
			break
		}
	}
	return proposals
}

// Every seat sees the round's original agenda. Applying in speaking order
// after successful closure preserves blind submissions and rejects stale
// competing revisions without changing a human-selected task or its status.
func applyRoundAgendaUpdates(s *Session, r *Round) {
	for _, t := range r.Turns {
		if t.Status != "done" {
			continue
		}
		for _, p := range t.ProposedAgendaUpdates {
			if p.Op == "add" {
				item := AgendaItem{AgendaInput: p.AgendaInput, Source: "discussion", SourceRound: r.Number, SourceSeat: t.Seat, Reason: p.Reason}
				if len(s.Agenda) == 0 && s.Preset != "work" && s.Preset != "" {
					item.Kind = "discussion"
				}
				if err := s.appendAgenda(item); err == nil {
					if len(s.Agenda) == 1 {
						s.ActiveAgendaID = s.Agenda[0].ID
					}
					addEvent(s, "agenda_suggested", t.Seat, item.Title)
				}
				continue
			}
			item := s.findAgenda(p.ItemID)
			if p.Op != "revise" || item == nil || item.Status != "pending" {
				continue
			}
			if item.Version != p.BaseVersion || item.Title != p.PreviousTitle || item.Kind != p.PreviousKind {
				// A same-round winner has already updated this item. Keep the
				// losing valid proposal available for an explicit host decision.
				competed := false
				for i := len(item.Revisions) - 1; i >= 0; i-- {
					if item.Revisions[i].Round != r.Number {
						break
					}
					if item.Revisions[i].PreviousTitle == p.PreviousTitle && item.Revisions[i].PreviousKind == p.PreviousKind {
						competed = true
						break
					}
				}
				if competed {
					item.Candidates = append(item.Candidates, AgendaCandidate{
						ID: newID(), AgendaInput: p.AgendaInput, Round: r.Number, Seat: t.Seat,
						Reason: p.Reason, PreviousTitle: p.PreviousTitle, PreviousKind: p.PreviousKind,
					})
					addEvent(s, "agenda_revision_candidate", t.Seat, item.Title)
				}
				continue
			}
			conflict := false
			for _, other := range s.Agenda {
				if item.ID != other.ID && strings.EqualFold(p.Title, other.Title) {
					conflict = true
					break
				}
			}
			if conflict {
				continue
			}
			item.Revisions = append(item.Revisions, AgendaRevision{r.Number, t.Seat, item.Title, item.Kind, p.Reason})
			item.AgendaInput = p.AgendaInput
			item.EditedBy = t.Seat
			s.Board.revealPreset("agenda")
			item.Version++
			addEvent(s, "agenda_revised", t.Seat, item.Title)
		}
	}
}
