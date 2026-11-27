#!/usr/bin/env python3
"""Enforce a non-regressing ratchet on frontend CSS, JS, and HTML metrics."""

from __future__ import annotations

import argparse
import bisect
from collections import defaultdict
from dataclasses import dataclass
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_BASELINE_REL = Path("Tools/frontend-metrics.json")
STATIC_REL = Path("web/static")
DEFAULT_PALETTE_ALLOWLIST = ("tokens.css",)
DEFAULT_BASE_CONTROL_ALLOWLIST = ("components.css",)

SCALAR_METRIC_KEYS = (
    "hex_colors_outside_palette",
    "important_lines",
    "distinct_media_widths",
    "distinct_font_sizes",
    "distinct_border_radii",
    "distinct_numeric_z_indices",
    "duplicate_custom_properties",
    "html_sinks",
    "base_control_rules_outside_components",
)

IMPORTANT_RE = re.compile(r"!\s*important\b", re.I)
BARE_BASE_CONTROL_RE = re.compile(
    r"^(?:button|input|select|textarea|dialog)(?:(?:::?[a-zA-Z0-9_-]+(?:\([^)]*\))?)|(?:\[[^\]]*\]))*$",
    re.I,
)
HEX_COLOR_RE = re.compile(
    r"(?<![0-9a-zA-Z_-])#(?:[0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{4}|[0-9a-fA-F]{3})(?![0-9a-fA-F_-])"
)
CSS_URL_OR_STRING_RE = re.compile(
    r"url\(\s*(?:\"[^\"]*\"|'[^']*'|[^)]*)\)|\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*'",
    re.I,
)
MEDIA_WIDTH_PATTERNS = (
    re.compile(
        r"(?<![-\w])(?:min-|max-)?(?:width|inline-size)\s*:\s*([0-9.]+(?:px|em|rem|vw|ch))",
        re.I,
    ),
    re.compile(
        r"(?<![-\w])(?:width|inline-size)\s*(?:<=|>=|<|>|=)\s*([0-9.]+(?:px|em|rem|vw|ch))",
        re.I,
    ),
    re.compile(
        r"([0-9.]+(?:px|em|rem|vw|ch))\s*(?:<=|>=|<|>|=)\s*(?:width|inline-size)(?![-\w])",
        re.I,
    ),
)
NUMERIC_Z_INDEX_RE = re.compile(r"^[+-]?\d+$")
HTML_SINK_RE = re.compile(
    r"(?:\.\s*(innerHTML|outerHTML|insertAdjacentHTML)\b"
    r"|\[\s*(['\"])(innerHTML|outerHTML|insertAdjacentHTML)\2\s*\])"
)

CSS_GROUP_ATRULES = (
    "@media",
    "@supports",
    "@container",
    "@layer",
    "@scope",
    "@document",
    "@keyframes",
    "@-webkit-keyframes",
    "@starting-style",
)

JS_REGEX_PREFIX_KEYWORDS = frozenset(
    {
        "return",
        "case",
        "throw",
        "in",
        "of",
        "typeof",
        "void",
        "delete",
        "else",
        "do",
        "yield",
        "await",
        "new",
    }
)
JS_REGEX_PREFIX_CHARS = frozenset("=(,[!&|?:;{~+-*%^<>")


@dataclass(frozen=True)
class Occurrence:
    path: str
    line: int
    detail: str


@dataclass(frozen=True)
class HtmlEntryMetrics:
    stylesheets: tuple[Occurrence, ...]
    scripts: tuple[Occurrence, ...]


@dataclass(frozen=True)
class MetricsReport:
    hex_colors_outside_palette: tuple[Occurrence, ...]
    important_lines: tuple[Occurrence, ...]
    media_widths: dict[str, tuple[Occurrence, ...]]
    font_sizes: dict[str, tuple[Occurrence, ...]]
    border_radii: dict[str, tuple[Occurrence, ...]]
    numeric_z_indices: dict[str, tuple[Occurrence, ...]]
    duplicate_custom_properties: dict[str, tuple[Occurrence, ...]]
    html_sinks: tuple[Occurrence, ...]
    base_control_rules_outside_components: tuple[Occurrence, ...]
    html_entry_points: dict[str, HtmlEntryMetrics]

    def scalar_counts(self) -> dict[str, int]:
        return {
            "hex_colors_outside_palette": len(self.hex_colors_outside_palette),
            "important_lines": len(self.important_lines),
            "distinct_media_widths": len(self.media_widths),
            "distinct_font_sizes": len(self.font_sizes),
            "distinct_border_radii": len(self.border_radii),
            "distinct_numeric_z_indices": len(self.numeric_z_indices),
            "duplicate_custom_properties": len(self.duplicate_custom_properties),
            "html_sinks": len(self.html_sinks),
            "base_control_rules_outside_components": len(self.base_control_rules_outside_components),
        }


