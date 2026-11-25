package meeting

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"sync"
	"testing"

	"scistation.local/desktop/internal/deliberation"
)

func TestContinuousCompactionRetainsMemoryAndOriginalStatements(t *testing.T) {
	const unresolvedQuote = "ROUND_1_UNRESOLVED_SOURCE"
	const hostHeading = "CURRENT_HOST_HEADING"
	const hostAnnotation = "CURRENT_HOST_POINT_ANNOTATION"
	longInitial := "ROUND_1_PUBLIC_SOURCE\n" + unresolvedQuote + "\n" + strings.Repeat("x", 20000)
	type summaryCapture struct {
		through int
		bytes   int
		prompt  string
	}
	var mu sync.Mutex
	var summaries []summaryCapture
	var beforeCompactBytes, afterCompactBytes int
	readRequested, readVerified := false, false
	var editDuringCheckpoint func() error

	call := func(ctx context.Context, seat, model, prompt, executable string) (string, error) {
		instructions := deliberation.InstructionsFrom(ctx)
		switch {
		case strings.Contains(instructions, "CONTINUOUS_SUMMARY"):
			const marker = "CONTINUOUS_SUMMARY REQUEST\n"
			if !strings.HasPrefix(prompt, marker) {
				return "", fmt.Errorf("summary request missing serialized payload")
			}
			payloadBytes := []byte(strings.TrimPrefix(prompt, marker))
			var payload struct {
				Previous []ContinuousItem `json:"previous_checkpoint"`
				New      []struct {
					Round int    `json:"round"`
					Seat  string `json:"seat"`
					Text  string `json:"text"`
				} `json:"new_public_statements"`
			}
			if err := json.Unmarshal(payloadBytes, &payload); err != nil {
				return "", fmt.Errorf("decode serialized summary input: %w", err)
			}
			through := 0
			for _, statement := range payload.New {
				if statement.Round > through {
					through = statement.Round
				}
			}
			mu.Lock()
			summaries = append(summaries, summaryCapture{through: through, bytes: len(payloadBytes), prompt: prompt})
			mu.Unlock()
			if through == 3 {
				if err := editDuringCheckpoint(); err != nil {
					return "", err
				}
			}

			items := append([]ContinuousItem(nil), payload.Previous...)
			for _, statement := range payload.New {
				quote := strings.SplitN(statement.Text, "\n", 2)[0]
				if quote == "" {
					return "", fmt.Errorf("round %d has no quotable source", statement.Round)
				}
				items = append(items, ContinuousItem{
					Text:  fmt.Sprintf("未决事项仍需核对（第 %d 轮）。", statement.Round),
					Round: statement.Round,
					Seat:  statement.Seat,
					Quote: quote,
				})
			}
			encoded, err := json.Marshal(continuousSummaryReply{Items: items})
			return string(encoded), err

		case strings.Contains(instructions, "CONTINUOUS_REVIEW"):
			const marker = "REVIEW MATERIAL\n"
			_, material, ok := strings.Cut(prompt, marker)
			if !ok {
				return "", fmt.Errorf("review request missing material")
			}
			var request struct {
				Round int `json:"round"`
			}
			if err := json.Unmarshal([]byte(material), &request); err != nil {
				return "", fmt.Errorf("decode review material: %w", err)
			}
			decision, reason, next := "continue", "仍有未决事项。", "继续检查未决事项。"
			if request.Round >= 10 {
				decision, reason, next = "complete", "达到本轮测试目标。", ""
			}
			return fmt.Sprintf(`{"decision":%q,"reason":%q,"next":%q,"progress":true,"evidence":[{"id":"R%d-T1","quote":"ROUND_%d_PUBLIC_SOURCE"}]}`,
				decision, reason, next, request.Round, request.Round), nil

		default:
			contextBytes, data, err := continuousMemoryContext(prompt)
			if err != nil {
				return "", err
			}
			round, _ := data["round"].(float64)
			roundNumber := int(round)
			if roundNumber == 2 {
				if !strings.Contains(string(contextBytes), unresolvedQuote) || !continuousMemoryContextHasStatement(data, 1, longInitial) {
					return "", fmt.Errorf("round 2 pre-compaction context omitted original long speech (bytes=%d)", len(contextBytes))
				}
				mu.Lock()
				beforeCompactBytes = len(contextBytes)
				mu.Unlock()
			}
			if roundNumber == 5 {
				var board MeetingBoard
				if err := json.Unmarshal([]byte(marshal(data["board"])), &board); err != nil {
					return "", err
				}
				point := board.PointAnnotations["r1-s1-p1"]
				if board.Title != hostHeading || board.SourceSeat != "user" || point.Body != hostAnnotation || point.SourceSeat != "user" {
					return "", fmt.Errorf("round after compaction did not receive the latest host board: %+v", board)
				}
				targets := marshal(data["board_annotation_targets"])
				if !strings.Contains(targets, unresolvedQuote) || !strings.Contains(targets, `"seat":"codex"`) {
					return "", fmt.Errorf("annotated original point lost its source after compaction: %s", targets)
				}
				if _, key := ModelRequest(ctx); !strings.HasSuffix(key, "-continuous-1-3") {
					return "", fmt.Errorf("compacted turn reused the old gateway session: %s", key)
				}
				if continuousMemoryContextHasStatement(data, 1, longInitial) {
					return "", fmt.Errorf("round 5 context still contains the covered long speech")
				}
				checkpoint, ok := data["rolling_summary"].(map[string]any)
				if !ok {
					return "", fmt.Errorf("round 5 context has no rolling_summary")
				}
				if checkpoint["through_round"] != float64(3) {
					return "", fmt.Errorf("round 5 checkpoint through_round = %v, want 3", checkpoint["through_round"])
				}
				items, ok := checkpoint["items"].([]any)
				if !ok {
					return "", fmt.Errorf("round 5 checkpoint has no items")
				}
				retainedUnresolved := false
				for _, raw := range items {
					item, ok := raw.(map[string]any)
					if !ok {
						continue
					}
					text, _ := item["text"].(string)
					quote, _ := item["quote"].(string)
					round, _ := item["round"].(float64)
					seat, _ := item["seat"].(string)
					if strings.Contains(text, "未决") && int(round) > 0 && seat == "codex" && quote != "" {
						retainedUnresolved = true
					}
				}
				if !retainedUnresolved {
					return "", fmt.Errorf("rolling summary lost its sourced unresolved item: %v", items)
				}
				prior, ok := data["prior_statements"].([]any)
				if !ok {
					return "", fmt.Errorf("round 5 context has no prior_statements")
				}
				latestFull := false
				for _, raw := range prior {
					statement, ok := raw.(map[string]any)
					if !ok || statement["round"] != float64(4) {
						continue
					}
					text, _ := statement["text"].(string)
					latestFull = text == "ROUND_4_PUBLIC_SOURCE\nAUTO_ROUND_4_DETAIL"
				}
				if !latestFull {
					return "", fmt.Errorf("latest completed statement is not present in full in round 5 context")
				}
				mu.Lock()
				afterCompactBytes = len(contextBytes)
				if !readRequested {
					readRequested = true
					mu.Unlock()
					return `{"action":"read_statement","round":1,"seat":"codex"}`, nil
				}
				mu.Unlock()
				if !continuousMemoryHistoryHasStatement(prompt, longInitial) {
					return "", fmt.Errorf("read_statement feedback did not restore the original round 1 text")
				}
				mu.Lock()
				readVerified = true
				mu.Unlock()
			}
			if roundNumber == 6 {
				if _, ok := data["rolling_summary"]; !ok {
					return "", fmt.Errorf("round 6 context lost its rolling summary")
				}
			}
			if roundNumber == 1 {
				return marshal(map[string]any{"action": "say", "text": longInitial, "points": []newPoint{{Text: unresolvedQuote}}}), nil
			}
			return say(fmt.Sprintf("ROUND_%d_PUBLIC_SOURCE\nAUTO_ROUND_%d_DETAIL", roundNumber, roundNumber)), nil
		}
	}

	e, project := engine(t, call)
	s, err := e.Create("continuous memory", project, []string{"codex"})
	if err != nil {
		t.Fatal(err)
	}
	editDuringCheckpoint = func() error {
		title, body, zero := hostHeading, hostAnnotation, 0
		if _, err := e.ChangeBoard(s.ID, HostBoardChange{Op: "rename_board", Title: &title, ExpectedVersion: &zero}); err != nil {
			return err
		}
		_, err := e.ChangeBoard(s.ID, HostBoardChange{Op: "annotate_point", PointID: "r1-s1-p1", Body: &body, ExpectedVersion: &zero})
		return err
	}
	config := &ContinuousConfig{Goal: "保留未决事项直到完成复核", Criteria: "保留可追溯的原始证据", MaxRounds: 12, SummaryEvery: 2}
	if _, err = e.StartRound(s.ID, "", "", 0, RoundOptions{Preset: "work", Phase: "work", Continuous: config}); err != nil {
		t.Fatal(err)
	}
	final := settled(t, e, s.ID)
	if final.Continuous == nil || final.Continuous.Status != "completed" {
		t.Fatalf("continuous run did not complete: session=%q continuous=%+v rounds=%+v", final.Status, final.Continuous, final.Rounds)
	}
	if len(final.Rounds) < 10 {
		t.Fatalf("continuous run stopped after %d rounds, want at least 10", len(final.Rounds))
	}
	if !final.Rounds[2].Auto {
		t.Fatal("round 3 was expected to be an automatically scheduled round")
	}
	for i, round := range final.Rounds {
		if len(round.Turns) != 1 || round.Turns[0].Status != "done" {
			t.Fatalf("round %d has no completed original statement: %+v", round.Number, round.Turns)
		}
		want := fmt.Sprintf("ROUND_%d_PUBLIC_SOURCE\nAUTO_ROUND_%d_DETAIL", i+1, i+1)
		if i == 0 {
			want = longInitial
		}
		if round.Turns[0].Text != want {
			t.Fatalf("round %d original statement was not retained intact", round.Number)
		}
	}
	mu.Lock()
	before, after := beforeCompactBytes, afterCompactBytes
	verifiedRead := readVerified
	captured := append([]summaryCapture(nil), summaries...)
	mu.Unlock()
	if !verifiedRead {
		t.Fatal("the model did not retrieve round 1 through read_statement after compaction")
	}
	if before <= after || before == 0 || after == 0 {
		t.Fatalf("serialized CONTEXT did not shrink after compaction: before=%d bytes after=%d bytes", before, after)
	}
	if len(captured) < 2 || captured[0].bytes == 0 || captured[1].bytes == 0 {
		t.Fatalf("summary requests did not record actual serialized input sizes: %+v", captured)
	}
	if captured[1].through != 3 || !strings.Contains(captured[1].prompt, "AUTO_ROUND_3_DETAIL") {
		t.Fatalf("second summary did not include automatic round 3: %+v", captured[1])
	}
	if captured[1].bytes >= captured[0].bytes {
		t.Fatalf("serialized summary input did not shrink after its first checkpoint: %d -> %d bytes", captured[0].bytes, captured[1].bytes)
	}
	uncompressed := clone(final)
	uncompressed.Rounds = uncompressed.Rounds[:5]
	uncompressed.Continuous.Status = "active"
	uncompressed.Continuous.Checkpoint = nil
	uncompressed.Continuous.Next = uncompressed.Rounds[4].Note
	data, err := e.context(uncompressed, 0, "")
	if err != nil {
		t.Fatal(err)
	}
	data["prior_statements"] = compactStatements(data["prior_statements"].([]publicStatement))
	includeBoardPrompt(data, uncompressed, 0)
	includeLiveAgenda(data, uncompressed, uncompressed.Rounds[4].AgendaItemID)
	withoutCheckpoint := len(marshal(data))
	if withoutCheckpoint <= after {
		t.Fatal("the checkpoint did not reduce the fifth round's context")
	}
	t.Logf("round 5 serialized CONTEXT bytes without/with checkpoint: %d -> %d; observed round 2/round 5: %d -> %d", withoutCheckpoint, after, before, after)
}

