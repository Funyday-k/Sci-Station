from __future__ import annotations


def draft_related_work_sample(run_id: str, project_id: str) -> dict:
    return {
        "id": f"artifact-{run_id}-related-work",
        "run_id": run_id,
        "kind": "related_work_beta",
        "proposed_path": f"projects/{project_id}/wiki/related_work.md",
        "title": "Related work beta draft",
        "content": "# Related Work\n\nThis P34 beta path validates the sidecar protocol; production synthesis belongs to P35.",
        "evidence_refs": [],
        "risk": "readOnly",
    }
