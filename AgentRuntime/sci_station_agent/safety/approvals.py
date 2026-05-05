from __future__ import annotations


WRITE_RISKS = {"writesWorkspace", "externalSideEffect", "modifiesMetadata", "runsCode", "destructive", "credentialAccess"}


def requires_approval(action: dict) -> bool:
    return str(action.get("risk", "readOnly")) in WRITE_RISKS


def approval_interrupt(run_id: str, actions: list[dict]) -> dict | None:
    risky = [action for action in actions if requires_approval(action)]
    if not risky:
        return None
    return {"type": "approval_required", "run_id": run_id, "actions": risky}
