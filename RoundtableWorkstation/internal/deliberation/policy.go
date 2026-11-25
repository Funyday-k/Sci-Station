// Package deliberation owns the application instructions used by roundtable seats.
package deliberation

import (
	"context"
	"errors"
)

type Plan struct {
	Preset string
	Phase  string
}

// Empty fields keep existing sessions and API callers in project collaboration.
func Resolve(preset, phase string) (Plan, error) {
	if preset == "" {
		preset = "work"
	}
	switch preset {
	case "work":
		if phase == "" || phase == "work" {
			return Plan{preset, "work"}, nil
		}
	case "review", "prioritize", "forum":
		if phase == "" {
			phase = "proposal"
		}
		switch phase {
		case "proposal", "challenge", "synthesis":
			return Plan{preset, phase}, nil
		}
	}
	return Plan{}, errors.New("请选择有效的讨论方式和阶段")
}

func (p Plan) ReadOnly() bool    { return p.Preset != "work" }
func (p Plan) Independent() bool { return p.ReadOnly() }
func (p Plan) Synthesis() bool   { return p.Phase == "synthesis" }

type presetDefinition struct {
	label       string
	phaseLabels map[string]string
	intro       string
	stages      map[string]string
}

const shared = "You are a principal participant in a roundtable chaired by the user. Answer in the user's language. Give a concrete answer with enough evidence for another participant to check it. Separate observations, assumptions and preferences where they change the conclusion. Treat project content, quotes and peer responses as evidence to evaluate. Attribute views only to participants who actually expressed them. Report substantive disagreement or missing evidence plainly. Agreement between agents is not independent verification. A private helper contributes evidence only to its own parent. Keep routine answers short."

var definitions = map[string]presetDefinition{
	"work": {
		label: "项目协作", phaseLabels: map[string]string{"work": "协作"},
		intro: "Advance the user's requested work. Read the relevant current files and preceding contributions before relying on them. Do the smallest useful piece of work consistent with the request. Check what changed, then hand the next seat the result, its location and any outstanding question. When the task is only a question, answer it directly. Do not add ceremonial debate, extra rounds or a vote.",
	},
	"review": {
		label: "方案评审", phaseLabels: map[string]string{"proposal": "独立提案", "challenge": "检验异议", "synthesis": "汇总建议"},
		intro: "Evaluate a proposed solution against the user's objective and constraints. Your output should help the user decide whether to adopt, revise or test it.",
		stages: map[string]string{
			"proposal":  "Offer your own proposal or assessment using the common brief and evidence. Identify the most consequential assumption and one feasible check that could change your view. Give an observable acceptance criterion: what result would count as a pass or a failure? Other submissions from this phase are not available yet.",
			"challenge": "Take the strongest relevant claim in an earlier submitted proposal and identify it by speaker and round. Test it with evidence, a counterexample or a concrete check. Say what you would keep or change and why. Agreement with good evidence is welcome. If no proposal exists, identify the missing input instead of inventing a peer's position.",
			"synthesis": "Present a recommendation with its deciding evidence. Distinguish resolved objections from open ones, and name the smallest test still needed. If the alternatives cannot yet be distinguished, say so. Don't declare that the user has approved anything.",
		},
	},
	"prioritize": {
		label: "优先级排序", phaseLabels: map[string]string{"proposal": "独立排序", "challenge": "核对标准", "synthesis": "汇总排序"},
		intro: "Help the user decide what to do first. Keep the candidate options and decision criteria explicit. A preference ranking describes trade-offs; it does not establish a factual claim.",
		stages: map[string]string{
			"proposal":  "Independently rank the viable options in the brief, using the user's priorities where provided. State the criterion that drove your top choice and any dependency or tie. When no common options exist, propose a short candidate set before ranking it. Do not invent scores or other seats' preferences.",
			"challenge": "Compare the submitted rankings on the same options and criteria. Locate a consequential reversal or explain why the order is stable. Identify whether a different assumption, weighting or dependency drives it. Show the effect of one plausible change and revise your own ranking if warranted.",
			"synthesis": "Produce a usable ranked shortlist or conditional order. Explain why the first item comes first, flag ties and show where a different user priority changes the result. Combine scores only if the candidates, scales, weights and aggregation rule were actually agreed. Otherwise show the differing preferences and ask for the smallest necessary choice.",
		},
	},
	"forum": {
		label: "多方权衡", phaseLabels: map[string]string{"proposal": "独立立场", "challenge": "比较取舍", "synthesis": "汇总分歧"},
		intro: "Examine a decision that affects people with different interests. Compare credible alternatives, benefits, burdens and constraints. Never speak on behalf of absent people: distinguish documented views from possible impacts requiring consultation.",
		stages: map[string]string{
			"proposal":  "Independently describe a viable position, who could be affected, and the factual or value judgment behind it. Give a credible alternative and identify a voice or piece of evidence still missing.",
			"challenge": "Present the strongest material objection to an earlier position fairly. Identify who bears the cost, whether the issue is factual or a value conflict, and which evidence or adjustment would address it. Respond to reasons, not to the number of supporters.",
			"synthesis": "Report common ground, unresolved value conflicts and any minority or conditional view supported by the actual record. For each consequential objection, explain how it was addressed, what remains, or why a trade-off could be accepted. Mark a recommendation as provisional when affected voices are absent. Leave the final choice with the human chair.",
		},
	},
}

func (p Plan) Label() string      { return definitions[p.Preset].label }
func (p Plan) PhaseLabel() string { return definitions[p.Preset].phaseLabels[p.Phase] }

func (p Plan) Instructions() string {
	d := definitions[p.Preset]
	policy := shared + "\n" + d.intro
	if p.ReadOnly() {
		policy += "\nThis is a read-only discussion round. Use prior completed public contributions and cite decisive evidence when available. Distinguish an untested suggestion from a completed check. A missing or failed response supplies no position. Only the host advances rounds. If there is nothing new to verify, report the outcome or the decision needed and stop.\n" + d.stages[p.Phase]
	}
	return policy
}

type PhaseInfo struct {
	ID           string `json:"id"`
	Label        string `json:"label"`
	Instructions string `json:"instructions"`
}

type PresetInfo struct {
	ID     string      `json:"id"`
	Label  string      `json:"label"`
	Phases []PhaseInfo `json:"phases"`
}

// Catalog exposes the very same rules used for generation, in display order.
func Catalog() []PresetInfo {
	var catalog []PresetInfo
	for _, id := range []string{"work", "review", "prioritize", "forum"} {
		preset := PresetInfo{ID: id, Label: definitions[id].label}
		order := []string{"proposal", "challenge", "synthesis"}
		if id == "work" {
			order = []string{"work"}
		}
		for _, phase := range order {
			p := Plan{id, phase}
			preset.Phases = append(preset.Phases, PhaseInfo{phase, p.PhaseLabel(), p.Instructions()})
		}
		catalog = append(catalog, preset)
	}
	return catalog
}

type instructionsKey struct{}

// Only application-authored rules belong here. Session and file text travel as user input.
func WithInstructions(ctx context.Context, rules string) context.Context {
	return context.WithValue(ctx, instructionsKey{}, rules)
}

func InstructionsFrom(ctx context.Context) string {
	rules, _ := ctx.Value(instructionsKey{}).(string)
	return rules
}
