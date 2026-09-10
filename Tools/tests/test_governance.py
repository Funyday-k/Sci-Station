"""Regression tests for release and PR gates, using isolated repository fixtures."""

from __future__ import annotations

import importlib.util
import json
import re
from pathlib import Path
import tempfile
from types import ModuleType
import unittest

ROOT = Path(__file__).resolve().parents[2]


def load_script(name: str) -> ModuleType:
    """Load a repository validation script without invoking its CLI."""
    spec = importlib.util.spec_from_file_location(name, ROOT / "Tools/scripts" / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


versions = load_script("check-version-consistency")
traceability = load_script("check-pr-traceability")
runner = load_script("check-core-runner-architecture")


class VersionGateTests(unittest.TestCase):
    def setUp(self) -> None:
        """Create only the version-bearing files needed by the checker."""
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        files = {
            "VERSION": "0.2.0\n",
            "CHANGELOG.md": "## [0.2.0] - 2026-09-10\n",
            "Sci-Station.xcodeproj/project.pbxproj": "MARKETING_VERSION = 0.2.0;\nMARKETING_VERSION = 0.2.0;\nCURRENT_PROJECT_VERSION = 2;\n",
            "README.md": "> 当前版本：0.2.0\n",
            "docs/README.en.md": "> Current version: 0.2.0\n",
            "AgentRuntime/pyproject.toml": '[project]\nversion = "0.1.0"\n',
            "AgentRuntime/sci_station_agent/__init__.py": '__version__ = "0.1.0"\n',
        }
        for name, text in files.items():
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)

    def test_runtime_can_evolve_independently(self) -> None:
        """An app release must not force all components to the same version."""
        self.assertEqual(versions.check_versions(self.root, "v0.2.0"), [])

    def test_wrong_or_injected_tag_is_rejected(self) -> None:
        """Reject mismatches and arbitrary tag input without executing it."""
        for tag in ["v0.1.0", "v0.2.0-rc.1", "$(touch unexpected)"]:
            self.assertTrue(versions.check_versions(self.root, tag))

    def test_drift_in_one_build_configuration_is_rejected(self) -> None:
        """All Xcode configurations must match the app source of truth."""
        path = self.root / "Sci-Station.xcodeproj/project.pbxproj"
        path.write_text(path.read_text().replace("0.2.0", "0.1.0", 1))
        self.assertTrue(versions.check_versions(self.root))

    def test_runtime_mirror_drift_is_rejected(self) -> None:
        """The runtime's two metadata fields must agree with each other."""
        (self.root / "AgentRuntime/sci_station_agent/__init__.py").write_text('__version__ = "0.9.0"\n')
        self.assertTrue(versions.check_versions(self.root))

    def test_readme_drift_is_rejected(self) -> None:
        """The visible app version is checked, not just build metadata."""
        (self.root / "README.md").write_text("> 当前版本：0.1.0\n")
        self.assertTrue(versions.check_versions(self.root))

    def test_tag_without_release_notes_is_rejected(self) -> None:
        """Unreleased notes alone are insufficient for a published tag."""
        (self.root / "CHANGELOG.md").write_text("## [Unreleased]\n")
        self.assertEqual(versions.check_versions(self.root), [])
        self.assertTrue(versions.check_versions(self.root, "v0.2.0"))


class TraceabilityGateTests(unittest.TestCase):
    def test_empty_pr_template_does_not_pass(self) -> None:
        """Examples and instructions must not count as a real reference."""
        body = (ROOT / ".github/PULL_REQUEST_TEMPLATE.md").read_text()
        self.assertFalse(traceability.has_reference(body, ROOT))
        self.assertFalse(traceability.has_reference("<!-- Closes #42 -->", ROOT))
        self.assertFalse(traceability.has_reference("`Closes #42`", ROOT))

    def test_real_issue_reference_passes(self) -> None:
        """Allow closing references and canonical issue URLs."""
        for body in ["Closes #42", "Refs #42", "https://github.com/Funyday-k/Sci-Station/issues/42"]:
            self.assertTrue(traceability.has_reference(body, ROOT))

    def test_missing_local_decision_or_anchor_is_rejected(self) -> None:
        """Local traceability must resolve to a real versioned record."""
        for body in ["docs/rfcs/RFC-9999-missing.md", "docs/BACKLOG.md", "docs/BACKLOG.md#missing"]:
            self.assertFalse(traceability.has_reference(body, ROOT))

    def test_actual_backlog_and_decision_pass(self) -> None:
        """The initial governance change can link its versioned requirement."""
        for body in ["docs/BACKLOG.md#gov-001--repository-governance-and-delivery-gates", "docs/architecture/ADR-0001-repository-governance.md", "`docs/BACKLOG.md#gov-001--repository-governance-and-delivery-gates`"]:
            self.assertTrue(traceability.has_reference(body, ROOT))


class RunnerArchitectureTests(unittest.TestCase):
    def test_missing_or_collapsed_runner_is_rejected(self) -> None:
        """Empty directories must not silently satisfy an architecture gate."""
        with tempfile.TemporaryDirectory() as directory:
            self.assertTrue(runner.check_runner(Path(directory)))

    def test_duplicate_check_registration_is_rejected(self) -> None:
        """Accidental double registration must fail before running the suite."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            base = root / "Tools/SciStationCoreTestRunner"
            (base / "Suites").mkdir(parents=True)
            (base / "Support").mkdir()
            for name in ["SciStationCoreTestRunner.swift", "CoreVerificationSuite.swift", "Support/Fixtures.swift"]:
                (base / name).write_text("")
            (base / "Suites/Example.swift").write_text('func sample() {}\nawait runCheck("sample")\nawait runCheck("sample")\n')
            self.assertTrue(any("registered once" in error for error in runner.check_runner(root)))

    def test_protection_requires_the_aggregate_gate(self) -> None:
        """The checked-in GitHub protection payload cannot bypass the aggregate."""
        settings = json.loads((ROOT / ".github/repository-settings.json").read_text())
        protection = settings["branch_protection"]
        self.assertTrue(protection["enforce_admins"])
        self.assertTrue(protection["required_status_checks"]["strict"])
        self.assertEqual(protection["required_status_checks"]["checks"], [{"context": "Required CI", "app_id": 15368}])

    def test_aggregate_waits_for_every_quality_job(self) -> None:
        """Adding a quality job must also make it a required aggregate dependency."""
        workflow = (ROOT / ".github/workflows/macos-ci.yml").read_text()
        jobs = set(re.findall(r"^  ([a-z][a-z0-9-]+):$", workflow.split("jobs:", 1)[1], re.M))
        aggregate = workflow.split("  required-ci:", 1)[1]
        dependencies = set(re.search(r"needs: \[([^\]]+)\]", aggregate)[1].replace(" ", "").split(","))
        self.assertEqual(dependencies, jobs - {"required-ci"})
        self.assertIn("if: ${{ always() }}", aggregate)
        self.assertNotIn("continue-on-error: true", workflow)

    def test_release_governance_precedes_credentials(self) -> None:
        """No release credentials should be imported before the quality gates."""
        workflow = (ROOT / ".github/workflows/release.yml").read_text()
        before_credentials = workflow.split("      - name: Import Developer ID certificate", 1)[0]
        for command in ["check-docs-hygiene.py", "check-version-consistency.py", "check-repository-hygiene.sh", "check-core-runner-architecture.py", "git merge-base --is-ancestor HEAD origin/main"]:
            self.assertIn(command, before_credentials)


if __name__ == "__main__":
    unittest.main()
