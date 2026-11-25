package meeting

import (
	"encoding/json"
	"sort"
)

const continuousPointBudget = 6 << 10

type continuousPointIndex struct {
	Total  int               `json:"total"`
	Points []continuousPoint `json:"points"`
}

type continuousPoint struct {
	ID        string                           `json:"id"`
	Text      string                           `json:"text"`
	Round     int                              `json:"round"`
	Seat      string                           `json:"seat"`
	Model     string                           `json:"model,omitempty"`
	Positions map[string]continuousPointStance `json:"positions,omitempty"`
	lastTurn  int
}

type continuousPointStance struct {
	Stance string `json:"stance"`
	Round  int    `json:"round"`
	Model  string `json:"model,omitempty"`
}

// prior contains completed, visible statements in speaking order. This index
// refers back to those statements without reproducing their reasons or full text.
func continuousPoints(prior []publicStatement, through int) *continuousPointIndex {
	var points []continuousPoint
	byID := make(map[string]int)
	for turn, statement := range prior {
		if statement.Round > through {
			continue
		}
		for _, p := range statement.Points {
			if _, exists := byID[p.ID]; exists || p.ID == "" {
				continue
			}
			title := prefixBytes(p.Text, 160)
			if len(title) < len(p.Text) {
				title += "…"
			}
			byID[p.ID] = len(points)
			points = append(points, continuousPoint{ID: p.ID, Text: title, Round: statement.Round, Seat: statement.Seat, Model: statement.Model, lastTurn: turn})
		}
		for _, position := range statement.Positions {
			idx, exists := byID[position.PointID]
			if !exists {
				continue
			}
			switch position.Stance {
			case "support", "oppose", "qualified", "undecided":
				p := &points[idx]
				if p.Positions == nil {
					p.Positions = make(map[string]continuousPointStance)
				}
				p.Positions[statement.Seat] = continuousPointStance{Stance: position.Stance, Round: statement.Round, Model: statement.Model}
				p.lastTurn = turn
			}
		}
	}
	if len(points) == 0 {
		return nil
	}

	sort.SliceStable(points, func(i, j int) bool { return points[i].lastTurn > points[j].lastTurn })
	index := &continuousPointIndex{Total: len(points), Points: []continuousPoint{}}
	envelope, _ := json.Marshal(index)
	remaining := continuousPointBudget - len(envelope)
	for _, point := range points {
		encoded, _ := json.Marshal(point)
		size := len(encoded)
		if size > continuousPointBudget-len(envelope) {
			// Keep every seat for an included point, even when one point alone
			// is too large. The total still counts points absent from this view.
			continue
		}
		if len(index.Points) > 0 {
			size++ // JSON array separator.
		}
		if size > remaining {
			break
		}
		index.Points = append(index.Points, point)
		remaining -= size
	}
	return index
}
