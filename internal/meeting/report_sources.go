package meeting

import (
	"fmt"
	"regexp"
	"strings"
	"unicode/utf8"

	"scistation.local/desktop/internal/workspace"
)

// The report transport receives only this projection. In particular, a Turn,
// Operation or Change must never be serialized into a report model prompt.
type reportSource struct {
	original  string
	seatLabel string
	Tail      string            `json:"closing_excerpt,omitempty"`
	Partial   bool              `json:"excerpted,omitempty"`
	ID        string            `json:"id"`
	Kind      string            `json:"kind"`
	Text      string            `json:"text"`
	Round     int               `json:"round,omitempty"`
	Seat      string            `json:"seat,omitempty"`
	SeatID    string            `json:"seat_id,omitempty"`
	Model     string            `json:"model,omitempty"`
	Status    string            `json:"status,omitempty"`
	Before    string            `json:"before,omitempty"`
	After     string            `json:"after,omitempty"`
	TargetID  string            `json:"target_id,omitempty"`
	Target    string            `json:"target,omitempty"`
	Points    []DiscussionPoint `json:"points,omitempty"`
	Positions []Position        `json:"positions,omitempty"`
}

type reportMaterial struct {
	Names         map[string]string `json:"-"`
	ChangedModels map[string]bool   `json:"-"`
	Coverage      string            `json:"coverage,omitempty"`
	BoardScope    string            `json:"board_notes_scope,omitempty"`
	Topic         string            `json:"topic"`
	Seats         []string          `json:"seats"`
	Sources       []reportSource    `json:"sources"`
}

func reportMaterials(s *Session) reportMaterial {
	m := reportMaterial{Topic: s.Topic, Seats: append([]string(nil), s.Seats...), Names: s.SeatNames(), ChangedModels: map[string]bool{}}
	lastModels := map[string]string{}
	for _, seat := range s.Seats {
		if member := s.memberForSeat(seat); member != nil {
			lastModels[seat] = member.Model
			if member.ModelEpoch > 0 {
				m.ChangedModels[seat] = true
			}
		}
	}
	for i, a := range s.Agenda {
		editor, round := a.EditedBy, a.SourceRound
		if n := len(a.Revisions); n > 0 {
			revision := a.Revisions[n-1]
			round = revision.Round
			if editor == "" {
				editor = revision.Seat
			}
		}
		if editor == "" {
			editor = a.SourceSeat
			if editor == "" && a.Source == "host" {
				editor = "user"
			}
		}
		label := s.HistoricalSeatName(editor, "", "", m.Names)
		model := ""
		for _, r := range s.Rounds {
			if r.Number != round {
				continue
			}
			for _, t := range r.Turns {
				if t.Seat == editor {
					model = r.RecordedTurnModel(t)
					label = s.HistoricalSeatName(editor, model, t.ModelLabel, m.Names)
					break
				}
			}
			break
		}
		m.Sources = append(m.Sources, reportSource{ID: fmt.Sprintf("A%d", i+1), Kind: "agenda", Text: a.Title, Status: a.Status, Round: round, Seat: editor, Model: model, seatLabel: label})
	}
	pointSources := map[string]string{}
	fileCount := 0
	addChange := func(c workspace.Change, round int, seat, model, label string) {
		fileCount++
		m.Sources = append(m.Sources, reportSource{ID: fmt.Sprintf("F%d", fileCount), Kind: "file", Text: c.Path, Before: c.Before, After: c.After, Round: round, Seat: seat, Model: model, seatLabel: label})
	}
	for _, r := range s.Rounds {
		if !r.Auto && strings.TrimSpace(r.Note) != "" {
			m.Sources = append(m.Sources, reportSource{ID: fmt.Sprintf("H%d", r.Number), Kind: "host", Text: r.Note, Round: r.Number, Seat: "user"})
		}
		for j, t := range r.Turns {
			model := r.RecordedTurnModel(t)
			if catalogModel := r.catalogTurnModel(t); catalogModel != "" {
				if last := lastModels[t.Seat]; last != "" && last != catalogModel {
					m.ChangedModels[t.Seat] = true
				}
				lastModels[t.Seat] = catalogModel
			}
			label := s.HistoricalSeatName(t.Seat, model, t.ModelLabel, m.Names)
			if t.Status == "done" && strings.TrimSpace(t.Text) != "" {
				sourceID := fmt.Sprintf("R%d-T%d", r.Number, j+1)
				m.Sources = append(m.Sources, reportSource{ID: sourceID, Kind: "public", Text: t.Text, Round: r.Number, Seat: t.Seat, Model: model, seatLabel: label, Points: append([]DiscussionPoint(nil), t.Points...), Positions: append([]Position(nil), t.Positions...)})
				for _, point := range t.Points {
					pointSources[point.ID] = sourceID
				}
			}
			for _, c := range t.Changes {
				addChange(c, r.Number, t.Seat, model, label)
			}
		}
	}
	// Old host saves need not have a matching write-ahead entry.
	hostRounds := map[reportFileVersionKey][]int{}
	for _, op := range s.Operations {
		if op.Seat == "user" && op.Status == "applied" && op.Change != nil {
			c := op.Change
			k := reportFileVersionKey{c.Path, c.Before, c.After}
			hostRounds[k] = append(hostRounds[k], op.Round)
		}
	}
	for _, u := range s.UserChanges {
		c := u.Change
		k := reportFileVersionKey{c.Path, c.Before, c.After}
		round := 0
		if found := hostRounds[k]; len(found) > 0 {
			round, hostRounds[k] = found[0], found[1:]
		}
		addChange(c, round, "user", "", "")
	}
	m.addBoardNotes(s, pointSources)
	return m
}

