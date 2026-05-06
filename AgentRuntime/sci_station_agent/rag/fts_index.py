from __future__ import annotations

import hashlib
import sqlite3
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

SCHEMA_VERSION = 1


@dataclass(frozen=True)
class ResourceDocument:
    resource_id: str
    relative_path: str
    source_type: str
    source_id: str | None
    content: str
    content_hash: str | None = None
    updated_at: str | None = None
    parser_hint: str = "markdown"


def content_hash(content: str) -> str:
    return "sha256:" + hashlib.sha256(normalize_content(content).encode("utf-8")).hexdigest()


def normalize_content(content: str) -> str:
    lines = content.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    return "\n".join(line.rstrip() for line in lines).strip()


class FTSIndex:
    def __init__(self, database_path: str | Path, schema_version: int = SCHEMA_VERSION) -> None:
        self.database_path = Path(database_path)
        self.schema_version = schema_version

    def rebuild_if_needed(self) -> bool:
        self.database_path.parent.mkdir(parents=True, exist_ok=True)
        with sqlite3.connect(self.database_path) as connection:
            existing = self._metadata_version(connection)
            if existing != self.schema_version:
                self._drop_schema(connection)
                self._create_schema(connection)
                return True
            self._create_schema(connection)
            return False

    def index_documents(self, documents: list[ResourceDocument]) -> None:
        self.rebuild_if_needed()
        with sqlite3.connect(self.database_path) as connection:
            for document in documents:
                doc_hash = document.content_hash or content_hash(document.content)
                connection.execute("DELETE FROM chunks WHERE relative_path = ? AND content_hash != ?", (document.relative_path, doc_hash))
                if connection.execute("SELECT 1 FROM chunks WHERE relative_path = ? AND content_hash = ? LIMIT 1", (document.relative_path, doc_hash)).fetchone():
                    continue
                chunks = chunk_markdown(document)
                for chunk in chunks:
                    connection.execute(
                        "INSERT INTO chunks (chunk_id, schema_version, source_type, source_id, relative_path, heading, start_line, end_line, text, content_hash, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                        (
                            chunk["chunk_id"],
                            self.schema_version,
                            document.source_type,
                            document.source_id,
                            document.relative_path,
                            chunk["heading"],
                            chunk["start_line"],
                            chunk["end_line"],
                            chunk["text"],
                            doc_hash,
                            document.updated_at or _now(),
                        ),
                    )

    def search(self, query: str, limit: int = 10, source_type: str | None = None) -> list[dict]:
        self.rebuild_if_needed()
        with sqlite3.connect(self.database_path) as connection:
            connection.row_factory = sqlite3.Row
            where = "chunks_fts MATCH ?"
            params: list[object] = [query]
            if source_type:
                where += " AND source_type = ?"
                params.append(source_type)
            rows = connection.execute(
                f"SELECT chunk_id, source_type, source_id, relative_path, heading, start_line, end_line, text, content_hash, updated_at FROM chunks_fts WHERE {where} LIMIT ?",
                [*params, limit],
            ).fetchall()
            return [dict(row) for row in rows]

    def _metadata_version(self, connection: sqlite3.Connection) -> int | None:
        try:
            row = connection.execute("SELECT value FROM metadata WHERE key = 'schema_version'").fetchone()
            return int(row[0]) if row else None
        except sqlite3.DatabaseError:
            return None

    def _create_schema(self, connection: sqlite3.Connection) -> None:
        connection.execute("CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
        connection.execute("CREATE TABLE IF NOT EXISTS chunks (chunk_id TEXT PRIMARY KEY, schema_version INTEGER NOT NULL, source_type TEXT NOT NULL, source_id TEXT, relative_path TEXT NOT NULL, heading TEXT, start_line INTEGER NOT NULL, end_line INTEGER NOT NULL, text TEXT NOT NULL, content_hash TEXT NOT NULL, updated_at TEXT NOT NULL)")
        connection.execute("CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts USING fts5(chunk_id UNINDEXED, source_type UNINDEXED, source_id UNINDEXED, relative_path UNINDEXED, heading, start_line UNINDEXED, end_line UNINDEXED, text, content_hash UNINDEXED, updated_at UNINDEXED, content='chunks', content_rowid='rowid')")
        connection.execute("CREATE TRIGGER IF NOT EXISTS chunks_ai AFTER INSERT ON chunks BEGIN INSERT INTO chunks_fts(rowid, chunk_id, source_type, source_id, relative_path, heading, start_line, end_line, text, content_hash, updated_at) VALUES (new.rowid, new.chunk_id, new.source_type, new.source_id, new.relative_path, new.heading, new.start_line, new.end_line, new.text, new.content_hash, new.updated_at); END")
        connection.execute("CREATE TRIGGER IF NOT EXISTS chunks_ad AFTER DELETE ON chunks BEGIN INSERT INTO chunks_fts(chunks_fts, rowid, chunk_id, source_type, source_id, relative_path, heading, start_line, end_line, text, content_hash, updated_at) VALUES('delete', old.rowid, old.chunk_id, old.source_type, old.source_id, old.relative_path, old.heading, old.start_line, old.end_line, old.text, old.content_hash, old.updated_at); END")
        connection.execute("INSERT OR REPLACE INTO metadata(key, value) VALUES('schema_version', ?)", (str(self.schema_version),))

    def _drop_schema(self, connection: sqlite3.Connection) -> None:
        connection.execute("DROP TRIGGER IF EXISTS chunks_ai")
        connection.execute("DROP TRIGGER IF EXISTS chunks_ad")
        connection.execute("DROP TABLE IF EXISTS chunks_fts")
        connection.execute("DROP TABLE IF EXISTS chunks")
        connection.execute("DROP TABLE IF EXISTS metadata")


def chunk_markdown(document: ResourceDocument, max_lines: int = 80) -> list[dict]:
    lines = document.content.splitlines()
    chunks: list[dict] = []
    heading = ""
    heading_path: list[str] = []
    start = 1
    buffer: list[str] = []
    for index, line in enumerate(lines, start=1):
        if line.startswith("#"):
            if buffer:
                chunks.append(_chunk(document, heading, heading_path, start, index - 1, buffer))
                buffer = []
            level = len(line) - len(line.lstrip("#"))
            heading = line.lstrip("#").strip() or heading
            if heading:
                heading_path = heading_path[: max(level - 1, 0)] + [heading]
            start = index
        buffer.append(line)
        if len(buffer) >= max_lines:
            chunks.append(_chunk(document, heading, heading_path, start, index, buffer))
            buffer = []
            start = index + 1
    if buffer:
        chunks.append(_chunk(document, heading, heading_path, start, len(lines), buffer))
    return chunks


def _chunk(document: ResourceDocument, heading: str, heading_path: list[str], start_line: int, end_line: int, lines: list[str]) -> dict:
    return {
        "chunk_id": f"{document.resource_id}:{start_line}-{end_line}",
        "heading": heading,
        "heading_path": heading_path,
        "start_line": start_line,
        "end_line": end_line,
        "text": "\n".join(lines).strip(),
    }


def _now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
