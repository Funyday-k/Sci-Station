from __future__ import annotations

from dataclasses import dataclass

from .citation_critic import critic_check_evidence


@dataclass(frozen=True)
class RelatedWorkDraft:
    artifact: dict
    evidence: list[dict]
    evidence_matrix: list[dict]
    critic_report: dict


THEME_KEYWORDS = [
    ("retrieval", ("retrieval", "rag", "index", "search")),
    ("workflow", ("workflow", "agent", "planning", "orchestration")),
    ("evaluation", ("evaluation", "experiment", "benchmark", "metric")),
]


def draft_related_work_production(run_id: str, project_id: str, evidence_table: list[dict]) -> RelatedWorkDraft:
    clustered = cluster_by_theme(evidence_table)
    matrix = build_evidence_matrix(clustered)
    evidence_refs = _evidence_refs(evidence_table)
    content = _related_work_content(clustered, matrix)
    artifact = {
        "id": f"artifact-{run_id}-related-work",
        "run_id": run_id,
        "kind": "related_work",
        "proposed_path": f"projects/{project_id}/wiki/related_work.md",
        "title": "Related work draft",
        "content": content,
        "evidence_refs": evidence_refs,
        "risk": "readOnly",
    }
    report = critic_check_evidence(artifact, evidence_table).to_dict()
    return RelatedWorkDraft(artifact=artifact, evidence=evidence_table, evidence_matrix=matrix, critic_report=report)


def cluster_by_theme(evidence_table: list[dict]) -> dict[str, list[dict]]:
    clusters: dict[str, list[dict]] = {"Theme 1: Retrieval foundations": [], "Theme 2: Workflow orchestration": [], "Theme 3: Evaluation and gaps": []}
    fallback_order = list(clusters.keys())
    for index, evidence in enumerate(evidence_table):
        text = " ".join(str(evidence.get(key) or "") for key in ("heading", "quote", "claim", "source_id")).lower()
        assigned = False
        for theme_index, (_, keywords) in enumerate(THEME_KEYWORDS):
            if any(keyword in text for keyword in keywords):
                clusters[fallback_order[theme_index]].append(evidence)
                assigned = True
                break
        if not assigned:
            clusters[fallback_order[index % len(fallback_order)]].append(evidence)
    return clusters


def build_evidence_matrix(clusters: dict[str, list[dict]]) -> list[dict]:
    matrix: list[dict] = []
    for theme, items in clusters.items():
        for evidence in items:
            matrix.append({
                "theme": theme,
                "evidence_id": evidence.get("id"),
                "source": evidence.get("relative_path"),
                "lines": evidence.get("lines"),
                "claim": evidence.get("claim") or _claim_from_evidence(evidence),
                "confidence": evidence.get("confidence"),
            })
    return matrix


def draft_related_work_sample(run_id: str, project_id: str) -> dict:
    return {
        "id": f"artifact-{run_id}-related-work",
        "run_id": run_id,
        "kind": "related_work_beta",
        "proposed_path": f"projects/{project_id}/wiki/related_work.md",
        "title": "Related work beta draft",
        "content": "# Related Work\n\nThis sample path validates the sidecar protocol; use the production related-work workflow for evidence-backed synthesis.",
        "evidence_refs": [],
        "risk": "readOnly",
    }


def _related_work_content(clusters: dict[str, list[dict]], matrix: list[dict]) -> str:
    lines = [
        "# Related Work",
        "",
        "## Scope",
        "- This draft compares the active project's core papers by research theme rather than by paper order. [evidence:{}]".format(_first_evidence_id(matrix)),
    ]
    for index, (theme, items) in enumerate(clusters.items(), start=1):
        lines.extend(["", f"## Theme {index}"])
        for evidence in items[:2]:
            lines.append(f"- {theme} claim from {_source_label(evidence)}. [evidence:{evidence.get('id')}]")
        if len(items) < 2:
            lines.append(f"- {theme} needs one more source before final synthesis. [evidence:{items[0].get('id') if items else _first_evidence_id(matrix)}]")
    lines.extend([
        "",
        "## Comparison Table",
        "| Theme | Source | Evidence |",
        "| --- | --- | --- |",
    ])
    for row in matrix[:8]:
        lines.append(f"| {row['theme']} | {row['source']} | {row['evidence_id']} |")
    lines.extend([
        "",
        "## Research Gap Summary",
        "- The matrix suggests gaps where workflow orchestration is less directly evaluated against retrieval evidence. [evidence:{}]".format(_first_evidence_id(matrix)),
        "",
        "## Evidence Matrix",
    ])
    for row in matrix:
        start, end = (row.get("lines") or ["?", "?"])[:2]
        lines.append(f"- {row['theme']}: {row['evidence_id']} at {row['source']} lines {start}-{end}")
    return "\n".join(lines) + "\n"


def _claim_from_evidence(evidence: dict) -> str:
    quote = str(evidence.get("quote") or "").strip().replace("\n", " ")
    return quote[:120] if quote else "Evidence-backed claim"


def _source_label(evidence: dict) -> str:
    return str(evidence.get("source_id") or evidence.get("relative_path") or "source")


def _first_evidence_id(matrix: list[dict]) -> str:
    return str(matrix[0].get("evidence_id")) if matrix else "missing-evidence"


def _evidence_refs(evidence_table: list[dict]) -> list[dict]:
    return [{
        "id": item.get("id"),
        "relative_path": item.get("relative_path"),
        "lines": item.get("lines"),
        "source_hash": item.get("source_hash"),
        "chunk_id": item.get("chunk_id"),
        "retrieved_at": item.get("retrieved_at"),
    } for item in evidence_table if item.get("id")]
