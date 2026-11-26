package meeting

import (
	"context"
	"errors"
	"fmt"
	"unicode/utf8"

	"scistation.local/desktop/internal/deliberation"
)

// ToolBudget covers workstation-mediated actions in one seat's tool loop,
// including its children. The selected CLI owns all of its independent tools.
type ToolBudget struct {
	MaxCalls     int  `json:"max_calls"`
	ContextChars int  `json:"context_chars"`
	TotalResults int  `json:"total_results"`
	PerResult    int  `json:"per_result"`
	AutoRead     bool `json:"auto_read"`
}

func (b *ToolBudget) Validate() error {
	if b == nil {
		return nil
	}
	if b.MaxCalls < 1 || b.MaxCalls > 240 ||
		b.ContextChars < 1000 || b.ContextChars > 5_000_000 ||
		b.TotalResults < 1000 || b.TotalResults > 5_000_000 ||
		b.PerResult < 1000 || b.PerResult > b.TotalResults {
		return errors.New("请检查工具调用次数（1–240）、上下文与工具结果字数（1,000–5,000,000）；单次上限不能超过累计上限")
	}
	return nil
}

type runningToolBudget struct {
	settings *ToolBudget
	calls    int
	results  int
}

func (b *runningToolBudget) checkContext(ctx context.Context, prompt string) error {
	if b.settings != nil && utf8.RuneCountInString(prompt)+utf8.RuneCountInString(deliberation.InstructionsFrom(ctx)) > b.settings.ContextChars {
		return errors.New("本轮文本上下文超过工具预算。请减少材料或调整设置后开始新一轮。")
	}
	return nil
}

func (b *runningToolBudget) reserve() error {
	if b.settings == nil {
		return nil
	}
	if b.calls >= b.settings.MaxCalls {
		return errors.New("已达到本席位的工具调用上限，请根据现有证据总结")
	}
	if b.settings.TotalResults-b.results < 100 {
		return errors.New("已达到本席位的工具结果累计字数上限，请根据现有证据总结")
	}
	b.calls++
	return nil
}

// A clipped payload stays valid JSON and identifies the record as incomplete.
func (b *runningToolBudget) record(result any) any {
	if b.settings == nil {
		return result
	}
	const omitted = "工具结果超出剩余字数预算。"
	encoded := marshal(result)
	limit := min(b.settings.PerResult, b.settings.TotalResults-b.results)
	length := utf8.RuneCountInString(encoded)
	if length <= limit {
		b.results += length
		return result
	}
	if limit < 100 {
		return nil
	}
	content := []rune(encoded)
	// JSON escaping can expand characters, so also check the encoded preview.
	for cap := min(limit-60, len(content)); cap > 0; cap /= 2 {
		preview := map[string]any{"truncated": true, "preview": string(content[:cap])}
		if chars := utf8.RuneCountInString(marshal(preview)); chars <= limit {
			b.results += chars
			return preview
		}
	}
	b.results += utf8.RuneCountInString(marshal(omitted))
	return omitted
}

func (e *Engine) authorizeModelRead(ctx context.Context, id, seat, child string, index int, a action, b *runningToolBudget) error {
	if b.settings == nil || b.settings.AutoRead {
		return nil
	}
	var target string
	if a.Action == "read" {
		var err error
		target, err = relative(a.Path)
		if err != nil {
			return err
		}
	} else {
		target = fmt.Sprintf("R%d · %s", a.Round, a.Seat)
	}
	return e.waitForReadDecision(ctx, id, seat, child, index, a.Action, target)
}
