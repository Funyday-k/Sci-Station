from __future__ import annotations


def draft_gap_planning_sample(run_id: str, project_id: str) -> dict:
    return {
        "id": f"artifact-{run_id}-gap-plan",
        "run_id": run_id,
        "kind": "gap_planning_beta",
        "proposed_path": f"projects/{project_id}/wiki/research_plan.md",
        "title": "Research planning beta draft",
        "content": "# Research Plan\n\nThis P34 beta path validates the sidecar protocol; production planning belongs to P35.",
        "evidence_refs": [],
        "risk": "readOnly",
    }
