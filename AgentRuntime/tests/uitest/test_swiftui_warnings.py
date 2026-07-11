"""Coverage for the SwiftUI runtime warning log format.

The on-disk schema is owned by
``Sci-Station/Testing/SwiftUIRuntimeWarningCapture.swift``; this test
locks the Python parser onto the same tab-separated contract so a Swift
refactor that drops or adds a field fails loudly here.
"""

from __future__ import annotations

from pathlib import Path

import pytest

from sci_station_agent.uitest.files import (
    FileProbe,
    SWIFTUI_WARNINGS_RELATIVE_PATH,
    SwiftUIWarning,
    parse_swiftui_warnings_log,
)


SAMPLE_LINE = (
    "2026-05-17T21:30:00.123Z\t"
    "com.apple.runtime-issues\t"
    "SwiftUI\t"
    "Sci-Station\t"
    "Modifying state during view update."
)


def test_parse_sample_line_returns_all_five_fields() -> None:
    warning = SwiftUIWarning.parse(SAMPLE_LINE)
    assert warning is not None
    assert warning.timestamp == "2026-05-17T21:30:00.123Z"
    assert warning.subsystem == "com.apple.runtime-issues"
    assert warning.category == "SwiftUI"
    assert warning.process == "Sci-Station"
    assert warning.message == "Modifying state during view update."


def test_parse_rejects_lines_missing_fields() -> None:
    assert SwiftUIWarning.parse("only-two\tfields") is None
    assert SwiftUIWarning.parse("") is None


def test_parse_log_skips_blank_and_malformed_lines(tmp_path: Path) -> None:
    log = tmp_path / SWIFTUI_WARNINGS_RELATIVE_PATH
    log.parent.mkdir(parents=True, exist_ok=True)
    log.write_text(
        SAMPLE_LINE
        + "\n"
        + "\n"
        + "garbage line\n"
        + SAMPLE_LINE.replace(
            "Modifying state during view update.",
            "Cycle detected during view update.",
        )
        + "\n",
        encoding="utf-8",
    )
    warnings = parse_swiftui_warnings_log(log)
    assert [w.message for w in warnings] == [
        "Modifying state during view update.",
        "Cycle detected during view update.",
    ]


def test_parse_log_returns_empty_when_file_missing(tmp_path: Path) -> None:
    assert parse_swiftui_warnings_log(tmp_path / "missing.log") == []


def test_file_probe_can_assert_no_warnings_via_text_loader(tmp_path: Path) -> None:
    # Simulate the App creating the log on workspace open:
    # file exists but no warnings were ever appended.
    log = tmp_path / SWIFTUI_WARNINGS_RELATIVE_PATH
    log.parent.mkdir(parents=True, exist_ok=True)
    log.write_text("", encoding="utf-8")

    probe = FileProbe(tmp_path)
    assert probe.matches(
        SWIFTUI_WARNINGS_RELATIVE_PATH,
        loader="text",
        expected_equals="",
    )


def test_file_probe_can_assert_warning_appeared_via_text_loader(tmp_path: Path) -> None:
    log = tmp_path / SWIFTUI_WARNINGS_RELATIVE_PATH
    log.parent.mkdir(parents=True, exist_ok=True)
    log.write_text(SAMPLE_LINE + "\n", encoding="utf-8")

    probe = FileProbe(tmp_path)
    assert probe.matches(
        SWIFTUI_WARNINGS_RELATIVE_PATH,
        loader="text",
        expected_contains_text="Modifying state",
    )
    assert not probe.matches(
        SWIFTUI_WARNINGS_RELATIVE_PATH,
        loader="text",
        expected_contains_text="never gonna match",
    )
