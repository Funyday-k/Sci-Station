package meeting

import (
	"encoding/json"
	"fmt"
	"strings"
	"testing"
	"unicode/utf8"
)

func TestContinuousPointsPreservesExplicitPositionsAtCutoff(t *testing.T) {
	const id = "r1-s1-p1"
	prior := []publicStatement{
		{Round: 1, Seat: "a", Points: []DiscussionPoint{{ID: id, Text: "Keep independent proposals."}}},
		{Round: 1, Seat: "b", Text: "Nothing to add."},
		{Round: 2, Seat: "c", Positions: []Position{{PointID: id, Stance: "support"}}},
		{Round: 3, Seat: "c", Positions: []Position{{PointID: id, Stance: "oppose"}}},
		{Round: 3, Seat: "d", Positions: []Position{{PointID: id, Stance: "qualified"}}},
		{Round: 4, Seat: "e", Points: []DiscussionPoint{{ID: "r4-s1-p1", Text: "Future only."}}, Positions: []Position{{PointID: id, Stance: "support"}}},
	}
	if continuousPoints(prior, 0) != nil || continuousPoints([]publicStatement{{Round: 1, Seat: "a", Text: "Legacy speech."}}, 10) != nil {
		t.Fatal("unstructured or future statements created a point")
	}
	index := continuousPoints(prior, 3)
	if index == nil || index.Total != 1 || len(index.Points) != 1 {
		t.Fatalf("incorrect cutoff or count: %+v", index)
	}
	p := index.Points[0]
	if p.ID != id || p.Seat != "a" || p.Round != 1 || len(p.Positions) != 2 ||
		p.Positions["c"] != (continuousPointStance{Stance: "oppose", Round: 3}) ||
		p.Positions["d"] != (continuousPointStance{Stance: "qualified", Round: 3}) {
		t.Fatalf("wrong source, inferred or stale stance: %+v", p)
	}
	earlier := continuousPoints(prior, 2).Points[0].Positions
	if len(earlier) != 1 || earlier["c"] != (continuousPointStance{Stance: "support", Round: 2}) {
		t.Fatalf("later opinions altered an earlier cutoff: %v", earlier)
	}
}

func TestContinuousPointsBoundedJSONKeepsActiveOldPointRetrievable(t *testing.T) {
	// Both multibyte and JSON-escaped characters matter for the byte budget.
	title := "关键" + strings.Repeat("检<&证", 45)
	prior := make([]publicStatement, 0, 102)
	for i := 1; i <= 100; i++ {
		id := fmt.Sprintf("r%d-s1-p1", i)
		prior = append(prior, publicStatement{Round: i, Seat: "chair", Text: title, Points: []DiscussionPoint{{ID: id, Text: title}}})
	}
	const oldID = "r1-s1-p1"
	reason := "I oppose this until the comparison is independently checked."
	prior = append(prior, publicStatement{Round: 101, Seat: "peer", Text: reason, Positions: []Position{{PointID: oldID, Stance: "oppose", Reason: reason}}})
	index := continuousPoints(prior, 101)
	b, err := json.Marshal(index)
	if err != nil || len(b) > 6<<10 || strings.Contains(string(b), reason) {
		t.Fatalf("JSON length=%d or full reasoning was copied: %v", len(b), err)
	}
	if index.Total != 100 || len(index.Points) < 2 || len(index.Points) >= index.Total {
		t.Fatalf("index total or bounded selection wrong: total %d, shown %d", index.Total, len(index.Points))
	}
	first := index.Points[0]
	if first.ID != oldID || first.Positions["peer"] != (continuousPointStance{Stance: "oppose", Round: 101}) ||
		index.Points[1].ID != "r100-s1-p1" || !utf8.ValidString(first.Text) || !strings.HasSuffix(first.Text, "…") ||
		!strings.HasPrefix(title, strings.TrimSuffix(first.Text, "…")) {
		t.Fatalf("lost a recently challenged point, its original locator or a UTF-8 boundary: %+v", first)
	}
	// Older statements are absent from inline context after the checkpoint.
	reader := newStatementReader(prior, nil)
	source, err := reader.read(action{Round: first.Round, Seat: first.Seat})
	if err != nil || source.(publicStatement).Text != title {
		t.Fatalf("index cannot retrieve the full original proposition: %v", err)
	}
	source, err = reader.read(action{Round: first.Positions["peer"].Round, Seat: "peer"})
	if err != nil || source.(publicStatement).Text != reason {
		t.Fatalf("index cannot retrieve the original objection: %v", err)
	}
}

func TestContinuousPointsNeverDropsIndividualDissentToFit(t *testing.T) {
	prior := []publicStatement{
		{Round: 1, Seat: "one", Points: []DiscussionPoint{{ID: "small", Text: "Small point"}, {ID: "large", Text: "Large debate"}}},
	}
	for i := 0; i < 200; i++ {
		prior = append(prior, publicStatement{Round: 2, Seat: fmt.Sprintf("seat-%04d", i), Positions: []Position{{PointID: "large", Stance: "oppose"}}})
	}
	index := continuousPoints(prior, 2)
	if index.Total != 2 || len(index.Points) != 1 || index.Points[0].ID != "small" {
		t.Fatalf("partial stances displayed for an oversized point: %+v", index)
	}
}
