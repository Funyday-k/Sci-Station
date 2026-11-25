package meeting

import (
	"fmt"
	"strings"
)

// RecordedTurnModel resolves an older turn from its own frozen round when the
// saved turn predates explicit model attribution.
func (r Round) RecordedTurnModel(t Turn) string {
	if t.Model != "" {
		return t.Model
	}
	return r.Settings.Models[t.Seat]
}

func (r Round) catalogTurnModel(t Turn) string {
	model := r.RecordedTurnModel(t)
	if r.Settings.CatalogModelIDs[t.Seat] {
		return model
	}
	return legacyCatalogID(t.Seat, model)
}

// HistoricalSeatName displays the captured label or model of an earlier speaker
// while retaining the seat number when its current identity has changed.
func (s *Session) HistoricalSeatName(seat, model, label string, names map[string]string) string {
	currentName := names[seat]
	if currentName == "" {
		currentName = seat
	}
	if seat == "user" || seat == "" {
		return currentName
	}
	current := s.memberForSeat(seat)
	if current == nil && label == "" {
		return currentName
	}
	label = strings.TrimSpace(label)
	if current != nil && (((model == "" || current.Model == "") && label == "" && current.ModelEpoch == 0) ||
		(model == current.Model && (label == "" || label == current.Label))) {
		return currentName
	}
	if label == "" {
		label = model
	}
	for i, id := range s.Seats {
		if id == seat {
			if label == "" {
				return fmt.Sprintf("席位 %d", i+1)
			}
			return fmt.Sprintf("%s · 席位 %d", label, i+1)
		}
	}
	if label != "" {
		return label
	}
	return currentName
}
