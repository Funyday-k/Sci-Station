from __future__ import annotations

import copy
import json
import platform
import sqlite3
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from . import __version__
from .graph.gap_planning import draft_gap_planning_production
from .graph.paper_reading import build_sample_paper_reading_events, draft_paper_reading_note
from .graph.related_work import draft_related_work_production
from .graph.router import route_intent
from .rag.evidence import stable_evidence_id
from .rag.fts_index import content_hash
from .rag.retriever import build_retrieval_trace
from .transport.schemas import JsonDict, load_fixture
from .transport.stdio_jsonrpc import StdioJsonRpcTransport

PROTOCOL_VERSION = "1.0"
SCHEMA_VERSION = 1


class SidecarServer:
    def __init__(self, fixture_path: Path | None = None, development_mode: bool = False) -> None:
        self.fixture_path = fixture_path
        self.development_mode = development_mode
        self.fixture = load_fixture(fixture_path) if fixture_path else None
        self.pending_actions: list[JsonDict] = []
        self.resume_actions: list[JsonDict] = []
        self.current_run: JsonDict = {}
        self.initialized = False

    def handle(self, message: JsonDict) -> JsonDict | None:
        method = message.get("method")
        request_id = message.get("id")
        params = message.get("params") or {}
        if not method:
            return None

        try:
            if method == "sidecar.initialize":
                return self._response(request_id, self._initialize(params))
            if method == "sidecar.health":
                return self._response(request_id, self._health())
            if method == "sidecar.initialized":
                return self._response(request_id, {"acknowledged": True})
            if method == "agent.start":
                self._start(params)
                return self._response(request_id, {"accepted": True})
            if method == "agent.resume":
                self._resume(params)
                return self._response(request_id, {"accepted": True})
            if method == "agent.cancel":
                self.pending_actions = []
                self.resume_actions = []
                return self._response(request_id, {"cancelled": True})
            if method == "agent.checkpoint":
                return self._response(request_id, self._checkpoint(params))
            return self._error(request_id, -32601, f"Unsupported method: {method}")
        except Exception as exc:  # pragma: no cover - defensive transport boundary
            return self._error(request_id, -32603, str(exc))

    def flush_notifications(self, transport: StdioJsonRpcTransport) -> None:
        while self.pending_actions:
            action = self.pending_actions.pop(0)
            kind = action.get("kind")
            if kind == "event":
                transport.send_notification("runtime.event", self._rewrite_envelope(action["envelope"]))
            elif kind == "wait_for_resume":
                self.resume_actions = self.pending_actions
                self.pending_actions = []
                return
            elif kind == "sleep":
                time.sleep(float(action.get("seconds", 0)))
            elif kind == "crash":
                print("Sci-Station sidecar fixture requested crash.", file=sys.stderr, flush=True)
                raise SystemExit(int(action.get("exit_code", 42)))

    def _initialize(self, params: JsonDict) -> JsonDict:
        if self.fixture and self.fixture.meta.get("mode") == "handshake_timeout":
            time.sleep(60)
        protocol_version = params.get("protocolVersion") or params.get("protocol_version")
        schema_version = params.get("schemaVersion") or params.get("schema_version")
        if protocol_version != PROTOCOL_VERSION or schema_version != SCHEMA_VERSION:
            raise ValueError("Incompatible protocolVersion or schemaVersion")
        self.initialized = True
        dependencies = self._dependency_status()
        return {
            "protocolVersion": PROTOCOL_VERSION,
            "schemaVersion": SCHEMA_VERSION,
            "sidecarVersion": __version__,
            "capabilities": {
                "paperReading": True,
                "relatedWork": True,
                "gapPlanning": True,
                "citationCritic": True,
                "runReplay": True,
                "hybridRetrieval": True,
                "mcpGateway": True,
                "llmProxy": True,
                "approvalResume": True,
                "ftsIndex": True,
                "embeddingRetrieval": True,
            },
            "dependencies": dependencies,
            "workspaceAccepted": bool(params.get("workspaceRoot") or params.get("workspace_root")),
        }

    def _health(self) -> JsonDict:
        return {
            "status": "ready" if self.initialized else "starting",
            "protocolVersion": PROTOCOL_VERSION,
            "schemaVersion": SCHEMA_VERSION,
            "sidecarVersion": __version__,
            "dependencies": self._dependency_status(),
            "pythonVersion": platform.python_version(),
            "protocolSchemaVersion": f"{PROTOCOL_VERSION}/{SCHEMA_VERSION}",
            "lastCrash": None,
            "fallbackReason": None,
        }

    def _start(self, params: JsonDict) -> None:
        self.current_run = dict(params)
        if self.fixture:
            self.pending_actions = list(self.fixture.actions)
            return
        intent = route_intent({
            "user_goal": str(params.get("goal", "")),
            "selected_paper_id": params.get("selectedPaperID") or params.get("selected_paper_id"),
            "project_id": params.get("projectID") or params.get("project_id"),
        })
        self.pending_actions = self._build_production_actions(params, intent)

    def _resume(self, params: JsonDict) -> None:
        self.current_run.update(params)
        if self.resume_actions:
            self.pending_actions = self.resume_actions
            self.resume_actions = []
        elif self.fixture:
            actions = list(self.fixture.actions)
            for index, action in enumerate(actions):
                if action.get("kind") == "wait_for_resume":
                    self.pending_actions = actions[index + 1 :]
                    break

    def _checkpoint(self, params: JsonDict) -> JsonDict:
        return {
            "run_id": params.get("runID") or params.get("run_id") or self.current_run.get("runID") or self.current_run.get("run_id"),
            "state": "waiting_for_approval" if self.resume_actions else "running",
        }

    def _build_production_actions(self, params: JsonDict, intent: str) -> list[JsonDict]:
        run_id = str(params.get("runID") or params.get("run_id") or "agent-run")
        goal = str(params.get("goal", ""))
        workspace_root = Path(str(params.get("workspaceRoot") or params.get("workspace_root") or ".")).expanduser()
        run_directory = workspace_root / ".sci-station" / "agent" / "runs" / run_id
        project_id = str(params.get("projectID") or params.get("project_id") or "main-project")
        selected_paper_id = str(params.get("selectedPaperID") or params.get("selected_paper_id") or "selected-paper")

        if intent == "paper_reading":
            relative_path = f"library/papers/{selected_paper_id}/paper.md"
            paper_text = self._read_workspace_text(workspace_root, relative_path) or self._synthetic_paper_text(selected_paper_id)
            source_hash = content_hash(paper_text)
            draft = draft_paper_reading_note(run_id, selected_paper_id, paper_text, relative_path, source_hash)
            artifact = draft.artifact
            evidence = draft.evidence
            critic_report = draft.critic_report or {"can_request_approval": False, "required_revisions": ["Paper text needs conversion before final approval."]}
            extra = {"needs_conversion": draft.needs_conversion}
        elif intent == "related_work":
            evidence = self._sample_evidence_table()
            draft = draft_related_work_production(run_id, project_id, evidence)
            artifact = draft.artifact
            critic_report = draft.critic_report
            extra = {"evidence_matrix": draft.evidence_matrix}
        elif intent == "gap_planning":
            evidence = self._sample_evidence_table()
            draft = draft_gap_planning_production(run_id, project_id, evidence)
            artifact = draft.artifact
            critic_report = draft.critic_report
            extra = {"todo_drafts": draft.todo_drafts, "duplicate_warnings": draft.duplicate_warnings}
        else:
            return build_sample_paper_reading_events(run_id=run_id, goal=goal, intent=intent)

        retrieval_trace = build_retrieval_trace(
            query=goal,
            retrieval_mode="fts_only" if intent == "paper_reading" else "synthetic_fixture",
            embedding_store="fts_only",
            fallback_reason="embedding disabled or unavailable; production workflow used FTS/synthetic evidence",
            candidates=[self._trace_candidate_from_evidence(row) for row in evidence],
        )
        retrieval_trace.update({
            "run_id": run_id,
            "runtime": "langgraph_sidecar",
            "workflow": intent,
            "retriever": "fts_or_synthetic_fixture",
            "evidence_count": len(evidence),
            "fallback_metadata": {"used_synthetic_evidence": intent in {"related_work", "gap_planning"}},
        })
        self._write_workflow_files(run_directory, critic_report, retrieval_trace, evidence, extra)
        final = f"LangGraph sidecar completed {intent} and produced an approval-ready artifact draft."
        return self._workflow_events(run_id, goal, intent, artifact, final)

    def _write_workflow_files(self, run_directory: Path, critic_report: JsonDict, retrieval_trace: JsonDict, evidence: list[JsonDict], extra: JsonDict) -> None:
        run_directory.mkdir(parents=True, exist_ok=True)
        (run_directory / "critic_report.json").write_text(json.dumps(critic_report, sort_keys=True, indent=2), encoding="utf-8")
        (run_directory / "retrieval_trace.json").write_text(json.dumps(retrieval_trace, sort_keys=True, indent=2), encoding="utf-8")
        (run_directory / "evidence.json").write_text(json.dumps({"evidence": evidence, **extra}, sort_keys=True, indent=2), encoding="utf-8")

    def _workflow_events(self, run_id: str, goal: str, intent: str, artifact: JsonDict, final_markdown: str) -> list[JsonDict]:
        timestamp = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
        return [
            {"kind": "event", "envelope": self._envelope(f"evt-{run_id}-start", run_id, 10, timestamp, "run_started", {"goal": goal})},
            {"kind": "event", "envelope": self._envelope(f"evt-{run_id}-router", run_id, 20, timestamp, "node_started", {"name": f"router:{intent}"})},
            {"kind": "event", "envelope": self._envelope(f"evt-{run_id}-draft", run_id, 30, timestamp, "artifact_draft", artifact)},
            {"kind": "event", "envelope": self._envelope(f"evt-{run_id}-final", run_id, 40, timestamp, "final_response", {"markdown": final_markdown})},
        ]

    def _read_workspace_text(self, workspace_root: Path, relative_path: str) -> str | None:
        path = workspace_root / relative_path
        try:
            if path.exists() and path.is_file():
                return path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            return None
        return None

    def _synthetic_paper_text(self, paper_id: str) -> str:
        return "\n".join(
            f"Line {line} for {paper_id}: retrieval workflow method experiment limitation evidence."
            for line in range(1, 90)
        )

    def _sample_evidence_table(self) -> list[JsonDict]:
        rows: list[JsonDict] = []
        themes = [
            ("retrieval", "retrieval RAG index search evidence"),
            ("retrieval", "retrieval search ranking evidence"),
            ("workflow", "agent workflow orchestration planning evidence"),
            ("workflow", "workflow planning checkpoint evidence"),
            ("evaluation", "evaluation benchmark experiment metric evidence"),
            ("evaluation", "experiment metric comparison evidence"),
        ]
        timestamp = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
        for index, (heading, quote) in enumerate(themes, start=1):
            relative_path = f"library/papers/p{index}/paper.md"
            source_hash = f"sha256:{index}"
            evidence_id = stable_evidence_id("paper", f"p{index}", relative_path, 1, 8, source_hash)
            rows.append({
                "id": evidence_id,
                "source_type": "paper",
                "source_id": f"p{index}",
                "relative_path": relative_path,
                "lines": [1, 8],
                "source_hash": source_hash,
                "chunk_id": f"paper:p{index}:1-8",
                "retrieved_at": timestamp,
                "heading": heading,
                "quote": quote,
                "confidence": 0.74,
            })
        return rows

    def _trace_candidate_from_evidence(self, evidence: JsonDict) -> JsonDict:
        lines = evidence.get("lines") if isinstance(evidence.get("lines"), list) else [None, None]
        return {
            "source_path": evidence.get("relative_path"),
            "chunk_id": evidence.get("chunk_id"),
            "fts_score": evidence.get("confidence", 0.7),
            "embedding_score": None,
            "rerank_score": evidence.get("confidence", 0.7),
            "rerank_reason": "keyword/source evidence fallback",
            "dedupe_reason": None,
            "source_hash_status": "fresh",
            "line_start": lines[0] if len(lines) > 0 else None,
            "line_end": lines[1] if len(lines) > 1 else None,
            "pdf_page": evidence.get("pdf_page"),
        }

    def _envelope(self, event_id: str, run_id: str, sequence: int, timestamp: str, event_type: str, payload: JsonDict) -> JsonDict:
        return {
            "id": event_id,
            "schema_version": SCHEMA_VERSION,
            "run_id": run_id,
            "sequence": sequence,
            "timestamp": timestamp,
            "event": {"type": event_type, "payload": payload},
        }

    def _rewrite_envelope(self, envelope: JsonDict) -> JsonDict:
        rewritten = copy.deepcopy(envelope)
        run_id = self.current_run.get("runID") or self.current_run.get("run_id") or rewritten.get("run_id")
        thread_id = self.current_run.get("threadID") or self.current_run.get("thread_id") or rewritten.get("thread_id")
        goal = self.current_run.get("goal", "")
        self._replace_placeholders(rewritten, {"${run_id}": str(run_id), "${thread_id}": str(thread_id or ""), "${goal}": str(goal)})
        rewritten["run_id"] = str(run_id)
        if thread_id:
            rewritten["thread_id"] = str(thread_id)
        event = rewritten.get("event", {})
        payload = event.get("payload", {}) if isinstance(event, dict) else {}
        if isinstance(payload, dict):
            for key in ("run_id", "runID"):
                if key in payload:
                    payload[key] = str(run_id)
            if event.get("type") == "approval_required":
                payload["run_id"] = str(run_id)
            if event.get("type") == "artifact_draft":
                payload["run_id"] = str(run_id)
            if event.get("type") == "checkpoint_saved":
                payload["run_id"] = str(run_id)
        return rewritten

    def _replace_placeholders(self, value: Any, replacements: dict[str, str]) -> None:
        if isinstance(value, dict):
            for key, item in value.items():
                if isinstance(item, str):
                    for old, new in replacements.items():
                        item = item.replace(old, new)
                    value[key] = item
                else:
                    self._replace_placeholders(item, replacements)
        elif isinstance(value, list):
            for item in value:
                self._replace_placeholders(item, replacements)

    def _dependency_status(self) -> JsonDict:
        try:
            import langgraph  # type: ignore  # noqa: F401

            langgraph_available = True
        except Exception:
            langgraph_available = False
        sqlite_vec_available = False
        try:
            connection = sqlite3.connect(":memory:")
            try:
                connection.enable_load_extension(True)
                connection.load_extension("sqlite_vec")
                sqlite_vec_available = True
            finally:
                connection.close()
        except Exception:
            sqlite_vec_available = False
        return {
            "python": True,
            "langgraph": langgraph_available,
            "sqlite3": True,
            "sqlite_vec": sqlite_vec_available,
        }

    def _response(self, request_id: object, result: JsonDict) -> JsonDict:
        return {"jsonrpc": "2.0", "id": request_id, "result": result}

    def _error(self, request_id: object, code: int, message: str) -> JsonDict:
        return {"jsonrpc": "2.0", "id": request_id, "error": {"code": code, "message": message}}
