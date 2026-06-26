# Changelog

All notable user-facing changes to Sci-Station are tracked in this file.

This project follows the release process in `docs/development/versioning/ReleaseProcess.md` and the versioning policy in `docs/development/versioning/VersioningPolicy.md`.

## [Unreleased]

### Added

- AI Lab now shows a visible collaboration/status rail with runtime, evidence, writeback, Prompt, and MCP summaries derived from existing run state.
- Prompt patch review now records rationale/source, impact scope, rollback hints, and explicit Apply/Reject decisions.
- Skill Manager now exposes catalog/search/import/toggle/trust basics with confirmation before enabling or trusting workspace skills.

### Changed

- Updated AI platform documentation to state Swift Loop is the production default, sidecar/Auto remain experimental, Prompt/Skill/MCP coverage is auditable but still beta, and synthetic/sample evidence is not production evidence.
- AI Lab writeback status now treats Brief/Wiki/Tasks as first-class target kinds with target path, diff/summary, risk, and approval state.

### Fixed

- AI run records now retain runtime provenance, prompt metadata, and fallback reasons across replay/debug paths.
- Remote MCP status now reports discovery, credential resolution, and liveness instead of collapsing to a generic unsupported state.
- Sidecar production workflows now block artifact drafts when real workspace evidence is unavailable instead of packaging sample evidence as production evidence.

### Known Issues

- None yet.

## [0.2.0] - 2026-06-08

### Added

- New development documentation center under `docs/development/`.
- Architecture, module, process, testing, versioning, release, roadmap and template documentation.
- AI-executable Proposal workflow and implementation-summary template.
- Gitignored user feedback intake area for user requests, bugs, questions and feature ideas.
- Design-system foundations: extended `SciStationDesignTokens` (spacing scale, corner radii, semantic colors, typography roles) and a reusable component kit (`SciBadge`, `SciSectionCard`, `SciEmptyState`, `SciActionButton`).
- AI Lab selection workflow: an `询问 AI` / `Ask AI` quick action that hands the current PDF text selection to the assistant for explanation, alongside localized Summarize and Todo-draft selection actions.
- `0.2.0` Proposal and release record.

### Changed

- Replaced historical taskbook-style development docs with a module/process/version/release structure.
- Separated raw user feedback from AI-maintained development documentation.
- Updated root and developer documentation links to the new development documentation center.
- AI Lab: localized assistant mode labels to `询问` / `助理` (`ask` / `agent`), constrained the reasoning (`思考过程`) box width, and removed the timestamp from tool-call rows.
- PDF reader right rail: made the drag-to-resize handle visible and discoverable.
- PDF reader right rail: replaced the segmented context picker with a vertical icon tab bar, and made the AI panel full-height so its composer stays pinned to the bottom (incl. narrow-rail layout).
- Performance foundations: extracted `TodoQueries` (behavior-preserving todo filtering and sorting) and an `AgentStreamStore` that isolates high-frequency streaming-text updates from app-wide view invalidation.

### Fixed

- Added a formal version-management and release-process foundation for the beta line.
- The AI assistant can now read user-selected PDF text through the selection action bar.

### Known Issues

- App `MARKETING_VERSION` set to `0.2.0` and `CURRENT_PROJECT_VERSION` to `2`; packaging/signing/notarization not yet performed.

## [0.1.0] - 2026-06-08

### Status

- Initial beta/test version baseline.

### Notes

- App version is currently configured in Xcode build settings as `MARKETING_VERSION = 0.1.0` and `CURRENT_PROJECT_VERSION = 1`.
- Diagnostics export records `app_version` using `CFBundleShortVersionString` and `CFBundleVersion`.

[Unreleased]: https://github.com/Funyday-k/Sci-Station/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/Funyday-k/Sci-Station/releases/tag/v0.2.0
[0.1.0]: https://github.com/Funyday-k/Sci-Station/releases/tag/v0.1.0
