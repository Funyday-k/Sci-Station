package meeting

import (
	"encoding/json"
	"fmt"
	"strings"
	"unicode/utf8"
)

// Bound the complete serialized meeting projection, including the source
// index, repeated model labels, position details and JSON escaping.
const reportMaterialBudget = 64 << 10
const reportDraftBudget = 32 << 10

// SeatNames returns the public labels used for meeting citations and tools.
func (s *Session) SeatNames() map[string]string {
	names := map[string]string{"user": "主持人", "codex": "Codex", "cursor": "Cursor"}
	counts := map[string]int{}
	seats := s.Seats
	if len(seats) == 0 {
		for _, member := range s.Members {
			seats = append(seats, member.ID)
		}
	}
	for _, seat := range seats {
		m := s.memberForSeat(seat)
		if m == nil {
			continue
		}
		name := m.Label
		if name == "" {
			name = m.Model
		}
		if name == "" {
			name = m.ID
		}
		names[seat] = name
		counts[name]++
	}
	for i, seat := range seats {
		name := names[seat]
		if counts[name] > 1 {
			names[seat] = fmt.Sprintf("%s · 席位 %d", name, i+1)
		}
	}
	return names
}
func (m reportMaterial) seatName(seat string) string {
	if name := m.Names[seat]; name != "" {
		return name
	}
	return seat
}
func reportStance(stance string) string {
	switch stance {
	case "support":
		return "认同"
	case "oppose":
		return "不认同"
	case "qualified":
		return "有保留"
	case "undecided":
		return "尚未决定"
	}
	return "未知表态"
}
func (s reportSource) containsQuote(quote string) bool {
	original := s.original
	if original == "" {
		original = s.Text
	}
	if !strings.Contains(original, quote) {
		return false
	}
	if strings.Contains(s.Text, quote) || strings.Contains(s.Tail, quote) {
		return true
	}
	for _, p := range s.Points {
		if strings.Contains(p.Text, quote) {
			return true
		}
	}
	for _, p := range s.Positions {
		if strings.Contains(p.Reason, quote) {
			return true
		}
	}
	return false
}

func exactTail(s string, limit int) string {
	if len(s) <= limit {
		return s
	}
	offset := len(s) - limit
	for offset < len(s) && !utf8.RuneStart(s[offset]) {
		offset++
	}
	return s[offset:]
}

// All fields share a cap when the full projection exceeds the budget. Every
// original source keeps its ID and each long statement gets its own opening
// and closing excerpts, independent of its position in the meeting.
func (m reportMaterial) capped(limit int) reportMaterial {
	out := reportMaterial{Topic: prefixBytes(m.Topic, limit), Names: m.Names, ChangedModels: m.ChangedModels, BoardScope: m.BoardScope}
	for _, seat := range m.Seats {
		out.Seats = append(out.Seats, m.seatName(seat))
	}
	short := out.Topic != m.Topic
	public, excerpted := 0, 0
	for _, s := range m.Sources {
		view := s
		view.SeatID, view.Seat = s.Seat, m.sourceSeatName(s)
		view.original = s.Text
		if s.Kind == "public" {
			public++
		}
		if len(s.Text) > limit {
			short = true
			view.Partial = true
			if s.Kind == "public" {
				head := (limit + 1) / 2
				view.Text = prefixBytes(s.Text, head)
				view.Tail = exactTail(s.Text, limit-head)
				excerpted++
			} else {
				view.Text = prefixBytes(s.Text, limit)
			}
		}
		view.Points = append([]DiscussionPoint(nil), s.Points...)
		for i, p := range view.Points {
			view.Points[i].Text = prefixBytes(p.Text, limit)
			short = short || p.Text != view.Points[i].Text
		}
		view.Positions = append([]Position(nil), s.Positions...)
		for i, p := range view.Positions {
			view.Positions[i].Reason = prefixBytes(p.Reason, limit)
			short = short || p.Reason != view.Positions[i].Reason
		}
		out.Sources = append(out.Sources, view)
	}
	if short {
		out.Coverage = fmt.Sprintf("本次整理使用了 %d 条公开发言，其中 %d 条完整提供，%d 条提供首尾摘录。其他较长资料按相同上限节选。所有来源编号均保留，可在会议记录中查看原文。", public, public-excerpted, excerpted)
	}
	return out
}

func (m reportMaterial) forReportPrompt() (reportMaterial, error) {
	fits := func(view reportMaterial) bool {
		sources := view.Sources
		view.Sources = []reportSource{}
		header, _ := json.Marshal(view)
		total := len(header)
		for i, src := range sources {
			field, _ := json.Marshal(src)
			total += len(field)
			if i > 0 {
				total++
			}
			if total > reportMaterialBudget {
				return false
			}
		}
		return total <= reportMaterialBudget
	}
	// Bounding the first probe per field avoids repeatedly encoding full long
	// turns. Most short meetings fit in the one probe.
	initial := reportMaterialBudget
	letters := 0
	for _, src := range m.Sources {
		letters += len(src.Text)
	}
	if letters > reportMaterialBudget && len(m.Sources) > 0 {
		initial = reportMaterialBudget / len(m.Sources)
	}
	current := m.capped(initial)
	if fits(current) && current.Coverage == "" {
		return current, nil
	}
	low, high := 0, reportMaterialBudget
	best := reportMaterial{}
	if fits(current) {
		best = current
		low = initial + 1
	} else {
		high = initial - 1
	}
	for low <= high {
		mid := low + (high-low)/2
		view := m.capped(mid)
		if fits(view) {
			best = view
			low = mid + 1
		} else {
			high = mid - 1
		}
	}
	// Never label an index-only projection an examination of all the public
	// contributions. Preserve the source draft for the host instead.
	if len(best.Sources) == len(m.Sources) {
		usable := true
		for _, src := range best.Sources {
			if src.Kind == "public" && strings.TrimSpace(src.Text+src.Tail) == "" {
				usable = false
				break
			}
		}
		if usable {
			return best, nil
		}
	}
	return reportMaterial{}, fmt.Errorf("来源索引或发言数量超过单次复核容量，无法为每条公开发言提供原文。已保留全部来源的材料草稿。")
}
