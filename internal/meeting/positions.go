package meeting

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
)

// Points and positions belong to the completed public turn that contains them.
// A point ID is stable within a session, even when the speaker changes their view.
type DiscussionPoint struct {
	ID   string `json:"id"`
	Text string `json:"text"`
}

type Position struct {
	PointID string `json:"point_id"`
	Stance  string `json:"stance"`
	Reason  string `json:"reason"`
}

type publicStatement struct {
	Round       int               `json:"round"`
	Seat        string            `json:"seat"`
	Model       string            `json:"model"`
	Text        string            `json:"text"`
	TextExcerpt string            `json:"text_excerpt,omitempty"`
	TextOmitted bool              `json:"text_omitted,omitempty"`
	Points      []DiscussionPoint `json:"points,omitempty"`
	Positions   []Position        `json:"positions,omitempty"`
}

const positionInstructions = `When your final public statement raises a distinct proposition or explicitly evaluates a visible one, attach that information to your say action. For a new point use points:[{"text":"verbatim proposition from your say text","stance":"support","reason":"verbatim excerpt from the same text expressing your own position"}]. If you only raise the point, omit stance and reason. For an existing point use positions:[{"point_id":"ID found in prior_statements[].points","stance":"oppose","reason":"verbatim excerpt from your say text expressing your reason"}]. Copy the precise text including its language and punctuation. Use support, oppose, qualified (conditional or reserved), or undecided (you explicitly reserve judgment). Reuse a visible point's ID when answering it. Record only your own explicit position. Do not supply speaker, model, round or new IDs, count silence as agreement, or assign a position to anyone else. Omit these optional fields when the statement contains no such point or position.`

type newPoint struct {
	Text   string `json:"text"`
	Stance string `json:"stance,omitempty"`
	Reason string `json:"reason,omitempty"`
}

func priorPointIDs(prior []publicStatement) map[string]bool {
	ids := make(map[string]bool)
	for _, statement := range prior {
		for _, point := range statement.Points {
			ids[point.ID] = true
		}
	}
	return ids
}

// Only fields in the protocol are accepted. Provenance always comes from the
// turn that actually spoke, never from an attribution in a model's payload.
func decodePositionList[T any](name string, raw json.RawMessage) ([]T, error) {
	if len(raw) == 0 {
		return nil, nil
	}
	var entries []json.RawMessage
	if err := json.Unmarshal(raw, &entries); err != nil || entries == nil {
		return nil, fmt.Errorf("%s 必须是数组；无相关记录时可省略该字段", name)
	}
	out := make([]T, 0, len(entries))
	for _, entry := range entries {
		decoder := json.NewDecoder(bytes.NewReader(entry))
		decoder.DisallowUnknownFields()
		var value T
		if err := decoder.Decode(&value); err != nil || duplicateObjectFields(string(entry)) {
			return nil, fmt.Errorf("%s 含无效、重复或未定义的字段；轮次与席位由应用记录", name)
		}
		out = append(out, value)
	}
	return out, nil
}

func validatePosition(p Position, statement string) error {
	switch p.Stance {
	case "support", "oppose", "qualified", "undecided":
	default:
		return errors.New("stance 必须是 support、oppose、qualified 或 undecided")
	}
	if p.Reason == "" || !strings.Contains(statement, p.Reason) {
		return errors.New("reason 须逐字引用本次发言 text 中表达本人立场的原文")
	}
	return nil
}

func parsePositions(a action, visible map[string]bool, round, turnIndex int) ([]DiscussionPoint, []Position, error) {
	newPoints, err := decodePositionList[newPoint]("points", a.Points)
	if err != nil {
		return nil, nil, err
	}
	responses, err := decodePositionList[Position]("positions", a.Positions)
	if err != nil {
		return nil, nil, err
	}

	var points []DiscussionPoint
	var positions []Position
	seenText := make(map[string]bool)
	for i, draft := range newPoints {
		quote := strings.TrimSpace(draft.Text)
		if quote == "" || !strings.Contains(*a.Text, quote) || seenText[quote] {
			return nil, nil, errors.New("每个新增讨论点的 text 须分别逐字引用本次发言中不同的提议或主张")
		}
		seenText[quote] = true
		id := fmt.Sprintf("r%d-s%d-p%d", round, turnIndex+1, i+1)
		points = append(points, DiscussionPoint{ID: id, Text: quote})
		if draft.Stance != "" || draft.Reason != "" {
			position := Position{PointID: id, Stance: draft.Stance, Reason: strings.TrimSpace(draft.Reason)}
			if err := validatePosition(position, *a.Text); err != nil {
				return nil, nil, err
			}
			positions = append(positions, position)
		}
	}
	seenIDs := make(map[string]bool)
	for _, response := range responses {
		if !visible[response.PointID] || seenIDs[response.PointID] {
			return nil, nil, errors.New("positions 每个 point_id 只能出现一次，且必须来自 prior_statements 中可见的 points")
		}
		response.Reason = strings.TrimSpace(response.Reason)
		if err := validatePosition(response, *a.Text); err != nil {
			return nil, nil, err
		}
		seenIDs[response.PointID] = true
		positions = append(positions, response)
	}
	return points, positions, nil
}
