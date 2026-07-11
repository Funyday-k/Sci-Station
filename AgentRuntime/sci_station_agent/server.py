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
from .graph.paper_reading import draft_paper_reading_note
from .graph.related_work import draft_related_work_production
from .graph.router import route_intent
from .rag.evidence import stable_evidence_id
from .rag.fts_index import FTSIndex, ResourceDocument, content_hash
from .rag.retriever import FTSRetriever, build_retrieval_trace
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
        enabled_workflow_ids = self._enabled_workflow_ids(params)
        if enabled_workflow_ids is not None and intent in {"paper_reading", "related_work", "gap_planning"} and intent not in enabled_workflow_ids:
            self.pending_actions = self._workflow_disabled_actions(params, intent, enabled_workflow_ids)
            return
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

        evidence_provenance: JsonDict = {"contains_synthetic_evidence": False, "sources": ["workspace"]}
        if intent == "paper_reading":
            relative_path = f"library/papers/{selected_paper_id}/paper.md"
            paper_text = self._read_workspace_text(workspace_root, relative_path)
            if paper_text is None:
                return self._insufficient_evidence_actions(
                    params,
                    intent,
                    f"Missing workspace paper text at {relative_path}; convert/OCR the paper before running production paper reading.",
                    missing_sources=[relative_path],
                )
            source_hash = content_hash(paper_text)
            draft = draft_paper_reading_note(run_id, selected_paper_id, paper_text, relative_path, source_hash)
            artifact = draft.artifact
            evidence = draft.evidence
            critic_report = draft.critic_report or {"can_request_approval": False, "required_revisions": ["Paper text needs conversion before final approval."]}
            extra = {"needs_conversion": draft.needs_conversion}
        elif intent == "related_work":
            evidence = self._workspace_evidence(workspace_root, query=goal or "related work retrieval workflow evaluation", project_id=project_id)
            if not evidence:
                return self._insufficient_evidence_actions(
                    params,
                    intent,
                    "No real workspace evidence matched the related-work query; index project wiki or paper markdown before drafting.",
                )
            draft = draft_related_work_production(run_id, project_id, evidence)
            artifact = draft.artifact
            critic_report = draft.critic_report
            extra = {"evidence_matrix": draft.evidence_matrix}
        elif intent == "gap_planning":
            evidence = self._workspace_evidence(workspace_root, query=goal or "research gaps planning evidence", project_id=project_id)
            if not evidence:
                return self._insufficient_evidence_actions(
                    params,
                    intent,
                    "No real workspace evidence matched the gap-planning query; index project wiki or paper markdown before planning.",
                )
            draft = draft_gap_planning_production(run_id, project_id, evidence)
            artifact = draft.artifact
            critic_report = draft.critic_report
            extra = {"todo_drafts": draft.todo_drafts, "duplicate_warnings": draft.duplicate_warnings}
        else:
            return self._insufficient_evidence_actions(params, intent, f"Workflow '{intent}' is not a production sidecar workflow.")

        retrieval_trace = build_retrieval_trace(
            query=goal,
            retrieval_mode="fts_only",
            embedding_store="fts_only",
            fallback_reason="embedding disabled or unavailable; production workflow used FTS-only real workspace evidence",
            candidates=[self._trace_candidate_from_evidence(row) for row in evidence],
        )
        retrieval_trace.update({
            "run_id": run_id,
            "runtime": "langgraph_sidecar",
            "requested_runtime": str(params.get("runtimeSelection") or params.get("runtime_selection") or "langgraph_sidecar"),
            "effective_runtime": "langgraph_sidecar",
            "workflow": intent,
            "retriever": "fts_only_workspace",
            "evidence_count": len(evidence),
            "fallback_metadata": {
                "reason": retrieval_trace.get("fallback_reason"),
                "effective_runtime": "langgraph_sidecar",
                "used_synthetic_evidence": evidence_provenance["contains_synthetic_evidence"],
            },
            "evidence_provenance": evidence_provenance,
            "provenance": self._run_provenance(params, intent, evidence_provenance),
        })
        self._write_workflow_files(run_directory, critic_report, retrieval_trace, evidence, {**extra, "provenance": evidence_provenance})
        final = f"LangGraph sidecar completed {intent} with real workspace evidence and produced an approval-ready artifact draft."
        return self._workflow_events(run_id, goal, intent, artifact, final, retrieval_trace["provenance"])

    def _insufficient_evidence_actions(
        self,
        params: JsonDict,
        intent: str,
        reason: str,
        missing_sources: list[str] | None = None,
    ) -> list[JsonDict]:
        run_id = str(params.get("runID") or params.get("run_id") or "agent-run")
        goal = str(params.get("goal", ""))
        workspace_root = Path(str(params.get("workspaceRoot") or params.get("workspace_root") or ".")).expanduser()
        run_directory = workspace_root / ".sci-station" / "agent" / "runs" / run_id
        evidence_provenance: JsonDict = {
            "contains_synthetic_evidence": False,
            "sources": [],
            "missing_sources": missing_sources or [],
        }
        retrieval_trace = build_retrieval_trace(
            query=goal,
            retrieval_mode="fts_only",
            embedding_store="fts_only",
            fallback_reason=reason,
            candidates=[],
        )
        retrieval_trace.update({
            "run_id": run_id,
            "runtime": "langgraph_sidecar",
            "requested_runtime": str(params.get("runtimeSelection") or params.get("runtime_selection") or "langgraph_sidecar"),
            "effective_runtime": "langgraph_sidecar",
            "workflow": intent,
            "retriever": "fts_only_workspace",
            "evidence_count": 0,
            "fallback_metadata": {
                "reason": reason,
                "effective_runtime": "langgraph_sidecar",
                "used_synthetic_evidence": False,
            },
            "evidence_provenance": evidence_provenance,
            "provenance": self._run_provenance(params, intent, evidence_provenance, fallback_reason=reason),
        })
        critic_report = {
            "schema_version": 1,
            "can_request_approval": False,
            "required_revisions": [reason],
            "evidence_count": 0,
        }
        self._write_workflow_files(run_directory, critic_report, retrieval_trace, [], {"provenance": evidence_provenance})
        final = f"LangGraph sidecar could not produce a production {intent} draft: {reason} No synthetic/sample evidence was used."
        return self._workflow_events(run_id, goal, intent, None, final, retrieval_trace["provenance"])

    def _enabled_workflow_ids(self, params: JsonDict) -> set[str] | None:
        raw = params.get("enabledWorkflowIDs")
        if raw is None:
            raw = params.get("enabled_workflow_ids")
        if raw is None:
            return None
        if isinstance(raw, str):
            return {item.strip() for item in raw.split(",") if item.strip()}
        if isinstance(raw, (list, tuple, set)):
            return {str(item) for item in raw if str(item)}
        return set()

    def _workflow_disabled_actions(self, params: JsonDict, intent: str, enabled_workflow_ids: set[str]) -> list[JsonDict]:
        run_id = str(params.get("runID") or params.get("run_id") or "agent-run")
        goal = str(params.get("goal", ""))
        timestamp = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
        enabled_summary = ", ".join(sorted(enabled_workflow_ids)) or "none"
        final = f"Workflow '{intent}' is disabled by the workspace module registry. Enabled workflows: {enabled_summary}. No artifact was generated."
        return [
            {"kind": "event", "envelope": self._envelope(f"evt-{run_id}-start", run_id, 10, timestamp, "run_started", {"goal": goal})},
            {"kind": "event", "envelope": self._envelope(f"evt-{run_id}-router", run_id, 20, timestamp, "node_started", {"name": f"router:{intent}:disabled"})},
            {"kind": "event", "envelope": self._envelope(f"evt-{run_id}-final", run_id, 30, timestamp, "final_response", {"markdown": final, "workflow": intent, "enabled_workflows": sorted(enabled_workflow_ids)})},
        ]

    def _write_workflow_files(self, run_directory: Path, critic_report: JsonDict, retrieval_trace: JsonDict, evidence: list[JsonDict], extra: JsonDict) -> None:
        run_directory.mkdir(parents=True, exist_ok=True)
        (run_directory / "critic_report.json").write_text(json.dumps(critic_report, sort_keys=True, indent=2), encoding="utf-8")
        (run_directory / "retrieval_trace.json").write_text(json.dumps(retrieval_trace, sort_keys=True, indent=2), encoding="utf-8")
        (run_directory / "evidence.json").write_text(json.dumps({"evidence": evidence, **extra}, sort_keys=True, indent=2), encoding="utf-8")

    def _workflow_events(self, run_id: str, goal: str, intent: str, artifact: JsonDict | None, final_markdown: str, provenance: JsonDict | None = None) -> list[JsonDict]:
        timestamp = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
        runtime_payload = {key: value for key, value in (provenance or {}).items() if key in {"requested_runtime", "effective_runtime", "fallback_reason", "evidence_provenance"}}
        events = [
            {"kind": "event", "envelope": self._envelope(f"evt-{run_id}-start", run_id, 10, timestamp, "run_started", {"goal": goal, **runtime_payload})},
            {"kind": "event", "envelope": self._envelope(f"evt-{run_id}-router", run_id, 20, timestamp, "node_started", {"name": f"router:{intent}"})},
            {"kind": "event", "envelope": self._envelope(f"evt-{run_id}-final", run_id, 40, timestamp, "final_response", {"markdown": final_markdown})},
        ]
        if artifact is not None:
            events.insert(2, {"kind": "event", "envelope": self._envelope(f"evt-{run_id}-draft", run_id, 30, timestamp, "artifact_draft", artifact)})
        return events

    def _run_provenance(self, params: JsonDict, workflow: str, evidence_provenance: JsonDict, fallback_reason: str | None = None) -> JsonDict:
        requested_runtime = str(params.get("runtimeSelection") or params.get("runtime_selection") or "langgraph_sidecar")
        return {
            "schema_version": 1,
            "runtime": "langgraph_sidecar",
            "requested_runtime": requested_runtime,
            "effective_runtime": "langgraph_sidecar",
            "workflow": workflow,
            "sidecar_version": __version__,
            "python_version": platform.python_version(),
            "fallback_reason": fallback_reason,
            "evidence_provenance": evidence_provenance,
        }

    def _read_workspace_text(self, workspace_root: Path, relative_path: str) -> str | None:
        path = workspace_root / relative_path
        try:
            if path.exists() and path.is_file():
                return path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            return None
        return None

    def _workspace_evidence(self, workspace_root: Path, query: str, project_id: str, limit: int = 8) -> list[JsonDict]:
        documents = self._workspace_documents(workspace_root, project_id)
        if not documents:
            return []
        index = FTSIndex(workspace_root / ".sci-station" / "agent" / "sidecar_fts.sqlite3")
        index.index_documents(documents)
        terms = " OR ".join(self._fts_terms(query))
        evidence = FTSRetriever(index).retrieve(terms, limit=limit)
        return evidence

    def _workspace_documents(self, workspace_root: Path, project_id: str) -> list[ResourceDocument]:
        candidates: list[Path] = []
        for relative_root in ("library/papers", f"projects/{project_id}", "wiki"):
            root = workspace_root / relative_root
            if root.exists():
                candidates.extend(path for path in root.rglob("*.md") if path.is_file())
        documents: list[ResourceDocument] = []
        for path in sorted(set(candidates)):
            try:
                content = path.read_text(encoding="utf-8")
            except UnicodeDecodeError:
                continue
            if not content.strip():
                continue
            relative_path = path.relative_to(workspace_root).as_posix()
            source_type = "paper" if relative_path.startswith("library/papers/") else "wiki"
            source_id = self._source_id_from_relative_path(relative_path, source_type)
            documents.append(ResourceDocument(
                resource_id=f"{source_type}:{source_id or relative_path}",
                relative_path=relative_path,
                source_type=source_type,
                source_id=source_id,
                content=content,
                content_hash=content_hash(content),
            ))
        return documents

    def _source_id_from_relative_path(self, relative_path: str, source_type: str) -> str | None:
        parts = relative_path.split("/")
        if source_type == "paper" and len(parts) >= 3:
            return parts[2]
        if source_type == "wiki":
            return relative_path.removesuffix(".md")
        return None

    def _fts_terms(self, query: str) -> list[str]:
        normalized = "".join(character.lower() if character.isalnum() else " " for character in query)
        stopwords = {"the", "and", "for", "with", "this", "that", "please", "draft", "create"}
        terms = [term for term in normalized.split() if len(term) >= 3 and term not in stopwords]
        fallback = ["retrieval", "workflow", "evidence", "evaluation", "planning", "method"]
        selected: list[str] = []
        for term in terms + fallback:
            if term not in selected:
                selected.append(term)
            if len(selected) >= 8:
                break
        return selected or fallback

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
