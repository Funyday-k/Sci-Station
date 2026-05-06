from __future__ import annotations

import hashlib
import json
import math
import sqlite3
import threading
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Protocol

CHUNK_SCHEMA_VERSION = 1
DEFAULT_EMBEDDING_DIMENSION = 32
INDEX_RELATIVE_PATH = ".sci-station/index/embeddings"


class EmbeddingStoreUnavailable(RuntimeError):
    pass


@dataclass(frozen=True)
class EmbeddingModelIdentity:
    provider: str = "swift-proxy"
    model_id: str = "deterministic-fallback-v1"
    dimension: int = DEFAULT_EMBEDDING_DIMENSION
    model_version: str = "v1"


@dataclass(frozen=True)
class EmbeddingChunk:
    id: str
    source_path: str
    source_type: str
    source_hash: str
    chunk_index: int
    text_hash: str
    text: str
    line_start: int
    line_end: int
    heading_path: list[str] = field(default_factory=list)
    source_id: str | None = None
    pdf_page_start: int | None = None
    pdf_page_end: int | None = None
    embedding_provider: str = "swift-proxy"
    embedding_model_id: str = "deterministic-fallback-v1"
    embedding_dimension: int = DEFAULT_EMBEDDING_DIMENSION
    embedding_model_version: str = "v1"
    embedding_created_at: str = ""
    chunk_schema_version: int = CHUNK_SCHEMA_VERSION
    metadata: dict[str, str] = field(default_factory=dict)

    def as_evidence(self) -> dict:
        return {
            "id": self.id,
            "source_type": self.source_type,
            "source_id": self.source_id,
            "relative_path": self.source_path,
            "lines": [self.line_start, self.line_end],
            "source_hash": self.source_hash,
            "chunk_id": self.id,
            "retrieved_at": self.embedding_created_at or _now(),
            "heading": " > ".join(self.heading_path) if self.heading_path else None,
            "quote": self.text[:240],
            "confidence": 0.68,
        }


@dataclass(frozen=True)
class EmbeddingSearchResult:
    chunk: EmbeddingChunk
    score: float
    rank: int
    source_hash_status: str = "fresh"
    location_type: str = "markdown_line"
    snippet: str = ""

    def to_candidate(self) -> dict:
        candidate = self.chunk.as_evidence()
        candidate.update({
            "embedding_score": self.score,
            "rank": self.rank,
            "source_hash_status": self.source_hash_status,
            "location_type": self.location_type,
            "snippet": self.snippet or self.chunk.text[:240],
        })
        if self.chunk.pdf_page_start is not None:
            candidate["pdf_page"] = self.chunk.pdf_page_start
        return candidate


@dataclass(frozen=True)
class EmbeddingStoreStats:
    store: str
    status: str
    chunk_count: int
    stale_count: int = 0
    fallback_reason: str | None = None
    schema_version: int = CHUNK_SCHEMA_VERSION


class EmbeddingStore(Protocol):
    def open(self) -> None: ...
    def close(self) -> None: ...
    def health_check(self, model: EmbeddingModelIdentity, schema_version: int = CHUNK_SCHEMA_VERSION) -> EmbeddingStoreStats: ...
    def begin_transaction(self) -> None: ...
    def commit(self) -> None: ...
    def rollback(self) -> None: ...
    def upsert_chunks(self, chunks: list[EmbeddingChunk]) -> None: ...
    def delete_by_source(self, source_path: str) -> None: ...
    def mark_stale(self, current_source_hashes: dict[str, str]) -> list[str]: ...
    def query(self, query: str, limit: int = 10, current_source_hashes: dict[str, str] | None = None) -> list[EmbeddingSearchResult]: ...
    def stats(self, current_source_hashes: dict[str, str] | None = None) -> EmbeddingStoreStats: ...
    def compact(self) -> None: ...