const maxReportBoardNotes = 12

func (m *reportMaterial) addBoardNotes(s *Session, pointSources map[string]string) {
	view := currentBoardPrompt(s, 0)
	included, total := 0, view.AnnotationsOmitted
	add := func(id, target, text string, source BoardSource) {
		if source.SourceSeat != "user" || strings.TrimSpace(text) == "" {
			return
		}
		total++
		if included >= maxReportBoardNotes {
			return
		}
		included++
		m.Sources = append(m.Sources, reportSource{ID: fmt.Sprintf("B%d", included), Kind: "host_board", Text: text, Seat: source.SourceSeat, Round: source.SourceRound, TargetID: id, Target: target})
	}
	for _, module := range view.Board.Modules {
		add(module.ID, module.Title, module.Body, module.BoardSource)
	}
	for _, id := range view.AnnotationIDs {
		if annotation, ok := view.Board.PointAnnotations[id]; ok {
			target := pointSources[id]
			if target == "" {
				target = id
			}
			add(id, "观点 · "+target, annotation.Body, annotation.BoardSource)
		} else if annotation, ok := view.Board.MaterialAnnotations[id]; ok {
			add(id, "材料 · "+view.Targets.Materials[id], annotation.Body, annotation.BoardSource)
		}
	}
	if included > 0 {
		m.BoardScope = fmt.Sprintf("收录议题板当前保存的 %d 条主持人笔记或批注，共 %d 条。", included, total)
	}
}

type reportFileVersionKey struct{ path, before, after string }

type reportEvidence struct {
	ID    string `json:"id"`
	Quote string `json:"quote"`
}

type reportParagraph struct {
	Text     string           `json:"text"`
	Evidence []reportEvidence `json:"evidence"`
}

type reportBody struct {
	Outcome []reportParagraph `json:"outcome"`
	Reasons []reportParagraph `json:"reasons"`
	Open    []reportParagraph `json:"open"`
	Next    []reportParagraph `json:"next"`
}

func (b reportBody) sections() []struct {
	title      string
	paragraphs []reportParagraph
} {
	return []struct {
		title      string
		paragraphs []reportParagraph
	}{
		{"会议结果", b.Outcome}, {"主要依据", b.Reasons}, {"分歧与待定事项", b.Open}, {"后续行动", b.Next},
	}
}

var reportRef = regexp.MustCompile(`(?i)\[(R[0-9]+[^\]\r\n]*|[ABHF][0-9]+)\]`)