@dataclass(frozen=True)
class MetricFailure:
    metric: str
    message: str
    offending: tuple[str, ...]


def _line_starts(text: str) -> list[int]:
    starts = [0]
    idx = 0
    while True:
        idx = text.find("\n", idx)
        if idx == -1:
            break
        starts.append(idx + 1)
        idx += 1
    return starts


def _line_of(starts: list[int], offset: int, line_offset: int = 0) -> int:
    return bisect.bisect_right(starts, offset) + line_offset


def _mask_preserving_newlines(segment: str) -> str:
    return re.sub(r"[^\n]", " ", segment)


def _strip_css_comments(text: str) -> str:
    out: list[str] = []
    i = 0
    n = len(text)
    quote: str | None = None
    while i < n:
        ch = text[i]
        if quote:
            out.append(ch)
            if ch == "\\" and i + 1 < n:
                out.append(text[i + 1])
                i += 2
                continue
            if ch == quote:
                quote = None
            i += 1
            continue
        if ch in ('"', "'"):
            quote = ch
            out.append(ch)
            i += 1
            continue
        if ch == "/" and i + 1 < n and text[i + 1] == "*":
            end = text.find("*/", i + 2)
            if end == -1:
                out.append(_mask_preserving_newlines(text[i:]))
                break
            out.append(_mask_preserving_newlines(text[i : end + 2]))
            i = end + 2
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def _find_matching_brace(text: str, open_pos: int, end: int) -> int:
    depth = 0
    i = open_pos
    quote: str | None = None
    while i < end:
        ch = text[i]
        if quote:
            if ch == "\\" and i + 1 < end:
                i += 2
                continue
            if ch == quote:
                quote = None
        else:
            if ch in ('"', "'"):
                quote = ch
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    return i
        i += 1
    return end


def _record_css_declaration(
    raw: str,
    offset: int,
    declarations: list[tuple[str, str, int, int]],
) -> None:
    paren_depth = 0
    quote: str | None = None
    colon = -1
    i = 0
    n = len(raw)
    while i < n:
        ch = raw[i]
        if quote:
            if ch == "\\" and i + 1 < n:
                i += 2
                continue
            if ch == quote:
                quote = None
        else:
            if ch in ('"', "'"):
                quote = ch
            elif ch == "(":
                paren_depth += 1
            elif ch == ")":
                paren_depth = max(0, paren_depth - 1)
            elif paren_depth == 0 and ch == ":":
                colon = i
                break
        i += 1
    if colon == -1:
        return
    prop_raw = raw[:colon]
    prop = prop_raw.strip()
    if not prop:
        return
    prop_offset = offset + len(prop_raw) - len(prop_raw.lstrip())
    val_raw = raw[colon + 1 :]
    val_offset = offset + colon + 1
    declarations.append((prop, val_raw, prop_offset, val_offset))


def _split_selector_list(header: str) -> list[str]:
    """Split a CSS selector list on top-level commas (outside parentheses and brackets)."""
    parts: list[str] = []
    start = 0
    paren = 0
    bracket = 0
    quote: str | None = None
    i = 0
    n = len(header)
    while i < n:
        ch = header[i]
        if quote:
            if ch == "\\" and i + 1 < n:
                i += 2
                continue
            if ch == quote:
                quote = None
        elif ch in ('"', "'"):
            quote = ch
        elif ch == "(":
            paren += 1
        elif ch == ")":
            paren = max(0, paren - 1)
        elif ch == "[":
            bracket += 1
        elif ch == "]":
            bracket = max(0, bracket - 1)
        elif ch == "," and paren == 0 and bracket == 0:
            part = header[start:i].strip()
            if part:
                parts.append(part)
            start = i + 1
        i += 1
    tail = header[start:].strip()
    if tail:
        parts.append(tail)
    return parts


