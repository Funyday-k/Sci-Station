from __future__ import annotations

from .state import Intent


def route_intent(state: dict) -> Intent:
    goal = str(state.get("user_goal") or "").lower()
    selected_paper_id = state.get("selected_paper_id")
    project_id = state.get("project_id")

    if selected_paper_id and any(keyword in goal for keyword in [
        "精读",
        "paper note",
        "structured note",
        "结构化笔记",
        "formula",
        "equation",
        "evaporation rate",
        "公式",
        "方程",
        "蒸发率",
        "正文",
        "章节",
        "引用",
        "来源",
    ]):
        return "paper_reading"
    if project_id and any(keyword in goal for keyword in ["related work", "相关工作", "综述"]):
        return "related_work"
    if project_id and any(keyword in goal for keyword in ["gap", "research gaps", "下一步", "拆任务", "research plan"]):
        return "gap_planning"
    return "general"