// A model may naturally repeat an inline source mark or wrap its prose.
// Validate each mark before removing it; the renderer emits the verified IDs.
func reportProse(text string, evidence []reportEvidence, material reportMaterial, limit int) (string, error) {
	for _, match := range reportRef.FindAllStringSubmatch(text, -1) {
		token := strings.TrimSpace(match[1])
		found := false
		for _, ref := range evidence {
			if strings.EqualFold(token, ref.ID) {
				found = true
				break
			}
			if !strings.HasPrefix(ref.ID, "R") {
				continue
			}
			round, _, _ := strings.Cut(ref.ID, "-")
			if strings.EqualFold(token, round) {
				found = true
				break
			}
			if !strings.HasPrefix(strings.ToUpper(token), round+" · ") {
				continue
			}
			for _, s := range material.Sources {
				if s.ID != ref.ID {
					continue
				}
				for _, seat := range []string{s.Seat, s.SeatID} {
					if seat != "" && (strings.EqualFold(token, round+" · "+seat) ||
						(s.Model != "" && strings.EqualFold(token, round+" · "+seat+"/"+s.Model))) {
						found = true
						break
					}
				}
			}
			if found {
				break
			}
		}
		if !found {
			return "", fmt.Errorf("段内引用与提供的来源编号不符")
		}
	}
	text = inlineReport(reportRef.ReplaceAllString(text, ""))
	if text == "" {
		return "", fmt.Errorf("报告包含空段落")
	}
	if utf8.RuneCountInString(text) > limit {
		return "", fmt.Errorf("返回的段落超过 %d 字限制", limit)
	}
	return text, nil
}

// Quotes must be exact substrings of the source actually cited. The renderer
// adds the citations itself, never trusting inline references written by a model.
func (b reportBody) render(m reportMaterial) (string, error) {
	bad := fmt.Errorf("返回的报告缺少有效段落或引用，原话与来源必须逐条相符")
	if len(b.Outcome) == 0 {
		return "", bad
	}
	lookup := make(map[string]reportSource, len(m.Sources))
	for _, s := range m.Sources {
		lookup[s.ID] = s
	}
	var out strings.Builder
	quotes := []reportEvidence{}
	seen := map[reportEvidence]bool{}
	public := false
	for _, section := range b.sections() {
		if len(section.paragraphs) == 0 {
			continue
		}
		if len(section.paragraphs) > 12 {
			return "", bad
		}
		fmt.Fprintf(&out, "## %s\n\n", section.title)
		for _, p := range section.paragraphs {
			if len(p.Evidence) == 0 || len(p.Evidence) > 8 {
				return "", bad
			}
			prose, err := reportProse(p.Text, p.Evidence, m, 1600)
			if err != nil {
				return "", err
			}
			out.WriteString(prose)
			used := map[string]bool{}
			for _, ref := range p.Evidence {
				ref.Quote = strings.TrimSpace(ref.Quote)
				source, ok := lookup[ref.ID]
				if !ok {
					return "", fmt.Errorf("引用编号不在本场来源索引中")
				}
				if ref.Quote == "" {
					return "", fmt.Errorf("引用缺少原文片段")
				}
				if utf8.RuneCountInString(ref.Quote) > 300 {
					return "", fmt.Errorf("引文超过 300 字上限")
				}
				if !source.containsQuote(ref.Quote) {
					return "", fmt.Errorf("引文与本次提供的原文片段不符")
				}
				if source.Kind == "public" {
					public = true
				}
				if !used[ref.ID] {
					fmt.Fprintf(&out, " [%s]", ref.ID)
					used[ref.ID] = true
				}
				if !seen[ref] {
					quotes = append(quotes, ref)
					seen[ref] = true
				}
			}
			out.WriteString("\n\n")
		}
	}
	if !public {
		return "", fmt.Errorf("至少需要引用一条已完成的公开发言")
	}
	out.WriteString("## 引用原文\n\n")
	for _, ref := range quotes {
		s := lookup[ref.ID]
		fmt.Fprintf(&out, "- [%s] %s · %s\n", s.ID, m.sourceLabel(s), reportQuoteLine(ref.Quote))
	}
	return out.String(), nil
}

// Keep a verbatim-validated quote in its single cited list item. Preserve
// typography inside each line, including full-width spaces and punctuation.
var reportLineBreaks = strings.NewReplacer("\r\n", " ", "\r", " ", "\n", " ", "\u0085", " ", "\u2028", " ", "\u2029", " ")

func reportQuoteLine(s string) string { return reportLineBreaks.Replace(s) }

func inlineReport(s string) string { return strings.Join(strings.Fields(s), " ") }

func (m reportMaterial) sourceSeatName(s reportSource) string {
	if s.seatLabel != "" {
		return s.seatLabel
	}
	return m.seatName(s.Seat)
}

func (m reportMaterial) sourceIdentity(s reportSource) string {
	name := m.sourceSeatName(s)
	seat := s.Seat
	if s.SeatID != "" {
		seat = s.SeatID
	}
	if m.ChangedModels[seat] && s.Model != "" && name != s.Model && !strings.HasPrefix(name, s.Model+" · 席位 ") {
		name += "（" + s.Model + "）"
	}
	return name
}