def _walk_css_block(
    text: str,
    start: int,
    end: int,
    media_rules: list[tuple[str, int]],
    declarations: list[tuple[str, str, int, int]],
    is_decl_block: bool = False,
    selectors: list[tuple[str, int]] | None = None,
) -> None:
    i = start
    stmt_start = start
    paren_depth = 0
    quote: str | None = None
    while i < end:
        ch = text[i]
        if quote:
            if ch == "\\" and i + 1 < end:
                i += 2
                continue
            if ch == quote:
                quote = None
            i += 1
            continue
        if ch in ('"', "'"):
            quote = ch
            i += 1
            continue
        if ch == "(":
            paren_depth += 1
            i += 1
            continue
        if ch == ")":
            paren_depth = max(0, paren_depth - 1)
            i += 1
            continue
        if paren_depth == 0 and ch == "{":
            raw_header = text[stmt_start:i]
            header = raw_header.strip()
            close_pos = _find_matching_brace(text, i, end)
            header_offset = stmt_start + (len(raw_header) - len(raw_header.lstrip()))
            lower_header = header.lower()
            if re.match(r"^@media\b", lower_header):
                media_rules.append((header, header_offset))
                _walk_css_block(text, i + 1, close_pos, media_rules, declarations, is_decl_block=False, selectors=selectors)
            elif any(re.match(rf"^{re.escape(at)}\b", lower_header) for at in CSS_GROUP_ATRULES):
                _walk_css_block(text, i + 1, close_pos, media_rules, declarations, is_decl_block=False, selectors=selectors)
            else:
                if selectors is not None and header and not lower_header.startswith("@"):
                    selectors.append((header, header_offset))
                _walk_css_block(text, i + 1, close_pos, media_rules, declarations, is_decl_block=True, selectors=selectors)
            i = close_pos + 1
            stmt_start = i
            continue
        if paren_depth == 0 and ch == ";":
            if is_decl_block:
                _record_css_declaration(text[stmt_start:i], stmt_start, declarations)
            i += 1
            stmt_start = i
            continue
        i += 1
    if is_decl_block and stmt_start < end:
        tail = text[stmt_start:end]
        if tail.strip():
            _record_css_declaration(tail, stmt_start, declarations)


def _extract_media_widths(header: str) -> list[str]:
    found: list[tuple[int, str]] = []
    for pattern in MEDIA_WIDTH_PATTERNS:
        for match in pattern.finditer(header):
            found.append((match.start(1), match.group(1).lower()))
    found.sort(key=lambda item: item[0])
    # Deduplicate by position in case overlapping patterns matched the same token.
    result: list[str] = []
    seen_positions: set[int] = set()
    for pos, value in found:
        if pos not in seen_positions:
            seen_positions.add(pos)
            result.append(value)
    return result


def _strip_js_comments_and_non_bracket_strings(source: str) -> str:
    """Mask JS comments, regexes, and string bodies while preserving line numbers.

    Strings immediately following ``[`` are preserved so computed member sinks like
    ``el["innerHTML"]`` remain visible while ordinary strings like
    ``"avoid .innerHTML"`` do not trigger false positives.
    """
    out: list[str] = []
    n = len(source)
    i = 0
    # Track template literal `${ ... }` brace nesting.
    template_brace_stack: list[int] = []
    last_sig_char = ""
    last_ident = ""

    def can_start_regex() -> bool:
        if not last_sig_char and not last_ident:
            return True
        if last_ident in JS_REGEX_PREFIX_KEYWORDS:
            return True
        return last_sig_char in JS_REGEX_PREFIX_CHARS

    while i < n:
        ch = source[i]
        nxt = source[i + 1] if i + 1 < n else ""

        # Line comment
        if ch == "/" and nxt == "/":
            out.append("  ")
            i += 2
            while i < n and source[i] != "\n":
                out.append(" ")
                i += 1
            continue

        # Block comment
        if ch == "/" and nxt == "*":
            out.append("  ")
            i += 2
            while i < n:
                if source[i] == "*" and i + 1 < n and source[i + 1] == "/":
                    out.append("  ")
                    i += 2
                    break
                out.append("\n" if source[i] == "\n" else " ")
                i += 1
            continue

        # Regex literal
        if ch == "/" and can_start_regex():
            out.append(" ")
            i += 1
            in_class = False
            while i < n:
                c = source[i]
                if c == "\\" and i + 1 < n:
                    out.append("\n" if source[i + 1] == "\n" else "  ")
                    i += 2
                    continue
                if c == "[":
                    in_class = True
                elif c == "]":
                    in_class = False
                elif c == "/" and not in_class:
                    out.append(" ")
                    i += 1
                    while i < n and source[i].isalpha():
                        out.append(" ")
                        i += 1
                    break
                out.append("\n" if c == "\n" else " ")
                i += 1
            last_sig_char = ")"
            last_ident = ""
            continue

        # Quoted string literal
        if ch in ('"', "'"):
            keep_contents = last_sig_char == "["
            quote = ch
            out.append(ch if keep_contents else " ")
            i += 1
            while i < n:
                c = source[i]
                if c == "\\" and i + 1 < n:
                    if keep_contents:
                        out.append(source[i : i + 2])
                    else:
                        out.append("\n" if source[i + 1] == "\n" else "  ")
                    i += 2
                    continue
                if c == quote:
                    out.append(c if keep_contents else " ")
                    i += 1
                    break
                if keep_contents:
                    out.append(c)
                else:
                    out.append("\n" if c == "\n" else " ")
                i += 1
            last_sig_char = ")"
            last_ident = ""
            continue

        # Template literal start or resume after `${...}` closing brace
        if ch == "`" or (ch == "}" and template_brace_stack and template_brace_stack[-1] == 0):
            if ch == "}":
                template_brace_stack.pop()
            out.append(" ")
            i += 1
            while i < n:
                c = source[i]
                if c == "\\" and i + 1 < n:
                    out.append("\n" if source[i + 1] == "\n" else "  ")
                    i += 2
                    continue
                if c == "$" and i + 1 < n and source[i + 1] == "{":
                    out.append("  ")
                    i += 2
                    template_brace_stack.append(0)
                    last_sig_char = "{"
                    last_ident = ""
                    break
                if c == "`":
                    out.append(" ")
                    i += 1
                    last_sig_char = ")"
                    last_ident = ""
                    break
                out.append("\n" if c == "\n" else " ")
                i += 1
            continue

        # Track nested braces inside template expressions
        if template_brace_stack:
            if ch == "{":
                template_brace_stack[-1] += 1
            elif ch == "}":
                template_brace_stack[-1] -= 1

        # Identifiers (for regex-prefix keyword detection)
        if ch.isalpha() or ch in ("_", "$"):
            start = i
            while i < n and (source[i].isalnum() or source[i] in ("_", "$")):
                i += 1
            ident = source[start:i]
            out.append(ident)
            last_ident = ident
            last_sig_char = ""
            continue

        if ch in ("+", "-") and nxt == ch:
            out.append(ch + nxt)
            last_sig_char = ")"
            last_ident = ""
            i += 2
            continue

        out.append(ch)
        if not ch.isspace():
            last_sig_char = ch
            last_ident = ""
        i += 1

    return "".join(out)


