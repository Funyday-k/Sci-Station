# P39 Manual Test Run: Workspace Module Registry V1

Date: 2026-05-06
Scope: MT01 partial, MT07 partial, MT09 partial, MT10 partial, MT99 partial

## Summary

Status: Passed for automated/core coverage. GUI click-through remains recommended before release because P39 adds visible Settings and sidebar gating behavior.

P39 implemented the built-in Workspace Module Registry V1, module config persistence/migration, route/project tab/workflow gating, artifact kind fallback display, and Permission Dock module-scope explanation. No module setting currently grants write permission; writes still flow through existing Swift host approval paths.

## Automated Validation

| Check | Result | Notes |
|---|---:|---|
| `get_errors` on edited Swift files | Passed | No diagnostics in edited Swift/SwiftUI/Agent files |
| `swift run SciStationCoreTestRunner` | Passed | Includes registry snapshot, parse/migration, route/workflow gating, artifact kind mapping, dependency warning checks |
| `/Users/funyday/Documents/Sci-Station/.venv/bin/python -m pytest AgentRuntime/tests` | Passed | 28 passed, including disabled workflow fallback without artifact |
| `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build` | Passed | Existing `ChatMarkdownWebView` actor-isolation warnings remain |
| Targeted privacy keyword scan | Passed | No API key/secret/password/Keychain/prompt-response matches in module config generator or sidecar gating code |

## Manual Cases

| ID | Result | Evidence / Notes |
|---|---:|---|
| MT10-P39-01 legacy workspace creates `workspace_modules.yaml` | Passed by CoreTestRunner | Legacy V0 config migrates to `schema_version: 1`; existing `raw/papers` remains |
| MT10-P39-02 disabling a module hides route without deleting data | Passed by CoreTestRunner | Disabled `paper-library` hides Library and PDF Reader routes; no data deletion path added |
| MT10-P39-03 dependency warning appears | Passed by CoreTestRunner | `code` enabled without `ai-lab` emits `disabled-dependency:code:ai-lab` |
| MT10-P39-04 AI Lab workflow list follows enabled modules | Passed by Swift + Python tests | Swift filters `enabledAgentWorkflowIDs`; sidecar refuses disabled routed workflows and returns no artifact |
| MT10-P39-05 Draft Inbox filters by module/artifact kind | Partial | P38 Draft Inbox full store/filter UI is not present; P39 adds artifact kind descriptors and unknown-kind fallback in AI Lab event preview |
| MT10-P39-06 Permission Dock shows module approval scope | Passed by code path | Dock items now include module-scope explanation; approval decision logic remains unchanged |
| MT10-P39-07 future modules exist but hidden by default | Passed by CoreTestRunner | `code`, `datasets`, `experiments`, `citation-graph`, `recommendation`, `writing`, `theory-notes` declared disabled by default |
| MT10-P39-08 module config privacy scan | Passed | Generated schema contains module metadata only; targeted scans found no secret fields in generator/gating code |

## GUI Smoke Steps For Release

1. Launch the app and open an existing research root.
2. Open Settings -> Workspace and verify the Workspace Modules panel shows enabled, disabled, warning, workflow, and path rows.
3. Disable `paper-library` manually in `settings/workspace_modules.yaml`, reopen the root, and verify Library/PDF Reader entries are hidden while files remain on disk.
4. Open AI Lab with `paper_reading` disabled by module requirements and verify sidecar returns a no-artifact fallback message.
5. Trigger a write-capable tool plan and verify Permission Dock still asks for approval even when module scope text is shown.

## Known Limitations

- P39 does not implement the full P41 enable/disable settings UX.
- P39 does not implement the full P38 Draft Inbox artifact lifecycle; artifact kind mapping is exposed as registry descriptors and AI Lab safe fallback display.
- Directory repair metadata is present; full repair UI is deferred to P41.