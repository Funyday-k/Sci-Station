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
    spec = importlib.util.spec_from_file_location(name, ROOT / "Tools/scripts" / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


versions = load_script("check-version-consistency")
traceability = load_script("check-pr-traceability")


class VersionGateTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        files = {
            "VERSION": "0.2.0\n",
            "CHANGELOG.md": "## [0.2.0] - 2026-09-10\n",
            "BUILD_NUMBER": "2\n",
            "README.md": "> 当前版本：0.2.0\n",
            "docs/README.en.md": "> Current version: 0.2.0\n",
        }
        for name, text in files.items():
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)

    def test_version_sources_pass(self) -> None:
        self.assertEqual(versions.check_versions(self.root, "v0.2.0"), [])

    def test_wrong_or_injected_tag_is_rejected(self) -> None:
        for tag in ["v0.1.0", "v0.2.0-rc.1", "$(touch unexpected)"]:
            self.assertTrue(versions.check_versions(self.root, tag))

    def test_invalid_build_number_is_rejected(self) -> None:
        for build_number in ["", "one", "0", "02", "2.0", "2\n3"]:
            with self.subTest(build_number=build_number):
                (self.root / "BUILD_NUMBER").write_text(f"{build_number}\n")
                self.assertTrue(versions.check_versions(self.root))

    def test_readme_drift_is_rejected(self) -> None:
        (self.root / "README.md").write_text("> 当前版本：0.1.0\n")
        self.assertTrue(versions.check_versions(self.root))

    def test_tag_without_release_notes_is_rejected(self) -> None:
        (self.root / "CHANGELOG.md").write_text("## [Unreleased]\n")
        self.assertEqual(versions.check_versions(self.root), [])
        self.assertTrue(versions.check_versions(self.root, "v0.2.0"))


class TraceabilityGateTests(unittest.TestCase):
    def test_empty_pr_template_does_not_pass(self) -> None:
        body = (ROOT / ".github/PULL_REQUEST_TEMPLATE.md").read_text()
        self.assertFalse(traceability.has_reference(body, ROOT))
        self.assertFalse(traceability.has_reference("<!-- Closes #42 -->", ROOT))
        self.assertFalse(traceability.has_reference("`Closes #42`", ROOT))

    def test_real_issue_reference_passes(self) -> None:
        for body in ["Closes #42", "Refs #42", "https://github.com/Funyday-k/Sci-Station/issues/42"]:
            self.assertTrue(traceability.has_reference(body, ROOT))

    def test_missing_local_decision_or_anchor_is_rejected(self) -> None:
        for body in ["docs/rfcs/RFC-9999-missing.md", "docs/BACKLOG.md", "docs/BACKLOG.md#missing"]:
            self.assertFalse(traceability.has_reference(body, ROOT))

    def test_actual_backlog_and_decision_pass(self) -> None:
        for body in ["docs/BACKLOG.md#gov-001--repository-governance-and-delivery-gates", "docs/architecture/ADR-0001-repository-governance.md", "`docs/BACKLOG.md#gov-001--repository-governance-and-delivery-gates`"]:
            self.assertTrue(traceability.has_reference(body, ROOT))


class WorkflowGovernanceTests(unittest.TestCase):
    def test_external_actions_use_immutable_refs(self) -> None:
        for workflow in sorted((ROOT / ".github/workflows").glob("*.yml")):
            for action in re.findall(r"^ *(?:- )?uses: *(\S+)", workflow.read_text(), re.M):
                if not action.startswith("./"):
                    with self.subTest(workflow=workflow.name, action=action):
                        self.assertRegex(action, r"^[^@]+@[0-9a-f]{40}$")

    def test_protection_requires_the_aggregate_gate(self) -> None:
        settings = json.loads((ROOT / ".github/repository-settings.json").read_text())
        protection = settings["branch_protection"]
        self.assertTrue(protection["enforce_admins"])
        self.assertTrue(protection["required_status_checks"]["strict"])
        self.assertEqual(protection["required_status_checks"]["checks"], [{"context": "Required CI", "app_id": 15368}])

    def test_aggregate_waits_for_every_quality_job(self) -> None:
        workflow = (ROOT / ".github/workflows/macos-ci.yml").read_text()
        jobs = set(re.findall(r"^  ([a-z][a-z0-9-]+):$", workflow.split("jobs:", 1)[1], re.M))
        aggregate = workflow.split("  required-ci:", 1)[1]
        dependencies = set(re.search(r"needs: \[([^\]]+)\]", aggregate)[1].replace(" ", "").split(","))
        self.assertEqual(dependencies, jobs - {"required-ci"})
        self.assertIn("if: ${{ always() }}", aggregate)
        self.assertNotIn("continue-on-error: true", workflow)

    def test_public_release_is_certificate_free(self) -> None:
        workflow = (ROOT / ".github/workflows/release.yml").read_text()
        build_script = (ROOT / "packaging/macos/build.sh").read_text()
        package_script = (ROOT / "packaging/macos/package.sh").read_text()
        combined = workflow + build_script + package_script
        for forbidden in ["DEVELOPER_ID_", "APPLE_NOTARY_", "notarytool", "stapler staple"]:
            self.assertNotIn(forbidden, combined)
        self.assertIn("--options runtime", build_script)
        self.assertIn("--sign -", build_script)
        self.assertIn("verify-release.sh", workflow)
        self.assertIn("actions/attest@", workflow)

    def test_minimum_macos_gates_exercise_the_installed_native_app(self) -> None:
        for name in ("macos-ci.yml", "release.yml"):
            workflow = (ROOT / ".github/workflows" / name).read_text()
            with self.subTest(workflow=name):
                self.assertIn("Tools/scripts/test-release-install.sh --native-ui ", workflow)

    def test_publish_requires_the_minimum_os_and_provenance_gates(self) -> None:
        workflow = (ROOT / ".github/workflows/release.yml").read_text()
        publish = workflow.split("  publish:", 1)[1]
        self.assertIn("needs: [release-package, minimum-macos-gate, provenance]", publish)
        self.assertIn('if gh release view "$RELEASE_TAG"', publish)
        self.assertIn("--verify-tag", publish)
        self.assertNotIn("--clobber", publish)


if __name__ == "__main__":
    unittest.main()