class _HtmlEntryParser(HTMLParser):
    def __init__(self, rel_path: str) -> None:
        super().__init__(convert_charrefs=False)
        self.rel_path = rel_path
        self.stylesheets: list[Occurrence] = []
        self.scripts: list[Occurrence] = []
        self.inline_scripts: list[tuple[int, str]] = []
        self.inline_styles: list[tuple[int, str]] = []
        self._in_script = False
        self._in_style = False
        self._buf: list[str] = []
        self._buf_line = 1

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        tag_lower = tag.lower()
        line, _ = self.getpos()
        attr_map = {k.lower(): (v or "") for k, v in attrs}
        if tag_lower == "link":
            rels = attr_map.get("rel", "").lower().split()
            if "stylesheet" in rels:
                href = attr_map.get("href", "")
                detail = f'<link rel="stylesheet" href="{href}">' if href else '<link rel="stylesheet">'
                self.stylesheets.append(Occurrence(self.rel_path, line, detail))
        elif tag_lower == "script":
            src = attr_map.get("src", "")
            detail = f'<script src="{src}">' if src else "<script>"
            self.scripts.append(Occurrence(self.rel_path, line, detail))
            self._in_script = True
            self._buf = []
            self._buf_line = line
        elif tag_lower == "style":
            self._in_style = True
            self._buf = []
            self._buf_line = line

    def handle_startendtag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        self.handle_starttag(tag, attrs)
        tag_lower = tag.lower()
        if tag_lower == "script":
            self._in_script = False
        elif tag_lower == "style":
            self._in_style = False

    def handle_data(self, data: str) -> None:
        if self._in_script or self._in_style:
            self._buf.append(data)

    def handle_endtag(self, tag: str) -> None:
        tag_lower = tag.lower()
        if tag_lower == "script" and self._in_script:
            body = "".join(self._buf)
            if body.strip():
                self.inline_scripts.append((self._buf_line, body))
            self._in_script = False
            self._buf = []
        elif tag_lower == "style" and self._in_style:
            body = "".join(self._buf)
            if body.strip():
                self.inline_styles.append((self._buf_line, body))
            self._in_style = False
            self._buf = []


