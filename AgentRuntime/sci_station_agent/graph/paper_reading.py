from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone

from ..rag.evidence import EvidenceRef, stable_evidence_id


@dataclass(frozen=True)
class PaperReadingDraft:
    artifact: dict
    evidence: list[dict]
    needs_conversion: bool = False


def draft_paper_reading_note(
    run_id: str,
    paper_id: str,
    paper_text: str,
    relative_path: str,
    source_hash: str,
) -> PaperReadingDraft:
    lines = paper_text.splitlines()
    if len(paper_text.strip()) < 600 or len(lines) < 12:
        artifact = {
            "id": f"artifact-{run_id}-paper-conversion",
            "run_id": run_id,
            "kind": "paper_reading_note",
            "proposed_path": f"wiki/papers/{paper_id}.md",
            "title": "Paper text needs conversion",
            "content": "# Paper Note\n\nThe converted paper text is missing or too short. Convert or OCR the paper before generating an evidence-backed deep reading note.",
            "evidence_refs": [],
            "risk": "readOnly",
        }
        return PaperReadingDraft(artifact=artifact, evidence=[], needs_conversion=True)

    evidence = [
        _evidence("paper", paper_id, relative_path, 1, min(8, len(lines)), source_hash, "overview", lines),
        _evidence("paper", paper_id, relative_path, 9, min(16, len(lines)), source_hash, "method", lines),
        _evidence("paper", paper_id, relative_path, 17, min(24, len(lines)), source_hash, "method", lines),
        _evidence("paper", paper_id, relative_path, 25, min(32, len(lines)), source_hash, "contribution", lines),
        _evidence("paper", paper_id, relative_path, 33, min(40, len(lines)), source_hash, "contribution", lines),
        _evidence("paper", paper_id, relative_path, 41, min(48, len(lines)), source_hash, "limitation", lines),
        _evidence("paper", paper_id, relative_path, 49, min(56, len(lines)), source_hash, "limitation", lines),
    ]
    evidence_refs = [{
        "id": item["id"],
        "relative_path": item["relative_path"],
        "lines": item["lines"],
        "source_hash": item["source_hash"],
        "chunk_id": item["chunk_id"],
        "retrieved_at": item["retrieved_at"],
    } for item in evidence]
    content = _note_content(paper_id, evidence_refs)
    artifact = {
        "id": f"artifact-{run_id}-paper-note",
        "run_id": run_id,
        "kind": "paper_reading_note",
        "proposed_path": f"wiki/papers/{paper_id}.md",
        "title": f"Structured paper note for {paper_id}",
        "content": content,
        "evidence_refs": evidence_refs,
        "risk": "readOnly",
    }
    return PaperReadingDraft(artifact=artifact, evidence=evidence)


def build_sample_paper_reading_events(run_id: str, goal: str, intent: str) -> list[dict]:
    timestamp = "2026-05-05T00:00:00Z"
    return [
        {"kind": "event", "envelope": _envelope("sample-run-started", run_id, 10, timestamp, "run_started", {"goal": goal})},
        {"kind": "event", "envelope": _envelope("sample-router", run_id, 20, timestamp, "node_started", {"name": f"router:{intent}"})},
        {"kind": "event", "envelope": _envelope("sample-final", run_id, 30, timestamp, "final_response", {"markdown": "Sidecar accepted the run and produced a sample workflow response."})},
    ]


def _evidence(source_type: str, source_id: str, relative_path: str, start_line: int, end_line: int, source_hash: str, heading: str, lines: list[str]) -> dict:
    chunk_id = f"{source_type}:{source_id}:{start_line}-{end_line}"
    evidence_id = stable_evidence_id(source_type, source_id, relative_path, start_line, end_line, source_hash)
    quote = " ".join(lines[max(0, start_line - 1) : min(len(lines), end_line)])[:240]
    ref = EvidenceRef(
        id=evidence_id,
        source_type=source_type,
        source_id=source_id,
        relative_path=relative_path,
        lines=[start_line, end_line],
        source_hash=source_hash,
        chunk_id=chunk_id,
        retrieved_at=datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        heading=heading,
        quote=quote,
        confidence=0.76,
    )
    return ref.to_dict()


def _note_content(paper_id: str, evidence_refs: list[dict]) -> str:
    ids = [ref["id"] for ref in evidence_refs]
    return "\n".join([
        f"# Paper Note: {paper_id}",
        "",
        "## Contributions",
        f"- Contribution claim 1. [evidence:{ids[3]}]",
        f"- Contribution claim 2. [evidence:{ids[4]}]",
        f"- Contribution claim 3. [evidence:{ids[0]}]",
        "",
        "## Methods",
        f"- Method claim 1. [evidence:{ids[1]}]",
        f"- Method claim 2. [evidence:{ids[2]}]",
        "",
        "## Limitations",
        f"- Limitation claim 1. [evidence:{ids[5]}]",
        f"- Limitation claim 2. [evidence:{ids[6]}]",
        "",
        "## Evidence",
        *[f"- {ref['id']}: {ref['relative_path']} lines {ref['lines'][0]}-{ref['lines'][1]}" for ref in evidence_refs],
    ])


def _envelope(event_id: str, run_id: str, sequence: int, timestamp: str, event_type: str, payload: dict) -> dict:
    return {
        "id": event_id,
        "schema_version": 1,
        "run_id": run_id,
        "sequence": sequence,
        "timestamp": timestamp,
        "event": {"type": event_type, "payload": payload},
    }
