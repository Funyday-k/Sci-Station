from __future__ import annotations

from dataclasses import dataclass, field
from typing import Literal


Intent = Literal["paper_reading", "related_work", "gap_planning", "general"]


@dataclass
class SciStationAgentState:
    run_id: str
    user_goal: str
    thread_id: str | None = None
    project_id: str | None = None
    selected_paper_id: str | None = None
    intent: Intent | None = None
    messages: list[dict] = field(default_factory=list)
    evidence: list[dict] = field(default_factory=list)
    draft_artifacts: list[dict] = field(default_factory=list)
    pending_approval: dict | None = None
    final_response: str | None = None
