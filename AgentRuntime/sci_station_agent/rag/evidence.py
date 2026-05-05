from __future__ import annotations

import hashlib
from dataclasses import dataclass


def stable_evidence_id(source_type: str, source_id: str | None, relative_path: str, start_line: int, end_line: int, source_hash: str) -> str:
    raw = "\u001f".join([source_type, source_id or "", relative_path, str(start_line), str(end_line), source_hash])
    return "sha256:" + hashlib.sha256(raw.encode("utf-8")).hexdigest()


@dataclass(frozen=True)
class EvidenceRef:
    id: str
    source_type: str
    source_id: str | None
    relative_path: str
    lines: list[int]
    source_hash: str
    chunk_id: str
    retrieved_at: str
    heading: str | None = None
    quote: str | None = None
    confidence: float | None = None

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "source_type": self.source_type,
            "source_id": self.source_id,
            "relative_path": self.relative_path,
            "lines": self.lines,
            "source_hash": self.source_hash,
            "chunk_id": self.chunk_id,
            "retrieved_at": self.retrieved_at,
            "heading": self.heading,
            "quote": self.quote,
            "confidence": self.confidence,
        }


def is_stale(evidence: EvidenceRef | dict, current_source_hash: str | None) -> bool:
    if current_source_hash is None:
        return False
    source_hash = evidence.source_hash if isinstance(evidence, EvidenceRef) else evidence.get("source_hash")
    return bool(source_hash and source_hash != current_source_hash)
