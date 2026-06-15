"""Markdown report builder for scenario runs.

Each run produces a self-contained file that links back to the scenario
source, the App's research-root, and the failing/passing channels.
"""

from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path

from sci_station_agent.uitest.runner import ScenarioRunResult


def render_markdown(
    result: ScenarioRunResult,
    *,
    scenario_title: str = "",
    scenario_source: Path | None = None,
) -> str:
    """Return a markdown string describing ``result``."""

    timestamp = datetime.now(timezone.utc).isoformat(timespec="seconds")
    lines: list[str] = []
    status = "PASS" if result.succeeded else "FAIL"
    lines.append(f"# {result.scenario_id} -- {status}")
    if scenario_title:
        lines.append(f"_{scenario_title}_")
    lines.append("")
    lines.append(f"- generated: `{timestamp}`")
    lines.append(f"- research_root: `{result.research_root}`")
    if scenario_source is not None:
        lines.append(f"- scenario: `{scenario_source}`")
    lines.append("")

    lines.append("## Steps")
    if not result.steps:
        lines.append("_(no steps recorded)_")
    else:
        for outcome in result.steps:
            badge = ":white_check_mark:" if outcome.succeeded else ":x:"
            target = outcome.step.target or outcome.step.event or ""
            description = outcome.step.description or outcome.step.kind
            detail = f" -- {outcome.detail}" if outcome.detail else ""
            lines.append(
                f"- {badge} **{description}** `{outcome.step.kind}`"
                f" target=`{target}`{detail}"
            )
    lines.append("")

    lines.append("## Assertions")
    if not result.assertions:
        lines.append("_(scenario aborted before assertions ran)_")
    else:
        for outcome in result.assertions:
            badge = ":white_check_mark:" if outcome.succeeded else ":x:"
            channel = outcome.assertion.channel
            description = outcome.assertion.description
            detail = f" -- {outcome.detail}" if outcome.detail else ""
            lines.append(
                f"- {badge} **[{channel}]** {description}{detail}"
            )
    lines.append("")

    if result.notes:
        lines.append("## Notes")
        for note in result.notes:
            lines.append(f"- {note}")
        lines.append("")

    return "\n".join(lines)
