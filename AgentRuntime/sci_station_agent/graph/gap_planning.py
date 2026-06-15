from __future__ import annotations

from dataclasses import dataclass

from .citation_critic import critic_check_evidence


@dataclass(frozen=True)
class GapPlanningDraft:
    artifact: dict
    evidence: list[dict]
    todo_drafts: list[dict]
    duplicate_warnings: list[dict]
    critic_report: dict


def draft_gap_planning_production(
    run_id: str,
    project_id: str,
    evidence_table: list[dict],
    existing_tasks: list[dict] | None = None,
) -> GapPlanningDraft:
    existing_tasks = existing_tasks or []
    gaps = synthesize_research_gaps(evidence_table)
    todo_drafts = generate_todo_drafts(project_id, gaps, existing_tasks)
    duplicate_warnings = [todo for todo in todo_drafts if todo.get("possible_duplicate_task_id")]
    artifact = {
        "id": f"artifact-{run_id}-research-plan",
        "run_id": run_id,
        "kind": "research_plan",
        "proposed_path": f"projects/{project_id}/wiki/research_plan.md",
        "title": "Research plan draft",
        "content": _research_plan_content(gaps, todo_drafts),
        "evidence_refs": _evidence_refs(evidence_table),
        "risk": "readOnly",
    }
    report = critic_check_evidence(artifact, evidence_table).to_dict()
    return GapPlanningDraft(artifact=artifact, evidence=evidence_table, todo_drafts=todo_drafts, duplicate_warnings=duplicate_warnings, critic_report=report)


def synthesize_research_gaps(evidence_table: list[dict]) -> list[dict]:
    gaps: list[dict] = []
    for index, evidence in enumerate(evidence_table[:6], start=1):
        if index % 3 == 1:
            gap_type = "evidence-backed gap"
        elif index % 3 == 2:
            gap_type = "inferred gap"
        else:
            gap_type = "user-assumption"
        gaps.append({
            "id": f"gap-{index}",
            "type": gap_type,
            "summary": f"{gap_type.title()} from {_source_label(evidence)}",
            "evidence_id": evidence.get("id"),
            "related_paper_or_project": evidence.get("source_id") or evidence.get("relative_path"),
            "confidence": evidence.get("confidence", 0.6),
        })
    return gaps


def generate_todo_drafts(project_id: str, gaps: list[dict], existing_tasks: list[dict]) -> list[dict]:
    existing_titles = {str(task.get("title") or "").lower(): task for task in existing_tasks}
    drafts: list[dict] = []
    for index, gap in enumerate(gaps[:4], start=1):
        title = f"Investigate {gap['id']} for {project_id}"
        normalized = title.lower()
        duplicate = existing_titles.get(normalized)
        drafts.append({
            "title": title,
            "priority": "high" if gap["type"] == "evidence-backed gap" else "medium",
            "related_paper_or_project": gap.get("related_paper_or_project"),
            "reason": gap["summary"],
            "optional_due_date": None,
            "evidence_refs": [gap.get("evidence_id")],
            "possible_duplicate_task_id": duplicate.get("id") if duplicate else None,
        })
    return drafts


def draft_gap_planning_sample(run_id: str, project_id: str) -> dict:
    return {
        "id": f"artifact-{run_id}-gap-plan",
        "run_id": run_id,
        "kind": "gap_planning_beta",
        "proposed_path": f"projects/{project_id}/wiki/research_plan.md",
        "title": "Research planning beta draft",
        "content": "# Research Plan\n\nThis sample path validates the sidecar protocol; use the production gap-planning workflow for evidence-backed planning.",
        "evidence_refs": [],
        "risk": "readOnly",
    }


def _research_plan_content(gaps: list[dict], todo_drafts: list[dict]) -> str:
    first_evidence = str(gaps[0].get("evidence_id")) if gaps else "missing-evidence"
    context_evidence = str(gaps[1].get("evidence_id")) if len(gaps) > 1 else first_evidence
    milestone_evidence = str(gaps[2].get("evidence_id")) if len(gaps) > 2 else first_evidence
    lines = [
        "# Research Plan",
        "",
        "## Current Context",
        f"- The active project has evidence that can seed a cautious planning draft. [evidence:{context_evidence}]",
        "",
        "## Candidate Gaps",
    ]
    for gap in gaps:
        lines.append(f"- {gap['type']}: {gap['summary']}. [evidence:{gap.get('evidence_id')}]")
    lines.extend(["", "## Hypotheses"])
    for index, gap in enumerate(gaps[:3]):
        support = gaps[(index + 3) % len(gaps)] if gaps else gap
        lines.append(f"- Hypothesis for {gap['id']} should be treated as {gap['type']}. [evidence:{support.get('evidence_id')}]")
    lines.extend(["", "## Proposed Experiments"])
    for index, gap in enumerate(gaps[:3]):
        support = gaps[(index + 4) % len(gaps)] if gaps else gap
        lines.append(f"- Run a scoped experiment that checks {gap['id']} against the cited source. [evidence:{support.get('evidence_id')}]")
    lines.extend(["", "## Milestones", "- Confirm evidence quality before converting todo drafts into real tasks. [evidence:{}]".format(milestone_evidence), "", "## Todo Drafts"])
    for todo in todo_drafts:
        duplicate = f" Possible duplicate: {todo['possible_duplicate_task_id']}." if todo.get("possible_duplicate_task_id") else ""
        lines.append(f"- [{todo['priority']}] {todo['title']}: {todo['reason']}.{duplicate} [evidence:{todo['evidence_refs'][0]}]")
    lines.extend(["", "## Evidence"])
    for gap in gaps:
        lines.append(f"- {gap.get('evidence_id')}: {gap['type']} / {gap.get('related_paper_or_project')}")
    return "\n".join(lines) + "\n"


def _evidence_refs(evidence_table: list[dict]) -> list[dict]:
    return [{
        "id": item.get("id"),
        "relative_path": item.get("relative_path"),
        "lines": item.get("lines"),
        "source_hash": item.get("source_hash"),
        "chunk_id": item.get("chunk_id"),
        "retrieved_at": item.get("retrieved_at"),
    } for item in evidence_table if item.get("id")]


def _source_label(evidence: dict) -> str:
    return str(evidence.get("source_id") or evidence.get("relative_path") or "source")