class DeterministicFallbackEmbeddingStore:
    def __init__(self, index_directory: str | Path, fallback_reason: str = "sqlite-vec unavailable") -> None:
        self.index_directory = Path(index_directory)
        self.snapshot_path = self.index_directory / "deterministic_fallback_chunks.json"
        self.fallback_reason = fallback_reason
        self._lock = threading.RLock()
        self._rows: dict[str, EmbeddingChunk] = {}
        self._transaction_backup: dict[str, EmbeddingChunk] | None = None

    def open(self) -> None:
        with self._lock:
            self.index_directory.mkdir(parents=True, exist_ok=True)
            if not self.snapshot_path.exists():
                self._rows = {}
                return
            raw = json.loads(self.snapshot_path.read_text(encoding="utf-8"))
            self._rows = {item["id"]: EmbeddingChunk(**item) for item in raw.get("chunks", [])}

    def close(self) -> None:
        self._persist()

    def health_check(self, model: EmbeddingModelIdentity, schema_version: int = CHUNK_SCHEMA_VERSION) -> EmbeddingStoreStats:
        mismatched = [
            chunk for chunk in self._rows.values()
            if chunk.embedding_model_id != model.model_id
            or chunk.embedding_dimension != model.dimension
            or chunk.chunk_schema_version != schema_version
        ]
        status = "stale" if mismatched else "fallback"
        return EmbeddingStoreStats(
            store="deterministic_fallback",
            status=status,
            chunk_count=len(self._rows),
            stale_count=len(mismatched),
            fallback_reason=self.fallback_reason,
            schema_version=schema_version,
        )

    def begin_transaction(self) -> None:
        with self._lock:
            self._transaction_backup = dict(self._rows)

    def commit(self) -> None:
        with self._lock:
            self._persist()
            self._transaction_backup = None

    def rollback(self) -> None:
        with self._lock:
            if self._transaction_backup is not None:
                self._rows = self._transaction_backup
            self._transaction_backup = None

    def upsert_chunks(self, chunks: list[EmbeddingChunk]) -> None:
        with self._lock:
            for chunk in chunks:
                self._rows[chunk.id] = chunk

    def delete_by_source(self, source_path: str) -> None:
        with self._lock:
            self._rows = {key: chunk for key, chunk in self._rows.items() if chunk.source_path != source_path}

    def mark_stale(self, current_source_hashes: dict[str, str]) -> list[str]:
        return [
            chunk.id for chunk in self._rows.values()
            if current_source_hashes.get(chunk.source_path) not in (None, chunk.source_hash)
        ]

    def query(self, query: str, limit: int = 10, current_source_hashes: dict[str, str] | None = None) -> list[EmbeddingSearchResult]:
        current_source_hashes = current_source_hashes or {}
        query_vector = deterministic_embedding(query)
        scored: list[tuple[float, EmbeddingChunk]] = []
        for chunk in self._rows.values():
            lexical = lexical_score(query, chunk.text)
            vector = deterministic_embedding(chunk.text, dimension=chunk.embedding_dimension)
            semantic = cosine_similarity(query_vector[: chunk.embedding_dimension], vector)
            scored.append(((0.55 * lexical) + (0.45 * semantic), chunk))
        results: list[EmbeddingSearchResult] = []
        for rank, (score, chunk) in enumerate(sorted(scored, key=lambda item: item[0], reverse=True)[:limit], start=1):
            current_hash = current_source_hashes.get(chunk.source_path)
            if current_hash is None:
                status = "missing" if current_source_hashes else "fresh"
            else:
                status = "fresh" if current_hash == chunk.source_hash else "stale"
            location_type = "pdf_page" if chunk.pdf_page_start is not None else ("material_file" if chunk.source_type == "material" else "markdown_line")
            results.append(EmbeddingSearchResult(chunk=chunk, score=round(score, 6), rank=rank, source_hash_status=status, location_type=location_type, snippet=chunk.text[:240]))
        return results

    def stats(self, current_source_hashes: dict[str, str] | None = None) -> EmbeddingStoreStats:
        stale = len(self.mark_stale(current_source_hashes or {})) if current_source_hashes else 0
        return EmbeddingStoreStats(
            store="deterministic_fallback",
            status="fallback",
            chunk_count=len(self._rows),
            stale_count=stale,
            fallback_reason=self.fallback_reason,
        )

    def compact(self) -> None:
        self._persist()

    def _persist(self) -> None:
        with self._lock:
            self.index_directory.mkdir(parents=True, exist_ok=True)
            payload = {
                "schema_version": CHUNK_SCHEMA_VERSION,
                "store": "deterministic_fallback",
                "fallback_reason": self.fallback_reason,
                "chunks": [asdict(chunk) for chunk in sorted(self._rows.values(), key=lambda item: item.id)],
            }
            self.snapshot_path.write_text(json.dumps(payload, sort_keys=True, indent=2), encoding="utf-8")