def _scan_css_text(
    text: str,
    rel_path: str,
    file_name: str,
    allow_hex: bool,
    hex_occurrences: list[Occurrence],
    important_occurrences: list[Occurrence],
    media_widths: dict[str, list[Occurrence]],
    font_sizes: dict[str, list[Occurrence]],
    border_radii: dict[str, list[Occurrence]],
    numeric_z_indices: dict[str, list[Occurrence]],
    custom_prop_occurrences: dict[str, list[Occurrence]],
    custom_prop_files: dict[str, set[str]],
    line_offset: int = 0,
    allow_base_controls: bool = True,
    base_control_occurrences: list[Occurrence] | None = None,
) -> None:
    stripped = _strip_css_comments(text)
    raw_lines = text.splitlines()
    starts = _line_starts(stripped)

    for idx, line in enumerate(stripped.splitlines(), start=1):
        if IMPORTANT_RE.search(line):
            snippet = raw_lines[idx - 1].strip() if idx - 1 < len(raw_lines) else line.strip()
            important_occurrences.append(Occurrence(rel_path, idx + line_offset, snippet))

    media_rules: list[tuple[str, int]] = []
    declarations: list[tuple[str, str, int, int]] = []
    selectors: list[tuple[str, int]] = []
    _walk_css_block(stripped, 0, len(stripped), media_rules, declarations, selectors=selectors)

    if not allow_base_controls and base_control_occurrences is not None:
        for header, header_offset in selectors:
            line_no = _line_of(starts, header_offset, line_offset)
            for sel in _split_selector_list(header):
                compact = re.sub(r"\s+", " ", sel).strip()
                if BARE_BASE_CONTROL_RE.fullmatch(compact):
                    base_control_occurrences.append(Occurrence(rel_path, line_no, compact))

    for header, header_offset in media_rules:
        line_no = _line_of(starts, header_offset, line_offset)
        compact_header = re.sub(r"\s+", " ", header).strip()
        for width in _extract_media_widths(header):
            media_widths[width].append(Occurrence(rel_path, line_no, compact_header))

    for prop, val_raw, prop_offset, val_offset in declarations:
        prop_line = _line_of(starts, prop_offset, line_offset)
        if prop.startswith("--"):
            custom_prop_files[prop].add(file_name)
            custom_prop_occurrences[prop].append(Occurrence(rel_path, prop_line, prop))

        if not allow_hex:
            masked_val = CSS_URL_OR_STRING_RE.sub(
                lambda m: _mask_preserving_newlines(m.group(0)),
                val_raw,
            )
            for match in HEX_COLOR_RE.finditer(masked_val):
                hex_line = _line_of(starts, val_offset + match.start(), line_offset)
                hex_occurrences.append(Occurrence(rel_path, hex_line, match.group(0)))

        prop_lower = prop.lower()
        norm_val = IMPORTANT_RE.sub("", val_raw)
        norm_val = re.sub(r"\s+", " ", norm_val.strip())
        if not norm_val:
            continue

        if prop_lower == "font-size":
            font_sizes[norm_val].append(Occurrence(rel_path, prop_line, f"font-size: {norm_val}"))
        elif prop_lower == "border-radius":
            border_radii[norm_val].append(Occurrence(rel_path, prop_line, f"border-radius: {norm_val}"))
        elif prop_lower == "z-index" and NUMERIC_Z_INDEX_RE.fullmatch(norm_val):
            normalized_int = str(int(norm_val))
            numeric_z_indices[normalized_int].append(
                Occurrence(rel_path, prop_line, f"z-index: {normalized_int}")
            )


def _scan_js_sinks(
    source: str,
    rel_path: str,
    sinks: list[Occurrence],
    line_offset: int = 0,
) -> None:
    cleaned = _strip_js_comments_and_non_bracket_strings(source)
    raw_lines = source.splitlines()
    starts = _line_starts(cleaned)
    for match in HTML_SINK_RE.finditer(cleaned):
        sink_name = match.group(1) or match.group(3)
        local_line = _line_of(starts, match.start())
        snippet = raw_lines[local_line - 1].strip() if local_line - 1 < len(raw_lines) else sink_name
        sinks.append(Occurrence(rel_path, local_line + line_offset, snippet))


