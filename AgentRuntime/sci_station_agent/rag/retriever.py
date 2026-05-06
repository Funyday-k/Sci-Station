from __future__ import annotations

import math
from dataclasses import dataclass

from .evidence import stable_evidence_id
from .embedding_store import EmbeddingStore, deterministic_embedding
from .fts_index import FTSIndex


@dataclass(frozen=True)
class EmbeddingConfig:
    enabled: bool = False
    provider: str = "swift-proxy"
    model: str = ""
    dimension: int = 0
    store: str = "sqlite-vec"
    model_version: str = ""
    fallback_reason: str | None = None


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
            row["retrieval_source"] = "embedding"
            row["source_hash_status"] = "fresh"
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
                "fts_score": 0.7,
                "retrieval_source": "fts",
                "source_hash_status": "fresh",
            })
        return evidence


class HybridRetriever:
    def __init__(self, fts_retriever: FTSRetriever, embedding_index: InMemoryEmbeddingIndex | EmbeddingStore | None = None, embedding_config: EmbeddingConfig | None = None) -> None:
        self.fts_retriever = fts_retriever
        self.embedding_index = embedding_index
        self.embedding_config = embedding_config or EmbeddingConfig()

    def retrieve(self, query: str, limit: int = 10, query_vector: list[float] | None = None) -> list[dict]:
        return self.retrieve_with_trace(query, limit=limit, query_vector=query_vector)[0]

    def retrieve_with_trace(self, query: str, limit: int = 10, query_vector: list[float] | None = None, current_source_hashes: dict[str, str] | None = None) -> tuple[list[dict], dict]:
        fts_top_k = max(limit, 1)
        candidates = self.fts_retriever.retrieve(query, limit=fts_top_k)
        fallback_reason = None
        embedding_store_name = self.embedding_config.store
        if self.embedding_config.enabled and self.embedding_index:
            if hasattr(self.embedding_index, "query"):
                embedding_rows = self.embedding_index.query(query, limit=fts_top_k, current_source_hashes=current_source_hashes)  # type: ignore[attr-defined]
                candidates.extend(row.to_candidate() for row in embedding_rows)
                stats = self.embedding_index.stats(current_source_hashes or {})  # type: ignore[attr-defined]
                embedding_store_name = stats.store
                fallback_reason = stats.fallback_reason
            elif query_vector:
                candidates.extend(self.embedding_index.search(query_vector, limit=fts_top_k))  # type: ignore[union-attr]
            else:
                fallback_reason = "query vector unavailable; using FTS-only candidates"
        elif not self.embedding_config.enabled:
            fallback_reason = "embedding disabled; using FTS-only candidates"
        results, trace_candidates = _dedupe_and_rerank(candidates, limit=limit)
        trace = build_retrieval_trace(
            query=query,
            retrieval_mode="hybrid" if self.embedding_config.enabled and self.embedding_index else "fts_only",
            embedding_store=embedding_store_name if self.embedding_config.enabled else "fts_only",
            fallback_reason=fallback_reason or self.embedding_config.fallback_reason,
            candidates=trace_candidates,
        )
        return results, trace


def _dedupe_and_rerank(candidates: list[dict], limit: int | None = None) -> tuple[list[dict], list[dict]]:
    by_chunk: dict[str, dict] = {}
    deduped_trace: list[dict] = []
    for candidate in candidates:
        chunk_id = str(candidate.get("chunk_id") or candidate.get("id"))
        existing = by_chunk.get(chunk_id)
        candidate = dict(candidate)
        candidate["rerank_score"] = _score(candidate)
        candidate["rerank_reason"] = _rerank_reason(candidate)
        if existing is None:
            by_chunk[chunk_id] = candidate
        elif _score(candidate) > _score(existing):
            candidate["dedupe_reason"] = "replaced lower scored duplicate chunk"
            by_chunk[chunk_id] = candidate
            deduped_trace.append(_trace_candidate(existing, dedupe_reason="duplicate chunk superseded"))
        else:
            deduped_trace.append(_trace_candidate(candidate, dedupe_reason="duplicate chunk lower score"))
    ranked = sorted(by_chunk.values(), key=_score, reverse=True)
    selected = ranked[:limit] if limit is not None else ranked
    trace_candidates = [_trace_candidate(candidate) for candidate in selected] + deduped_trace
    return selected, trace_candidates


def _score(candidate: dict) -> float:
    fts_score = float(candidate.get("fts_score") or candidate.get("confidence") or 0.0)
    embedding_score = float(candidate.get("embedding_score") or 0.0)
    score = (0.55 * fts_score) + (0.45 * embedding_score)
    metadata = candidate.get("metadata") or {}
    if isinstance(metadata, dict):
        if metadata.get("core_paper"):
            score += 0.2
        if metadata.get("project_id"):
            score += 0.1
    if candidate.get("source_hash_status") == "fresh":
        score += 0.05
    return score


def _rerank_reason(candidate: dict) -> str:
    reasons = []
    if candidate.get("fts_score") is not None:
        reasons.append("keyword match")
    if candidate.get("embedding_score") is not None:
        reasons.append("semantic similarity")
    if candidate.get("source_hash_status") == "fresh":
        reasons.append("fresh source hash")
    return " + ".join(reasons) or "deterministic score"


def _trace_candidate(candidate: dict, dedupe_reason: str | None = None) -> dict:
    lines = candidate.get("lines") or [None, None]
    return {
        "source_path": candidate.get("relative_path"),
        "chunk_id": candidate.get("chunk_id"),
        "fts_score": candidate.get("fts_score") or candidate.get("confidence"),
        "embedding_score": candidate.get("embedding_score"),
        "rerank_score": round(float(candidate.get("rerank_score") or _score(candidate)), 6),
        "rerank_reason": candidate.get("rerank_reason") or _rerank_reason(candidate),
        "dedupe_reason": dedupe_reason or candidate.get("dedupe_reason"),
        "source_hash_status": candidate.get("source_hash_status", "fresh"),
        "line_start": lines[0] if len(lines) > 0 else None,
        "line_end": lines[1] if len(lines) > 1 else None,
        "pdf_page": candidate.get("pdf_page"),
    }


def build_retrieval_trace(query: str, retrieval_mode: str, embedding_store: str, fallback_reason: str | None, candidates: list[dict]) -> dict:
    query_hash = "sha256:" + __import__("hashlib").sha256(query.encode("utf-8")).hexdigest()
    return {
        "schema_version": 2,
        "retrieval_mode": retrieval_mode,
        "embedding_store": embedding_store,
        "fallback_reason": fallback_reason,
        "query": {"redacted": True, "hash": query_hash},
        "candidates": candidates,
    }


def _cosine_similarity(first: list[float], second: list[float]) -> float:
    if not first or not second or len(first) != len(second):
        return 0.0
    dot = sum(a * b for a, b in zip(first, second))
    first_norm = math.sqrt(sum(a * a for a in first))
    second_norm = math.sqrt(sum(b * b for b in second))
    if first_norm == 0 or second_norm == 0:
        return 0.0
    return dot / (first_norm * second_norm)