class SQLiteVecEmbeddingStore:
    def __init__(self, index_directory: str | Path) -> None:
        self.index_directory = Path(index_directory)
        self.database_path = self.index_directory / "sqlite_vec_chunks.sqlite"
        self._lock = threading.RLock()
        self._connection: sqlite3.Connection | None = None

    def open(self) -> None:
        with self._lock:
            self.index_directory.mkdir(parents=True, exist_ok=True)
            connection = sqlite3.connect(self.database_path, check_same_thread=False)
            connection.row_factory = sqlite3.Row
            try:
                connection.enable_load_extension(True)
                connection.load_extension("sqlite_vec")
            except sqlite3.Error as exc:
                connection.close()
                raise EmbeddingStoreUnavailable(f"sqlite-vec extension unavailable: {exc}") from exc
            self._connection = connection
            self._create_schema()

    def close(self) -> None:
        with self._lock:
            if self._connection is not None:
                self._connection.commit()
                self._connection.close()
                self._connection = None

    def health_check(self, model: EmbeddingModelIdentity, schema_version: int = CHUNK_SCHEMA_VERSION) -> EmbeddingStoreStats:
        with self._lock:
            rows = self.connection.execute(
                "SELECT COUNT(*) FROM chunks WHERE embedding_model_id != ? OR embedding_dimension != ? OR chunk_schema_version != ?",
                (model.model_id, model.dimension, schema_version),
            ).fetchone()
            stale_count = int(rows[0]) if rows else 0
            return EmbeddingStoreStats(
                store="sqlite_vec",
                status="stale" if stale_count else "ready",
                chunk_count=self._chunk_count(),
                stale_count=stale_count,
                schema_version=schema_version,
            )

    def begin_transaction(self) -> None:
        with self._lock:
            self.connection.execute("BEGIN IMMEDIATE")

    def commit(self) -> None:
        with self._lock:
            self.connection.commit()

    def rollback(self) -> None:
        with self._lock:
            self.connection.rollback()

    def upsert_chunks(self, chunks: list[EmbeddingChunk]) -> None:
        with self._lock:
            self.connection.executemany(
                """
                INSERT OR REPLACE INTO chunks (
                    id, source_path, source_type, source_hash, embedding_provider,
                    embedding_model_id, embedding_model_version, embedding_dimension,
                    chunk_schema_version, text_hash, text, chunk_json, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    (
                        chunk.id,
                        chunk.source_path,
                        chunk.source_type,
                        chunk.source_hash,
                        chunk.embedding_provider,
                        chunk.embedding_model_id,
                        chunk.embedding_model_version,
                        chunk.embedding_dimension,
                        chunk.chunk_schema_version,
                        chunk.text_hash,
                        chunk.text,
                        json.dumps(asdict(chunk), sort_keys=True),
                        _now(),
                    )
                    for chunk in chunks
                ],
            )

    def delete_by_source(self, source_path: str) -> None:
        with self._lock:
            self.connection.execute("DELETE FROM chunks WHERE source_path = ?", (source_path,))

    def mark_stale(self, current_source_hashes: dict[str, str]) -> list[str]:
        with self._lock:
            stale: list[str] = []
            for row in self.connection.execute("SELECT id, source_path, source_hash FROM chunks"):
                current_hash = current_source_hashes.get(str(row["source_path"]))
                if current_hash is not None and current_hash != row["source_hash"]:
                    stale.append(str(row["id"]))
            return stale

    def query(self, query: str, limit: int = 10, current_source_hashes: dict[str, str] | None = None) -> list[EmbeddingSearchResult]:
        current_source_hashes = current_source_hashes or {}
        query_vector = deterministic_embedding(query)
        with self._lock:
            chunks = [self._chunk_from_row(row) for row in self.connection.execute("SELECT chunk_json FROM chunks")]
        scored: list[tuple[float, EmbeddingChunk]] = []
        for chunk in chunks:
            lexical = lexical_score(query, chunk.text)
            vector = deterministic_embedding(chunk.text, dimension=chunk.embedding_dimension)
            semantic = cosine_similarity(query_vector[: chunk.embedding_dimension], vector)
            scored.append(((0.55 * lexical) + (0.45 * semantic), chunk))
        results: list[EmbeddingSearchResult] = []
        for rank, (score, chunk) in enumerate(sorted(scored, key=lambda item: item[0], reverse=True)[:limit], start=1):
            current_hash = current_source_hashes.get(chunk.source_path)
            if current_hash is None:
                status = "missing" if current_source_hashes else "fresh"
            else:
                status = "fresh" if current_hash == chunk.source_hash else "stale"
            location_type = "pdf_page" if chunk.pdf_page_start is not None else ("material_file" if chunk.source_type == "material" else "markdown_line")
            results.append(EmbeddingSearchResult(chunk=chunk, score=round(score, 6), rank=rank, source_hash_status=status, location_type=location_type, snippet=chunk.text[:240]))
        return results

    def stats(self, current_source_hashes: dict[str, str] | None = None) -> EmbeddingStoreStats:
        stale_count = len(self.mark_stale(current_source_hashes or {})) if current_source_hashes else 0
        return EmbeddingStoreStats(store="sqlite_vec", status="stale" if stale_count else "ready", chunk_count=self._chunk_count(), stale_count=stale_count)

    def compact(self) -> None:
        with self._lock:
            self.connection.execute("VACUUM")

    @property
    def connection(self) -> sqlite3.Connection:
        if self._connection is None:
            raise EmbeddingStoreUnavailable("sqlite-vec store is not open")
        return self._connection

    def _create_schema(self) -> None:
        self.connection.execute("CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
        self.connection.execute(
            """
            CREATE TABLE IF NOT EXISTS chunks (
                id TEXT PRIMARY KEY,
                source_path TEXT NOT NULL,
                source_type TEXT NOT NULL,
                source_hash TEXT NOT NULL,
                embedding_provider TEXT NOT NULL,
                embedding_model_id TEXT NOT NULL,
                embedding_model_version TEXT,
                embedding_dimension INTEGER NOT NULL,
                chunk_schema_version INTEGER NOT NULL,
                text_hash TEXT NOT NULL,
                text TEXT NOT NULL,
                chunk_json TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
            """
        )
        self.connection.execute("CREATE INDEX IF NOT EXISTS chunks_source_path_idx ON chunks(source_path)")
        self.connection.execute("CREATE INDEX IF NOT EXISTS chunks_model_idx ON chunks(embedding_model_id, embedding_dimension, chunk_schema_version)")
        self.connection.execute("INSERT OR REPLACE INTO metadata(key, value) VALUES('schema_version', ?)", (str(CHUNK_SCHEMA_VERSION),))
        self.connection.commit()

    def _chunk_count(self) -> int:
        row = self.connection.execute("SELECT COUNT(*) FROM chunks").fetchone()
        return int(row[0]) if row else 0

    def _chunk_from_row(self, row: sqlite3.Row) -> EmbeddingChunk:
        return EmbeddingChunk(**json.loads(str(row["chunk_json"])))


def open_preferred_embedding_store(workspace_root: str | Path, prefer_sqlite_vec: bool = True) -> EmbeddingStore:
    index_directory = Path(workspace_root) / INDEX_RELATIVE_PATH
    if prefer_sqlite_vec:
        sqlite_store = SQLiteVecEmbeddingStore(index_directory)
        try:
            sqlite_store.open()
            return sqlite_store
        except Exception as exc:
            fallback = DeterministicFallbackEmbeddingStore(index_directory, fallback_reason=str(exc))
            fallback.open()
            return fallback
    fallback = DeterministicFallbackEmbeddingStore(index_directory, fallback_reason="sqlite-vec disabled by configuration")
    fallback.open()
    return fallback


def chunks_from_resource_document(document, model: EmbeddingModelIdentity | None = None, max_lines: int = 80) -> list[EmbeddingChunk]:
    from .fts_index import chunk_markdown, content_hash

    model = model or EmbeddingModelIdentity()
    source_hash = document.content_hash or content_hash(document.content)
    chunks: list[EmbeddingChunk] = []
    for index, chunk in enumerate(chunk_markdown(document, max_lines=max_lines), start=0):
        text = str(chunk["text"])
        chunks.append(EmbeddingChunk(
            id=str(chunk["chunk_id"]),
            source_path=document.relative_path,
            source_type=document.source_type,
            source_id=document.source_id,
            source_hash=source_hash,
            chunk_index=index,
            text_hash=content_hash(text),
            text=text,
            line_start=int(chunk["start_line"]),
            line_end=int(chunk["end_line"]),
            heading_path=list(chunk.get("heading_path") or ([chunk["heading"]] if chunk.get("heading") else [])),
            embedding_provider=model.provider,
            embedding_model_id=model.model_id,
            embedding_model_version=model.model_version,
            embedding_dimension=model.dimension,
            embedding_created_at=_now(),
            chunk_schema_version=CHUNK_SCHEMA_VERSION,
        ))
    return chunks


def content_hash_normalized(content: str) -> str:
    return "sha256:" + hashlib.sha256(normalize_text(content).encode("utf-8")).hexdigest()


def normalize_text(content: str) -> str:
    lines = content.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    return "\n".join(line.rstrip() for line in lines).strip()


def deterministic_embedding(text: str, dimension: int = DEFAULT_EMBEDDING_DIMENSION) -> list[float]:
    normalized = normalize_text(text).lower()
    values = [0.0] * dimension
    tokens = [token for token in normalized.replace("_", " ").replace("-", " ").split() if token]
    for token in tokens or [normalized]:
        digest = hashlib.sha256(token.encode("utf-8")).digest()
        bucket = int.from_bytes(digest[:4], "big") % dimension
        sign = 1.0 if digest[4] % 2 == 0 else -1.0
        values[bucket] += sign
    norm = math.sqrt(sum(value * value for value in values))
    if norm == 0:
        return values
    return [round(value / norm, 8) for value in values]


def lexical_score(query: str, text: str) -> float:
    query_terms = set(normalize_text(query).lower().split())
    text_terms = set(normalize_text(text).lower().split())
    if not query_terms or not text_terms:
        return 0.0
    return len(query_terms.intersection(text_terms)) / len(query_terms)


def cosine_similarity(first: list[float], second: list[float]) -> float:
    if not first or not second or len(first) != len(second):
        return 0.0
    dot = sum(a * b for a, b in zip(first, second))
    first_norm = math.sqrt(sum(a * a for a in first))
    second_norm = math.sqrt(sum(b * b for b in second))
    if first_norm == 0 or second_norm == 0:
        return 0.0
    return dot / (first_norm * second_norm)


def _now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
