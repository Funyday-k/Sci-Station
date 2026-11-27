"""Unit tests for Tools/scripts/check-frontend-metrics.py using isolated fixtures."""

from __future__ import annotations

import contextlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
from types import ModuleType
import unittest


ROOT = Path(__file__).resolve().parents[2]


def load_script(name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, ROOT / "Tools/scripts" / f"{name}.py")
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    # Register before exec so dataclasses can resolve string annotations on Python 3.12.
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


metrics = load_script("check-frontend-metrics")


class FrontendMetricsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        (self.root / "web/static").mkdir(parents=True)
        (self.root / "Tools").mkdir(parents=True)

    def write(self, rel_path: str, content: str) -> Path:
        path = self.root / rel_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        return path

    def write_baseline(
        self,
        *,
        allowlist: list[str] | None = None,
        metric_limits: dict[str, int] | None = None,
        html_entries: dict[str, dict[str, int]] | None = None,
    ) -> Path:
        payload = {
            "palette_allowlist": allowlist if allowlist is not None else ["workspace-theme.css", "tokens.css"],
            "metrics": {key: 0 for key in metrics.SCALAR_METRIC_KEYS},
            "html_entry_points": html_entries if html_entries is not None else {},
        }
        if metric_limits:
            payload["metrics"].update(metric_limits)
        return self.write("Tools/frontend-metrics.json", json.dumps(payload, indent=2) + "\n")

    def test_counts_all_css_js_and_html_metrics_accurately(self) -> None:
        # Palette file: hex values here must be ignored by the allowlist,
        # while repeated custom properties within one file are NOT cross-file duplicates.
        self.write(
            "web/static/workspace-theme.css",
            """\
:root {
  --palette-accent: #4f46e5;
  --shared-token: #112233;
}
:root[data-theme="dark"] {
  --palette-accent: #a5b4fc;
}
""",
        )

        # Non-palette CSS exercising hex lengths, comments, selectors, url(), !important,
        # @media classic + range syntax, @container exclusion, font-size, border-radius, z-index.
        self.write(
            "web/static/app.css",
            """\
/* Ignored comment: #ff0000 !important font-size: 99px; border-radius: 99px; z-index: 999; */
#abc {
  --shared-token: var(--palette-accent);
  --only-here: 1px;
  color: #fff;
  background: url(#def) no-repeat;
  content: "#123456 /* not a comment */";
  box-shadow:
    0 2px 4px #1234,
    0 4px 8px #11223344;
  font-size: 14px !important;
  border-radius: 8px !important;
  z-index: +10;
}
.second {
  border-color: #a1b2c3;
  font-size: 14px;
  font-size: 1rem;
  border-radius: 8px;
  border-radius: 50%;
  z-index: 10;
  z-index: -1;
  z-index: auto;
  z-index: var(--z-modal);
  display: block !important; color: inherit !IMPORTANT;
}
@media (max-width: 800px) and (max-height: 600px) {
  .second { font-size: 1rem; }
}
@media (min-width: 1000px) {
  .second { z-index: 20; }
}
@media (600px <= width <= 800px) {
  .second { border-radius: 50%; }
}
@container (max-width: 420px) {
  .second { padding: 0; }
}
""",
        )

        # JS file exercising real sinks, comments, strings, regexes, templates, and ++/division.
        self.write(
            "web/static/app.js",
            """\
// el.innerHTML = "commented out";
/* el.outerHTML = "block comment"; */
const doc = "do not call el.innerHTML or el.insertAdjacentHTML";
const rx = /\\.innerHTML|outerHTML/;
let n = 1;
const ratio = n++ / 2;
el.innerHTML = "<b>hi</b>";
other.outerHTML = "<p>ok</p>";
panel.insertAdjacentHTML("beforeend", "<span>x</span>");
box["innerHTML"] = `${target.innerHTML = "nested"}`;
""",
        )

        # Vendor subdirectory must be ignored.
        self.write("web/static/research-vendor/vendor.css", ".v { color: #ff00ff !important; }\n")
        self.write("web/static/research-vendor/vendor.js", "el.innerHTML = 'vendor';\n")

        # HTML entry point with comments, non-stylesheet link, stylesheets, scripts, inline sink.
        self.write(
            "web/static/index.html",
            """\
<!doctype html>
<!-- <link rel="stylesheet" href="/static/commented.css"><script src="/static/old.js"></script> -->
<link rel="icon" href="/static/icon.png">
<link rel="stylesheet" href="/static/workspace-theme.css">
<link
  rel="alternate stylesheet"
  href="/static/app.css"
>
<script defer src="/static/app.js"></script>
<script>
  // inline comment el.innerHTML = "no";
  inlineNode.innerHTML = "yes";
</script>
""",
        )

        report = metrics.collect_metrics(self.root, ["workspace-theme.css", "tokens.css"])
        counts = report.scalar_counts()

        # Hex colors outside palette: #fff (line 5), #1234 (line 9), #11223344 (line 10), #a1b2c3 (line 16).
        self.assertEqual(counts["hex_colors_outside_palette"], 4)
        self.assertEqual(
            [(occ.path, occ.line, occ.detail) for occ in report.hex_colors_outside_palette],
            [
                ("web/static/app.css", 5, "#fff"),
                ("web/static/app.css", 9, "#1234"),
                ("web/static/app.css", 10, "#11223344"),
                ("web/static/app.css", 16, "#a1b2c3"),
            ],
        )

        # !important lines: lines 11, 12, 25 (line 25 has two !important tokens, counts as 1 line).
        self.assertEqual(counts["important_lines"], 3)
        self.assertEqual([occ.line for occ in report.important_lines], [11, 12, 25])

        # Distinct viewport @media widths: 600px, 800px, 1000px (@container 420px and max-height 600px excluded).
        self.assertEqual(counts["distinct_media_widths"], 3)
        self.assertEqual(sorted(report.media_widths), ["1000px", "600px", "800px"])

        # Distinct font-size: 14px, 1rem.
        self.assertEqual(counts["distinct_font_sizes"], 2)
        self.assertEqual(sorted(report.font_sizes), ["14px", "1rem"])

        # Distinct border-radius: 50%, 8px.
        self.assertEqual(counts["distinct_border_radii"], 2)
        self.assertEqual(sorted(report.border_radii), ["50%", "8px"])

        # Distinct numeric z-index: -1, 10 (+10 normalized to 10), 20 (auto and var() ignored).
        self.assertEqual(counts["distinct_numeric_z_indices"], 3)
        self.assertEqual(list(report.numeric_z_indices), ["-1", "10", "20"])

        # Duplicate custom properties across files: only --shared-token.
        self.assertEqual(counts["duplicate_custom_properties"], 1)
        self.assertEqual(list(report.duplicate_custom_properties), ["--shared-token"])

        # HTML sinks: 5 in app.js (lines 7, 8, 9, 10 x2) + 1 in inline <script> of index.html (line 12).
        self.assertEqual(counts["html_sinks"], 6)
        self.assertEqual(
            [(occ.path, occ.line) for occ in report.html_sinks],
            [
                ("web/static/app.js", 7),
                ("web/static/app.js", 8),
                ("web/static/app.js", 9),
                ("web/static/app.js", 10),
                ("web/static/app.js", 10),
                ("web/static/index.html", 12),
            ],
        )

        # HTML entry points: 2 stylesheets, 2 scripts.
        self.assertEqual(list(report.html_entry_points), ["index.html"])
        self.assertEqual(len(report.html_entry_points["index.html"].stylesheets), 2)
        self.assertEqual(len(report.html_entry_points["index.html"].scripts), 2)

    def test_palette_allowlist_controls_hex_counting(self) -> None:
        self.write("web/static/tokens.css", ":root { --a: #111; --b: #222; }\n")
        self.write("web/static/page.css", ".x { color: #333; }\n")

        with_allowlist = metrics.collect_metrics(self.root, ["tokens.css"])
        self.assertEqual(with_allowlist.scalar_counts()["hex_colors_outside_palette"], 1)
        self.assertEqual(with_allowlist.hex_colors_outside_palette[0].path, "web/static/page.css")

        without_allowlist = metrics.collect_metrics(self.root, [])
        self.assertEqual(without_allowlist.scalar_counts()["hex_colors_outside_palette"], 3)

    def test_failure_output_lists_offending_files_and_lines(self) -> None:
        self.write("web/static/page.css", ".card {\n  color: #abcdef;\n  font-size: 15px !important;\n}\n")
        self.write("web/static/page.js", "const a = 1;\nroot.innerHTML = html;\n")
        self.write(
            "web/static/page.html",
            '<link rel="stylesheet" href="/static/page.css">\n<script src="/static/page.js"></script>\n',
        )
        self.write_baseline(
            metric_limits={
                "hex_colors_outside_palette": 0,
                "important_lines": 0,
                "distinct_font_sizes": 0,
                "html_sinks": 0,
            },
            html_entries={"page.html": {"stylesheets": 0, "scripts": 1}},
        )

        stderr = io.StringIO()
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            code = metrics.main(["--root", str(self.root)])

        self.assertEqual(code, 1)
        err = stderr.getvalue()
        self.assertIn("FAIL hex_colors_outside_palette: 1 exceeds baseline 0", err)
        self.assertIn("web/static/page.css:2: #abcdef", err)
        self.assertIn("FAIL important_lines: 1 exceeds baseline 0", err)
        self.assertIn("web/static/page.css:3: font-size: 15px !important;", err)
        self.assertIn("FAIL html_sinks: 1 exceeds baseline 0", err)
        self.assertIn("web/static/page.js:2: root.innerHTML = html;", err)
        self.assertIn("FAIL html_entry_points[page.html].stylesheets: 1 exceeds baseline 0", err)
        self.assertIn('web/static/page.html:1: <link rel="stylesheet" href="/static/page.css">', err)

    def test_unlisted_html_entry_point_fails_ratchet(self) -> None:
        self.write("web/static/settings.html", '<script src="/static/settings.js"></script>\n')
        self.write_baseline(html_entries={})

        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            code = metrics.main(["--root", str(self.root)])

        self.assertEqual(code, 1)
        self.assertIn("html_entry_points[settings.html]: unlisted HTML entry point", stderr.getvalue())
        self.assertIn("web/static/settings.html:1:", stderr.getvalue())

    def test_metrics_below_baseline_pass_and_print_baseline_formats_one_line_entries(self) -> None:
        self.write("web/static/page.css", ".card { color: #123; }\n")
        self.write("web/static/page.html", '<link rel="stylesheet" href="/static/page.css">\n')
        self.write_baseline(
            allowlist=["tokens.css"],
            metric_limits={"hex_colors_outside_palette": 5},
            html_entries={"page.html": {"stylesheets": 3, "scripts": 1}},
        )

        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            code = metrics.main(["--root", str(self.root)])
        self.assertEqual(code, 0)
        self.assertIn("hex_colors_outside_palette: 1 < baseline 5", stdout.getvalue())
        self.assertIn("html_entry_points[page.html].stylesheets: 1 < baseline 3", stdout.getvalue())

        printed = io.StringIO()
        with contextlib.redirect_stdout(printed):
            code = metrics.main(["--root", str(self.root), "--print-baseline"])
        self.assertEqual(code, 0)
        text = printed.getvalue()
        parsed = json.loads(text)
        self.assertEqual(parsed["palette_allowlist"], ["tokens.css"])
        self.assertEqual(parsed["metrics"]["hex_colors_outside_palette"], 1)
        self.assertEqual(parsed["html_entry_points"]["page.html"], {"stylesheets": 1, "scripts": 0})
        # Verify one-line format for lowering baselines.
        self.assertIn('    "hex_colors_outside_palette": 1,', text)
        self.assertIn('    "page.html": {"stylesheets": 1, "scripts": 0}', text)

    def test_missing_or_malformed_baseline_fails_cleanly(self) -> None:
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            code = metrics.main(["--root", str(self.root)])
        self.assertEqual(code, 1)
        self.assertIn("error:", stderr.getvalue())

        self.write("Tools/frontend-metrics.json", '{"palette_allowlist": []}\n')
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            code = metrics.main(["--root", str(self.root)])
        self.assertEqual(code, 1)
        self.assertIn("missing required key", stderr.getvalue())

    def test_base_control_allowlist_blocks_bare_controls_outside_components(self) -> None:
        self.write(
            "web/static/components.css",
            "button { cursor: pointer; }\ndialog { padding: 0; }\n",
        )
        self.write(
            "web/static/page.css",
            ".toolbar button { padding: 4px; }\ninput[type='text'] { width: 100%; }\nbutton:disabled { opacity: 0.5; }\n",
        )
        report = metrics.collect_metrics(self.root, ["tokens.css"], ["components.css"])
        self.assertEqual(len(report.base_control_rules_outside_components), 2)
        details = [occ.detail for occ in report.base_control_rules_outside_components]
        self.assertEqual(details, ["input[type='text']", "button:disabled"])

    def test_nested_es_modules_scanned_and_vendor_ignored(self) -> None:
        self.write("web/static/modules/studio/dom.js", "export function render(el, html) { el.innerHTML = html; }\n")
        self.write("web/static/research-vendor/vendor.js", "el.innerHTML = 'ignored';\n")
        report = metrics.collect_metrics(self.root, ["tokens.css"], ["components.css"])
        self.assertEqual(
            [(occ.path, occ.line) for occ in report.html_sinks],
            [("web/static/modules/studio/dom.js", 1)],
        )

    def test_repository_baseline_and_ci_wiring_are_intact(self) -> None:
        report, failures, _improvements, _allowlist = metrics.check_metrics(ROOT)
        self.assertEqual(failures, [], metrics.format_failures(failures))
        self.assertIn("studio.html", report.html_entry_points)

        workflow = (ROOT / ".github/workflows/macos-ci.yml").read_text(encoding="utf-8")
        hygiene_job = workflow.split("  repository-hygiene:", 1)[1].split("  traceability:", 1)[0]
        self.assertIn("python3 Tools/scripts/check-frontend-metrics.py", hygiene_job)
        aggregate = workflow.split("  required-ci:", 1)[1]
        self.assertRegex(aggregate, r"needs: \[[^\]]*\brepository-hygiene\b[^\]]*\]")


if __name__ == "__main__":
    unittest.main()