func continuousMemoryContext(prompt string) ([]byte, map[string]any, error) {
	if !strings.HasPrefix(prompt, "CONTEXT:\n") {
		return nil, nil, fmt.Errorf("public prompt has no CONTEXT envelope")
	}
	encoded := strings.TrimPrefix(prompt, "CONTEXT:\n")
	if contextJSON, _, ok := strings.Cut(encoded, "\nSTEPS REMAINING:"); ok {
		encoded = contextJSON
	}
	var data map[string]any
	if err := json.Unmarshal([]byte(encoded), &data); err != nil {
		return nil, nil, fmt.Errorf("decode CONTEXT JSON: %w", err)
	}
	return []byte(encoded), data, nil
}

func continuousMemoryContextHasStatement(data map[string]any, round int, text string) bool {
	statements, ok := data["prior_statements"].([]any)
	if !ok {
		return false
	}
	for _, raw := range statements {
		statement, ok := raw.(map[string]any)
		if ok && statement["round"] == float64(round) && statement["text"] == text {
			return true
		}
	}
	return false
}

func continuousMemoryHistoryHasStatement(prompt, text string) bool {
	_, historyJSON, ok := strings.Cut(prompt, "ACTION HISTORY:\n")
	if !ok {
		return false
	}
	var history []struct {
		Result map[string]any `json:"result"`
	}
	if json.Unmarshal([]byte(historyJSON), &history) != nil {
		return false
	}
	for _, entry := range history {
		if entry.Result["text"] == text {
			return true
		}
	}
	return false
}