def collect_metrics(
    root: Path,
    palette_allowlist: list[str] | set[str],
    base_control_allowlist: list[str] | set[str] | tuple[str, ...] = DEFAULT_BASE_CONTROL_ALLOWLIST,
) -> MetricsReport:
    """Scan web/static/*.css|*.js|*.html under root and return detailed metrics."""
    static_dir = root / STATIC_REL
    allowset = {entry.strip() for entry in palette_allowlist if entry.strip()}
    base_allowset = {entry.strip() for entry in base_control_allowlist if entry.strip()}

    hex_occurrences: list[Occurrence] = []
    important_occurrences: list[Occurrence] = []
    media_widths: dict[str, list[Occurrence]] = defaultdict(list)
    font_sizes: dict[str, list[Occurrence]] = defaultdict(list)
    border_radii: dict[str, list[Occurrence]] = defaultdict(list)
    numeric_z_indices: dict[str, list[Occurrence]] = defaultdict(list)
    custom_prop_occurrences: dict[str, list[Occurrence]] = defaultdict(list)
    custom_prop_files: dict[str, set[str]] = defaultdict(set)
    base_control_occurrences: list[Occurrence] = []
    html_sinks: list[Occurrence] = []
    html_entry_points: dict[str, HtmlEntryMetrics] = {}

    if not static_dir.is_dir():
        raise FileNotFoundError(f"Static directory not found: {static_dir}")

    for path in sorted(static_dir.glob("*.css")):
        rel_path = path.relative_to(root).as_posix()
        allow_hex = path.name in allowset or rel_path in allowset
        allow_base = path.name in base_allowset or rel_path in base_allowset
        _scan_css_text(
            text=path.read_text(encoding="utf-8"),
            rel_path=rel_path,
            file_name=path.name,
            allow_hex=allow_hex,
            hex_occurrences=hex_occurrences,
            important_occurrences=important_occurrences,
            media_widths=media_widths,
            font_sizes=font_sizes,
            border_radii=border_radii,
            numeric_z_indices=numeric_z_indices,
            custom_prop_occurrences=custom_prop_occurrences,
            custom_prop_files=custom_prop_files,
            allow_base_controls=allow_base,
            base_control_occurrences=base_control_occurrences,
        )

    for path in sorted(static_dir.glob("*.js")):
        rel_path = path.relative_to(root).as_posix()
        _scan_js_sinks(path.read_text(encoding="utf-8"), rel_path, html_sinks)

    for path in sorted(static_dir.glob("*.html")):
        rel_path = path.relative_to(root).as_posix()
        parser = _HtmlEntryParser(rel_path)
        parser.feed(path.read_text(encoding="utf-8"))
        parser.close()
        html_entry_points[path.name] = HtmlEntryMetrics(
            stylesheets=tuple(parser.stylesheets),
            scripts=tuple(parser.scripts),
        )
        for start_line, body in parser.inline_scripts:
            _scan_js_sinks(body, rel_path, html_sinks, line_offset=start_line - 1)
        allow_hex = path.name in allowset or rel_path in allowset
        allow_base = path.name in base_allowset or rel_path in base_allowset
        for start_line, body in parser.inline_styles:
            _scan_css_text(
                text=body,
                rel_path=rel_path,
                file_name=path.name,
                allow_hex=allow_hex,
                hex_occurrences=hex_occurrences,
                important_occurrences=important_occurrences,
                media_widths=media_widths,
                font_sizes=font_sizes,
                border_radii=border_radii,
                numeric_z_indices=numeric_z_indices,
                custom_prop_occurrences=custom_prop_occurrences,
                custom_prop_files=custom_prop_files,
                line_offset=start_line - 1,
                allow_base_controls=allow_base,
                base_control_occurrences=base_control_occurrences,
            )

    duplicate_custom_properties = {
        prop: tuple(custom_prop_occurrences[prop])
        for prop in sorted(custom_prop_files)
        if len(custom_prop_files[prop]) > 1
    }

    return MetricsReport(
        hex_colors_outside_palette=tuple(hex_occurrences),
        important_lines=tuple(important_occurrences),
        media_widths={k: tuple(media_widths[k]) for k in sorted(media_widths)},
        font_sizes={k: tuple(font_sizes[k]) for k in sorted(font_sizes)},
        border_radii={k: tuple(border_radii[k]) for k in sorted(border_radii)},
        numeric_z_indices={k: tuple(numeric_z_indices[k]) for k in sorted(numeric_z_indices, key=int)},
        duplicate_custom_properties=duplicate_custom_properties,
        html_sinks=tuple(html_sinks),
        base_control_rules_outside_components=tuple(base_control_occurrences),
        html_entry_points=html_entry_points,
    )


def load_baseline(baseline_path: Path) -> dict:
    data = json.loads(baseline_path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"Baseline file must contain a JSON object: {baseline_path}")
    for key in ("palette_allowlist", "metrics", "html_entry_points"):
        if key not in data:
            raise ValueError(f"Baseline file missing required key {key!r}: {baseline_path}")
    if not isinstance(data["palette_allowlist"], list) or not all(
        isinstance(item, str) for item in data["palette_allowlist"]
    ):
        raise ValueError("Baseline 'palette_allowlist' must be a list of filenames")
    if "base_control_allowlist" in data:
        if not isinstance(data["base_control_allowlist"], list) or not all(
            isinstance(item, str) for item in data["base_control_allowlist"]
        ):
            raise ValueError("Baseline 'base_control_allowlist' must be a list of filenames")
    else:
        data["base_control_allowlist"] = list(DEFAULT_BASE_CONTROL_ALLOWLIST)
    if not isinstance(data["metrics"], dict):
        raise ValueError("Baseline 'metrics' must be an object")
    for metric_key in SCALAR_METRIC_KEYS:
        if metric_key == "base_control_rules_outside_components" and metric_key not in data["metrics"]:
            continue
        value = data["metrics"].get(metric_key)
        if not isinstance(value, int) or isinstance(value, bool) or value < 0:
            raise ValueError(f"Baseline metrics[{metric_key!r}] must be a non-negative integer")
    if not isinstance(data["html_entry_points"], dict):
        raise ValueError("Baseline 'html_entry_points' must be an object")
    for name, entry in data["html_entry_points"].items():
        if not isinstance(entry, dict):
            raise ValueError(f"Baseline html_entry_points[{name!r}] must be an object")
        for field in ("stylesheets", "scripts"):
            value = entry.get(field)
            if not isinstance(value, int) or isinstance(value, bool) or value < 0:
                raise ValueError(
                    f"Baseline html_entry_points[{name!r}][{field!r}] must be a non-negative integer"
                )
    return data


