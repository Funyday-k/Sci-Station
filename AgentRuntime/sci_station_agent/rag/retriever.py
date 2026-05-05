from __future__ import annotations

from .evidence import stable_evidence_id
from .fts_index import FTSIndex


class FTSRetriever:
    def __init__(self, index: FTSIndex) -> None:
        self.index = index

    def retrieve(self, query: str, limit: int = 10) -> list[dict]:
        rows = self.index.search(query, limit=limit)
        evidence = []
        for row in rows:
            evidence_id = stable_evidence_id(row["source_type"], row.get("source_id"), row["relative_path"], int(row["start_line"]), int(row["end_line"]), row["content_hash"])
            evidence.append({
                "id": evidence_id,
                "source_type": row["source_type"],
                "source_id": row.get("source_id"),
                "relative_path": row["relative_path"],
                "lines": [int(row["start_line"]), int(row["end_line"])],
                "source_hash": row["content_hash"],
                "chunk_id": row["chunk_id"],
                "retrieved_at": row["updated_at"],
                "heading": row.get("heading"),
                "quote": row["text"][:240],
                "confidence": 0.7,
            })
        return evidence