func (m reportMaterial) sourceLabel(s reportSource) string {
	switch s.Kind {
	case "agenda":
		if s.Seat != "" {
			return "议程 · " + m.sourceIdentity(s)
		}
		return "议程"
	case "host":
		return fmt.Sprintf("第 %d 轮主持人指令", s.Round)
	case "host_board":
		return "主持人议题板记录 · " + inlineReport(s.Target)
	case "file":
		return "已保存文件修改 · " + m.sourceIdentity(s)
	}
	return fmt.Sprintf("第 %d 轮 · %s", s.Round, m.sourceIdentity(s))
}

func (m reportMaterial) appendices() string {
	var agenda, files, points, boardNotes strings.Builder
	if m.BoardScope != "" {
		fmt.Fprintf(&boardNotes, "%s\n\n", m.BoardScope)
	}
	type stance struct {
		source reportSource
		value  Position
	}
	byPoint := map[string]map[string][]stance{}
	for _, s := range m.Sources {
		for _, p := range s.Positions {
			if byPoint[p.PointID] == nil {
				byPoint[p.PointID] = map[string][]stance{}
			}
			byPoint[p.PointID][s.Seat] = append(byPoint[p.PointID][s.Seat], stance{s, p})
		}
	}
	for _, s := range m.Sources {
		switch s.Kind {
		case "agenda":
			status := "待处理"
			if s.Status == "done" {
				status = "已完成"
			}
			fmt.Fprintf(&agenda, "- [%s] %s（%s）\n", s.ID, inlineReport(s.Text), status)
		case "host_board":
			excerpt := shorten(s.Text, 350)
			label := inlineReport(s.Target)
			if excerpt != s.Text {
				label += "（摘录）"
			}
			fmt.Fprintf(&boardNotes, "- [%s] %s · %s\n", s.ID, label, inlineReport(excerpt))
		case "file":
			label := m.sourceIdentity(s)
			if s.Seat == "user" {
				label = "主持人"
			}
			if s.Round > 0 {
				label = fmt.Sprintf("第 %d 轮 · %s", s.Round, label)
			}
			fmt.Fprintf(&files, "- [%s] %s · %s\n", s.ID, label, inlineReport(s.Text))
		}
		for _, point := range s.Points {
			fmt.Fprintf(&points, "\n**%s** [%s]\n\n", inlineReport(point.Text), s.ID)
			for _, seat := range m.Seats {
				history := byPoint[point.ID][seat]
				if len(history) == 0 {
					fmt.Fprintf(&points, "- %s · 未表态\n", m.seatName(seat))
					continue
				}
				last := history[len(history)-1]
				fmt.Fprintf(&points, "- %s · %s · %s [%s]", m.sourceIdentity(last.source), reportStance(last.value.Stance), inlineReport(last.value.Reason), last.source.ID)
				for i := len(history) - 2; i >= 0; i-- {
					prev := history[i]
					if prev.value.Stance != last.value.Stance {
						if prev.source.Model != "" && prev.source.Model != last.source.Model {
							fmt.Fprintf(&points, "（此前由 %s 表态为%s [%s]）", m.sourceIdentity(prev.source), reportStance(prev.value.Stance), prev.source.ID)
						} else {
							fmt.Fprintf(&points, "（此前%s [%s]）", reportStance(prev.value.Stance), prev.source.ID)
						}
						break
					}
				}
				points.WriteByte('\n')
			}
		}
	}
	var out strings.Builder
	for _, sec := range []struct{ title, body string }{{"观点与明确表态", points.String()}, {"主持人议题板笔记与批注", boardNotes.String()}, {"议程记录", agenda.String()}, {"已保存的文件修改", files.String()}} {
		if sec.body != "" {
			fmt.Fprintf(&out, "\n## %s\n\n%s", sec.title, sec.body)
		}
	}
	return out.String()
}

func (m reportMaterial) sourceDraft() string {
	var out strings.Builder
	out.WriteString("## 公开发言摘录\n\n")
	for _, s := range m.Sources {
		if s.Kind == "public" {
			fmt.Fprintf(&out, "- [%s] %s · %s\n", s.ID, m.sourceLabel(s), inlineReport(shorten(s.Text, 350)))
		}
	}
	return out.String()
}