def _format_flat_occurrences(occurrences: tuple[Occurrence, ...]) -> tuple[str, ...]:
    return tuple(f"{occ.path}:{occ.line}: {occ.detail}" for occ in occurrences)


def _format_grouped_occurrences(groups: dict[str, tuple[Occurrence, ...]]) -> tuple[str, ...]:
    lines: list[str] = []
    for key, occurrences in groups.items():
        locations = ", ".join(f"{occ.path}:{occ.line}" for occ in occurrences)
        lines.append(f"{key} -> {locations}")
    return tuple(lines)


def compare_with_baseline(
    report: MetricsReport,
    baseline: dict,
) -> tuple[list[MetricFailure], list[str]]:
    """Return (failures, improvements) comparing report against baseline."""
    failures: list[MetricFailure] = []
    improvements: list[str] = []

    counts = report.scalar_counts()
    baseline_metrics: dict[str, int] = baseline["metrics"]

    scalar_offenders: dict[str, tuple[str, ...]] = {
        "hex_colors_outside_palette": _format_flat_occurrences(report.hex_colors_outside_palette),
        "important_lines": _format_flat_occurrences(report.important_lines),
        "distinct_media_widths": _format_grouped_occurrences(report.media_widths),
        "distinct_font_sizes": _format_grouped_occurrences(report.font_sizes),
        "distinct_border_radii": _format_grouped_occurrences(report.border_radii),
        "distinct_numeric_z_indices": _format_grouped_occurrences(report.numeric_z_indices),
        "duplicate_custom_properties": _format_grouped_occurrences(report.duplicate_custom_properties),
        "html_sinks": _format_flat_occurrences(report.html_sinks),
        "base_control_rules_outside_components": _format_flat_occurrences(report.base_control_rules_outside_components),
    }

    for key in SCALAR_METRIC_KEYS:
        if key not in baseline_metrics:
            continue
        actual = counts[key]
        limit = baseline_metrics[key]
        if actual > limit:
            failures.append(
                MetricFailure(
                    metric=key,
                    message=f"{key}: {actual} exceeds baseline {limit}",
                    offending=scalar_offenders[key],
                )
            )
        elif actual < limit:
            improvements.append(f"{key}: {actual} < baseline {limit}")

    baseline_entries: dict[str, dict[str, int]] = baseline["html_entry_points"]
    for name in sorted(report.html_entry_points):
        entry = report.html_entry_points[name]
        if name not in baseline_entries:
            offending = _format_flat_occurrences(entry.stylesheets + entry.scripts)
            if not offending:
                offending = (f"{(STATIC_REL / name).as_posix()}:1: new HTML entry point",)
            failures.append(
                MetricFailure(
                    metric=f"html_entry_points.{name}",
                    message=(
                        f"html_entry_points[{name}]: unlisted HTML entry point "
                        f"(stylesheets={len(entry.stylesheets)}, scripts={len(entry.scripts)})"
                    ),
                    offending=offending,
                )
            )
            continue

        limit_entry = baseline_entries[name]
        actual_css = len(entry.stylesheets)
        limit_css = limit_entry["stylesheets"]
        if actual_css > limit_css:
            failures.append(
                MetricFailure(
                    metric=f"html_entry_points.{name}.stylesheets",
                    message=f"html_entry_points[{name}].stylesheets: {actual_css} exceeds baseline {limit_css}",
                    offending=_format_flat_occurrences(entry.stylesheets),
                )
            )
        elif actual_css < limit_css:
            improvements.append(f"html_entry_points[{name}].stylesheets: {actual_css} < baseline {limit_css}")

        actual_js = len(entry.scripts)
        limit_js = limit_entry["scripts"]
        if actual_js > limit_js:
            failures.append(
                MetricFailure(
                    metric=f"html_entry_points.{name}.scripts",
                    message=f"html_entry_points[{name}].scripts: {actual_js} exceeds baseline {limit_js}",
                    offending=_format_flat_occurrences(entry.scripts),
                )
            )
        elif actual_js < limit_js:
            improvements.append(f"html_entry_points[{name}].scripts: {actual_js} < baseline {limit_js}")

    for removed_name in sorted(set(baseline_entries) - set(report.html_entry_points)):
        improvements.append(f"html_entry_points[{removed_name}]: removed")

    return failures, improvements


