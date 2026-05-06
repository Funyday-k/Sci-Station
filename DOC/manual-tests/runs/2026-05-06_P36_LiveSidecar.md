# Manual Test Report

## Basic Info

- Date: 2026-05-06
- Tester: GitHub Copilot
- Task: P36 Live Sidecar Wiring, Evidence Navigation, Workspace Template Foundation
- Module: AI Lab / Sidecar Runtime / Evidence Artifact / Workspace Modules
- Commit: 5276e9a (working tree not committed)
- macOS: 26.4.1 (25E253)
- Xcode: 26.4.1 (17E202)
- Workspace: Repository fixtures and generated temporary Research Roots from automated tests
- AI enabled: Test-mode deterministic runtime paths
- Sidecar enabled: Enabled for automated sidecar fixture paths; interactive UI not launched
- Embedding enabled: Disabled / deferred to P37

## Automated Baseline

- `swift run SciStationCoreTestRunner`: PASS
- `/Users/funyday/Documents/Sci-Station/.venv/bin/python -m pytest AgentRuntime/tests`: PASS, 24 passed
- `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build`: PASS, `BUILD SUCCEEDED`
- `get_errors` for edited Swift / SwiftUI files: PASS, no errors found

## Test Scope

- [x] Smoke, automated compile and Problems check
- [x] Happy Path, automated runtime/workflow/template fixtures
- [x] Persistence, automated run directory and workspace config assertions
- [x] Permission / Privacy, automated sidecar run-directory and debug zip redaction assertions
- [x] Error / Fallback, automated sidecar coordinator fallback coverage
- [x] Integration, automated Swift/Python contract coverage
- [x] Regression, build and core runner coverage

## Test Cases

### MT07 AI Lab Partial

- ID: MT07-01, MT07-02, MT07-06, MT07-07, MT07-09, MT07-12, MT07-13
- Title: AI Lab plan/run/replay and permission baseline
- Preconditions: SwiftPM core runner fixtures and sidecar runtime fixture
- Steps: Execute `SciStationCoreTestRunner`; inspect compile-time App wiring through Xcode build
- Expected: AI Lab data models, runtime selection, session events, replay, and permission events compile and pass automated assertions
- Actual: Core runner passed; Xcode App build passed
- Result: PASS via automated substitute; interactive UI clicks not executed in this environment
- Notes: No S0/S1 issue found by automated checks

### MT08 Sidecar Runtime

- ID: MT08-01 to MT08-11
- Title: Runtime selector, sidecar health, restart, run directory, debug bundle
- Preconditions: Sidecar fixture runtime and App build
- Steps: Execute sidecar coordinator and debug bundle tests; build App runtime panel wiring
- Expected: Selector changes effective runtime; sidecar health/fallback state is readable; debug bundle zip excludes sensitive patterns
- Actual: Swift core runner passed `sidecarRuntimeCoordinatorResolvesHealthAndSelection` and `debugBundleManifestAndZipExcludeSecrets`; App build passed
- Result: PASS for automated coverage; MT08-05 restart and MT08-08 injected crash/replay are SKIPPED as interactive/manual scenarios
- Notes: Crash state is recorded by coordinator; stable UI injection of a crash was not performed

### MT09 Evidence / Artifact

- ID: MT09-01 to MT09-11
- Title: Evidence refs, source jump, PDF mapping, artifact metadata
- Preconditions: Automated evidence fixture with page mapping metadata
- Steps: Execute Swift evidence source jump test and Python workflow routing tests
- Expected: Evidence source jump returns line descriptors and PDF page when mapping exists; sidecar workflows emit artifacts and evidence files
- Actual: Swift and Python tests passed
- Result: PASS for automated line/PDF mapping coverage; interactive source navigation is SKIPPED
- Notes: No stale/missing UI click-through was manually exercised

### MT10 Workspace Module / Template

- ID: MT10-01, MT10-02, MT10-07, MT10-08, MT10-10
- Title: Minimal and Literature Review template creation, module config, migration safety
- Preconditions: Temporary Research Root fixtures
- Steps: Execute workspace template/module config write and legacy migration tests
- Expected: `settings/workspace_template.yaml` and `settings/workspace_modules.yaml` are created without deleting user data
- Actual: Swift core runner passed `workspaceTemplateModuleConfigWritesAndLegacyMigration`; Xcode build passed Settings menu wiring
- Result: PASS via automated substitute; interactive creation wizard preview clicks are SKIPPED
- Notes: P36 skeleton supports built-in Minimal Workspace and Literature Review templates only

### MT99 Partial Regression

- ID: MT99-01, MT99-02, MT99-06, MT99-07, MT99-10, MT99-11, MT99-12, MT99-14
- Title: Release partial regression
- Preconditions: App build and core runner
- Steps: Run full Xcode App build and core validation
- Expected: App compiles, core workflows pass, no new secret-writing path detected in debug bundle tests
- Actual: Xcode build succeeded; Swift and Python automated suites passed
- Result: PASS for automated baseline; interactive launch/restart checks are SKIPPED
- Notes: Manual App launch was not performed in this tool environment

## Issues Found

| ID | Severity | Module | Description | Repro Steps | Status |
|---|---|---|---|---|---|
| P36-MT-01 | S3 | Manual Testing | Interactive macOS UI clicks were not executed from this environment; coverage is automated substitute plus successful App build. | N/A | Deferred to human/manual pass |

## Final Verdict

- Result: CONDITIONAL PASS
- Required fixes before merge: None found by automated validation
- Can defer: Full interactive MT07/MT08/MT09/MT10/MT99 pass with a real test workspace and UI clicks
- Follow-up tasks: P37 embedding persistent store and retrieval runtime; P38 unified artifact lifecycle