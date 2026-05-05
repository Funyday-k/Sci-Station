from __future__ import annotations

import copy
import json
import sys
import time
from pathlib import Path
from typing import Any

from . import __version__
from .graph.paper_reading import build_sample_paper_reading_events
from .graph.router import route_intent
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
                "mcpGateway": True,
                "llmProxy": True,
                "approvalResume": True,
                "ftsIndex": True,
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
        self.pending_actions = build_sample_paper_reading_events(
            run_id=str(params.get("runID") or params.get("run_id") or "agent-run"),
            goal=str(params.get("goal", "")),
            intent=intent,
        )

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
        return {
            "python": True,
            "langgraph": langgraph_available,
            "sqlite3": True,
        }

    def _response(self, request_id: object, result: JsonDict) -> JsonDict:
        return {"jsonrpc": "2.0", "id": request_id, "result": result}

    def _error(self, request_id: object, code: int, message: str) -> JsonDict:
        return {"jsonrpc": "2.0", "id": request_id, "error": {"code": code, "message": message}}