def format_baseline(
    report: MetricsReport,
    palette_allowlist: list[str],
    base_control_allowlist: list[str] | tuple[str, ...] = DEFAULT_BASE_CONTROL_ALLOWLIST,
) -> str:
    """Format current metrics as JSON where lowering any baseline is a one-line edit."""
    counts = report.scalar_counts()
    lines: list[str] = ["{"]

    lines.append('  "palette_allowlist": [')
    for idx, entry in enumerate(palette_allowlist):
        comma = "," if idx + 1 < len(palette_allowlist) else ""
        lines.append(f"    {json.dumps(entry)}{comma}")
    lines.append("  ],")

    lines.append('  "base_control_allowlist": [')
    base_list = list(base_control_allowlist)
    for idx, entry in enumerate(base_list):
        comma = "," if idx + 1 < len(base_list) else ""
        lines.append(f"    {json.dumps(entry)}{comma}")
    lines.append("  ],")

    lines.append('  "metrics": {')
    for idx, key in enumerate(SCALAR_METRIC_KEYS):
        comma = "," if idx + 1 < len(SCALAR_METRIC_KEYS) else ""
        lines.append(f"    {json.dumps(key)}: {counts[key]}{comma}")
    lines.append("  },")

    lines.append('  "html_entry_points": {')
    entry_names = sorted(report.html_entry_points)
    for idx, name in enumerate(entry_names):
        entry = report.html_entry_points[name]
        comma = "," if idx + 1 < len(entry_names) else ""
        lines.append(
            f'    {json.dumps(name)}: {{"stylesheets": {len(entry.stylesheets)}, "scripts": {len(entry.scripts)}}}{comma}'
        )
    lines.append("  }")
    lines.append("}")
    return "\n".join(lines) + "\n"


def format_failures(failures: list[MetricFailure]) -> str:
    lines: list[str] = []
    for failure in failures:
        lines.append(f"FAIL {failure.message}")
        for item in failure.offending:
            lines.append(f"  {item}")
    return "\n".join(lines)


def check_metrics(
    root: Path = ROOT,
    baseline_path: Path | None = None,
) -> tuple[MetricsReport, list[MetricFailure], list[str], list[str]]:
    """Run the frontend metrics ratchet and return (report, failures, improvements, allowlist)."""
    resolved_baseline = baseline_path if baseline_path is not None else root / DEFAULT_BASELINE_REL
    baseline = load_baseline(resolved_baseline)
    allowlist = list(baseline["palette_allowlist"])
    base_allowlist = list(baseline["base_control_allowlist"])
    report = collect_metrics(root, allowlist, base_allowlist)
    failures, improvements = compare_with_baseline(report, baseline)
    return report, failures, improvements, allowlist


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root",
        type=Path,
        default=ROOT,
        help="Repository root containing web/static/ (default: repository root).",
    )
    parser.add_argument(
        "--baseline",
        type=Path,
        default=None,
        help="Path to the metrics baseline JSON (default: <root>/Tools/frontend-metrics.json).",
    )
    parser.add_argument(
        "--print-baseline",
        action="store_true",
        help="Print the current measured values in Tools/frontend-metrics.json format and exit 0.",
    )
    args = parser.parse_args(argv)

    root = args.root.resolve()
    baseline_path = args.baseline.resolve() if args.baseline else root / DEFAULT_BASELINE_REL

    try:
        if args.print_baseline:
            if baseline_path.is_file() and baseline_path.stat().st_size > 0:
                loaded = load_baseline(baseline_path)
                allowlist = list(loaded["palette_allowlist"])
                base_allowlist = list(loaded["base_control_allowlist"])
            else:
                allowlist = list(DEFAULT_PALETTE_ALLOWLIST)
                base_allowlist = list(DEFAULT_BASE_CONTROL_ALLOWLIST)
            report = collect_metrics(root, allowlist, base_allowlist)
            sys.stdout.write(format_baseline(report, allowlist, base_allowlist))
            return 0

        report, failures, improvements, _allowlist = check_metrics(root, baseline_path)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    if failures:
        print(format_failures(failures), file=sys.stderr)
        print(
            "Frontend metrics ratchet failed. Lower the introduced values or update "
            "Tools/frontend-metrics.json if an intentional baseline change was approved.",
            file=sys.stderr,
        )
        return 1

    counts = report.scalar_counts()
    summary = ", ".join(f"{key}={counts[key]}" for key in SCALAR_METRIC_KEYS)
    print(f"Frontend metrics ratchet passed ({summary}; {len(report.html_entry_points)} HTML entry points).")
    if improvements:
        print("Metrics below baseline (run with --print-baseline to lower Tools/frontend-metrics.json):")
        for item in improvements:
            print(f"  {item}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
