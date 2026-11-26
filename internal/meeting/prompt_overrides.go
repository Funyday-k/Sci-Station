package meeting

import (
	"context"
	"strings"

	"scistation.local/desktop/internal/deliberation"
)

// PromptSurface is a model entry point in the workstation.
type PromptSurface string

const (
	PromptPlanner      PromptSurface = "planner"
	PromptToolLoop     PromptSurface = "tool_loop"
	PromptPaperSummary PromptSurface = "paper_summary"
)

func (s PromptSurface) Valid() bool {
	return s == PromptPlanner || s == PromptToolLoop || s == PromptPaperSummary
}

// PromptOverride is the exact workspace guidance selected when a run starts.
type PromptOverride struct {
	ID      string        `json:"id"`
	Version int           `json:"version"`
	Surface PromptSurface `json:"surface"`
	Digest  string        `json:"digest"`
	System  string        `json:"system,omitempty"`
	Body    string        `json:"body"`
}

func (p *PromptOverride) instructionBlock() string {
	if p == nil {
		return ""
	}
	return "\n\nWorkspace prompt guidance (subordinate to the protocol and access rules above):\n" + strings.TrimSpace(p.System+"\n\n"+p.Body)
}

// ResearchWorkflow identifies the existing formal AI Lab handoff header.
func ResearchWorkflow(topic string) string {
	lines := strings.SplitN(topic, "\n", 3)
	if len(lines) < 2 || !strings.HasPrefix(lines[0], "科研工作流 · ") {
		return ""
	}
	workflow, tagged := strings.CutPrefix(strings.TrimSpace(lines[1]), "工作流 ID：")
	if !tagged {
		return ""
	}
	switch workflow {
	case "paper-reading", "related-work", "gap-planning":
		return workflow
	default:
		return ""
	}
}

func (s *Session) promptSurface() PromptSurface {
	if len(s.Seats) == 1 && ResearchWorkflow(s.Topic) == "paper-reading" {
		return PromptPaperSummary
	}
	return PromptToolLoop
}

func withPromptOverride(ctx context.Context, override *PromptOverride) context.Context {
	if override == nil {
		return ctx
	}
	return deliberation.WithInstructions(ctx, deliberation.InstructionsFrom(ctx)+override.instructionBlock())
}
