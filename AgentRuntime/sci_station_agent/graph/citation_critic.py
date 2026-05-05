from __future__ import annotations

import re
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from typing import Iterable

EVIDENCE_TOKEN_RE = re.compile(r"\[evidence:([^\]]+)\]")
UNSUPPORTED_SUPERLATIVES = ("best", "significantly", "state-of-the-art", "sota", "novel", "first", "only")
CORE_SECTIONS = {
    "tl;dr",
    "contributions",
    "method",
    "methods",
    "experiments",
    "limitations",
    "open questions",
    "relevance to current project",
    "scope",
    "theme 1",
    "theme 2",
    "theme 3",
    "research gap summary",
    "current context",
    "candidate gaps",
    "hypotheses",
    "proposed experiments",
    "milestones",
}


@dataclass(frozen=True)
class CriticReport:
    unsupported_claims: list[dict] = field(default_factory=list)
    stale_evidence: list[dict] = field(default_factory=list)
    weak_evidence: list[dict] = field(default_factory=list)
    overclaims: list[dict] = field(default_factory=list)
    required_revisions: list[str] = field(default_factory=list)
    can_request_approval: bool = True

    def to_dict(self) -> dict:
        return {
            "unsupported_claims": self.unsupported_claims,
            "stale_evidence": self.stale_evidence,
            "weak_evidence": self.weak_evidence,
            "overclaims": self.overclaims,
            "required_revisions": self.required_revisions,
            "can_request_approval": self.can_request_approval,
        }


def critic_check_evidence(
    draft_artifact: dict,
    evidence_table: Iterable[dict],
    *,
    allowed_source_types: set[str] | None = None,
    current_source_hashes: dict[str, str] | None = None,
    source_line_counts: dict[str, int] | None = None,
    max_quote_characters: int = 500,
) -> CriticReport:
    evidence_by_id = {str(item.get("id")): item for item in evidence_table if item.get("id")}
    current_source_hashes = current_source_hashes or {}
    source_line_counts = source_line_counts or {}
    allowed_source_types = allowed_source_types or {"paper", "wiki", "project_wiki", "annotation", "material"}

    unsupported_claims: list[dict] = []
    stale_evidence: list[dict] = []
    weak_evidence: list[dict] = []
    overclaims: list[dict] = []
    required_revisions: list[str] = []
    evidence_use_count: Counter[str] = Counter()
    evidence_claims: defaultdict[str, list[str]] = defaultdict(list)

    for claim in _claim_lines(str(draft_artifact.get("content") or "")):
        evidence_ids = EVIDENCE_TOKEN_RE.findall(claim["text"])
        if claim["is_core"] and not evidence_ids:
            unsupported_claims.append({"line": claim["line"], "claim": claim["text"], "reason": "missing evidence token"})
            continue

        for evidence_id in evidence_ids:
            evidence_use_count[evidence_id] += 1
            evidence_claims[evidence_id].append(claim["text"])
            evidence = evidence_by_id.get(evidence_id)
            if evidence is None:
                unsupported_claims.append({"line": claim["line"], "claim": claim["text"], "evidence_id": evidence_id, "reason": "evidence id not found"})
                continue

            source_type = evidence.get("source_type")
            relative_path = str(evidence.get("relative_path") or "")
            lines = evidence.get("lines") or []
            start_line, end_line = _line_range(lines)
            if source_type not in allowed_source_types:
                required_revisions.append(f"Evidence {evidence_id} uses disallowed source type {source_type}.")
            if start_line <= 0 or end_line < start_line:
                required_revisions.append(f"Evidence {evidence_id} has an invalid line range.")
            elif relative_path in source_line_counts and end_line > source_line_counts[relative_path]:
                required_revisions.append(f"Evidence {evidence_id} points past the end of {relative_path}.")

            current_hash = current_source_hashes.get(relative_path)
            source_hash = evidence.get("source_hash")
            if current_hash and source_hash and current_hash != source_hash:
                stale_evidence.append({"evidence_id": evidence_id, "relative_path": relative_path, "expected_hash": source_hash, "current_hash": current_hash})

            quote = str(evidence.get("quote") or "")
            confidence = evidence.get("confidence")
            if len(quote) > max_quote_characters:
                required_revisions.append(f"Evidence {evidence_id} quote is too long for an auditable citation block.")
            if isinstance(confidence, (int, float)) and confidence < 0.55:
                weak_evidence.append({"evidence_id": evidence_id, "confidence": confidence, "claim": claim["text"]})

            lowered = claim["text"].lower()
            if any(term in lowered for term in UNSUPPORTED_SUPERLATIVES) and (not isinstance(confidence, (int, float)) or confidence < 0.85):
                overclaims.append({"line": claim["line"], "claim": claim["text"], "evidence_id": evidence_id, "reason": "unsupported superlative or strong causal language"})

    for evidence_id, count in evidence_use_count.items():
        if count > 3:
            overclaims.append({
                "evidence_id": evidence_id,
                "reason": "same evidence is reused for too many claims",
                "claim_count": count,
                "claims": evidence_claims[evidence_id][:4],
            })

    if unsupported_claims:
        required_revisions.append("Core scientific claims must cite evidence before final approval.")
    if overclaims:
        required_revisions.append("Overstated claims must be rewritten or downgraded to low confidence.")

    blockers = bool(unsupported_claims or required_revisions)
    return CriticReport(
        unsupported_claims=unsupported_claims,
        stale_evidence=stale_evidence,
        weak_evidence=weak_evidence,
        overclaims=overclaims,
        required_revisions=_dedupe(required_revisions),
        can_request_approval=not blockers,
    )


def attach_low_confidence_warning(draft_artifact: dict, report: CriticReport) -> dict:
    artifact = dict(draft_artifact)
    if report.can_request_approval and not (report.stale_evidence or report.weak_evidence):
        return artifact
    warning = "\n\n> Warning: saved as a low confidence draft because citation critic found evidence issues."
    content = str(artifact.get("content") or "")
    if "low confidence draft" not in content:
        artifact["content"] = content.rstrip() + warning + "\n"
    artifact["critic_report"] = report.to_dict()
    return artifact


def _claim_lines(content: str) -> list[dict]:
    section = ""
    claims: list[dict] = []
    for line_number, raw_line in enumerate(content.splitlines(), start=1):
        stripped = raw_line.strip()
        if not stripped:
            continue
        if stripped.startswith("#"):
            section = stripped.lstrip("#").strip().lower()
            continue
        if section == "evidence" or section == "evidence matrix":
            continue
        if stripped.startswith(("- ", "* ")):
            text = stripped[2:].strip()
        elif re.match(r"^\d+[.)]\s+", stripped):
            text = re.sub(r"^\d+[.)]\s+", "", stripped).strip()
        else:
            continue
        if len(text) < 8:
            continue
        claims.append({"line": line_number, "section": section, "text": text, "is_core": section in CORE_SECTIONS})
    return claims


def _line_range(lines: object) -> tuple[int, int]:
    if not isinstance(lines, list) or len(lines) < 2:
        return (0, 0)
    try:
        return int(lines[0]), int(lines[1])
    except (TypeError, ValueError):
        return (0, 0)


def _dedupe(values: list[str]) -> list[str]:
    seen: set[str] = set()
    result: list[str] = []
    for value in values:
        if value not in seen:
            seen.add(value)
            result.append(value)
    return result