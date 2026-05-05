from __future__ import annotations

import math
from dataclasses import dataclass

from .evidence import stable_evidence_id
from .fts_index import FTSIndex


@dataclass(frozen=True)
class EmbeddingConfig:
    enabled: bool = False
    provider: str = "swift-proxy"
    model: str = ""
    dimension: int = 0
    store: str = "sqlite-vec"


class InMemoryEmbeddingIndex:
    def __init__(self, schema_version: int = 1) -> None:
        self.schema_version = schema_version
        self._rows: dict[str, tuple[list[float], dict]] = {}

    def upsert(self, chunk_id: str, vector: list[float], evidence: dict) -> None:
        self._rows[chunk_id] = (vector, evidence)

    def search(self, query_vector: list[float], limit: int = 10) -> list[dict]:
        scored: list[tuple[float, dict]] = []
        for vector, evidence in self._rows.values():
            score = _cosine_similarity(query_vector, vector)
            row = dict(evidence)
            row["embedding_score"] = score
            scored.append((score, row))
        return [row for _, row in sorted(scored, key=lambda item: item[0], reverse=True)[:limit]]

    def stale_chunk_ids(self, current_source_hashes: dict[str, str]) -> list[str]:
        stale: list[str] = []
        for chunk_id, (_, evidence) in self._rows.items():
            relative_path = evidence.get("relative_path")
            current_hash = current_source_hashes.get(str(relative_path)) if relative_path else None
            if current_hash and evidence.get("source_hash") != current_hash:
                stale.append(chunk_id)
        return stale


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


class HybridRetriever:
    def __init__(self, fts_retriever: FTSRetriever, embedding_index: InMemoryEmbeddingIndex | None = None, embedding_config: EmbeddingConfig | None = None) -> None:
        self.fts_retriever = fts_retriever
        self.embedding_index = embedding_index
        self.embedding_config = embedding_config or EmbeddingConfig()

    def retrieve(self, query: str, limit: int = 10, query_vector: list[float] | None = None) -> list[dict]:
        fts_top_k = max(limit, 1)
        candidates = self.fts_retriever.retrieve(query, limit=fts_top_k)
        if self.embedding_config.enabled and self.embedding_index and query_vector:
            candidates.extend(self.embedding_index.search(query_vector, limit=fts_top_k))
        return _dedupe_and_rerank(candidates)[:limit]


def _dedupe_and_rerank(candidates: list[dict]) -> list[dict]:
    by_chunk: dict[str, dict] = {}
    for candidate in candidates:
        chunk_id = str(candidate.get("chunk_id") or candidate.get("id"))
        existing = by_chunk.get(chunk_id)
        if existing is None or _score(candidate) > _score(existing):
            by_chunk[chunk_id] = candidate
    return sorted(by_chunk.values(), key=_score, reverse=True)


def _score(candidate: dict) -> float:
    score = float(candidate.get("confidence") or 0.0)
    score += float(candidate.get("embedding_score") or 0.0)
    metadata = candidate.get("metadata") or {}
    if isinstance(metadata, dict):
        if metadata.get("core_paper"):
            score += 0.2
        if metadata.get("project_id"):
            score += 0.1
    return score


def _cosine_similarity(first: list[float], second: list[float]) -> float:
    if not first or not second or len(first) != len(second):
        return 0.0
    dot = sum(a * b for a, b in zip(first, second))
    first_norm = math.sqrt(sum(a * a for a in first))
    second_norm = math.sqrt(sum(b * b for b in second))
    if first_norm == 0 or second_norm == 0:
        return 0.0
    return dot / (first_norm * second_norm)
