# Changelog

All notable user-facing changes to Sci-Station are tracked in this file.

Development, validation, versioning, and release conventions are maintained in `docs/DEVELOPER.md`.

## [Unreleased]

### Added

- Added a cancellable workspace session coordinator so overlapping open/create requests cannot publish stale state.
- Added Swift Testing coverage, macOS CI, repository-hygiene checks, and a Codex build-and-run environment.
- AI Lab now shows a visible collaboration/status rail with runtime, evidence, writeback, Prompt, and MCP summaries derived from existing run state.
- Prompt patch review now records rationale/source, impact scope, rollback hints, and explicit Apply/Reject decisions.
- Skill Manager now exposes catalog/search/import/toggle/trust basics with confirmation before enabling or trusting workspace skills.

### Changed

- Set macOS 15 and Apple Silicon as the supported baseline, aligned local Xcode builds with Sign to Run Locally, and made certificate-free release packaging default to ad-hoc signing with an explicit unsigned option.
- Reworked the AI Lab conversation and composer into a borderless, responsive layout that remains usable at narrow window sizes.
- Tightened home, project, library, settings, PDF, and shell layouts for more stable native macOS resizing and presentation.
- Consolidated tracked development, validation, compatibility, signing, and release guidance in `docs/DEVELOPER.md`; local process notes under `docs/development/` are no longer versioned.
- Updated AI platform documentation to state Swift Loop is the production default, sidecar/Auto remain experimental, Prompt/Skill/MCP coverage is auditable but still beta, and synthetic/sample evidence is not production evidence.
- AI Lab writeback status now treats Brief/Wiki/Tasks as first-class target kinds with target path, diff/summary, risk, and approval state.

### Fixed

- Prevented workspace-relative file operations from escaping the selected Research Root during imports, moves, and legacy migration.
- Removed SwiftUI state-update loops and unstable layout feedback paths that produced runtime warnings during navigation and resizing.
- AI run records now retain runtime provenance, prompt metadata, and fallback reasons across replay/debug paths.
- Remote MCP status now reports discovery, credential resolution, and liveness instead of collapsing to a generic unsupported state.
- Sidecar production workflows now block artifact drafts when real workspace evidence is unavailable instead of packaging sample evidence as production evidence.

### Known Issues

- None yet.

## [0.2.0] - 2026-06-08

### Added

- Structured architecture, module, process, testing, versioning, release, roadmap, and template documentation.
- AI-executable Proposal workflow and implementation-summary template.
- Gitignored user feedback intake area for user requests, bugs, questions and feature ideas.
- Design-system foundations: extended `SciStationDesignTokens` (spacing scale, corner radii, semantic colors, typography roles) and a reusable component kit (`SciBadge`, `SciSectionCard`, `SciEmptyState`, `SciActionButton`).
- AI Lab selection workflow: an `询问 AI` / `Ask AI` quick action that hands the current PDF text selection to the assistant for explanation, alongside localized Summarize and Todo-draft selection actions.
- `0.2.0` Proposal and release record.

### Changed

- Replaced historical taskbook-style development docs with a module/process/version/release structure.
- Separated raw user feedback from AI-maintained development documentation.
- Updated root and developer documentation links for the structured development workflow.
- AI Lab: localized assistant mode labels to `询问` / `助理` (`ask` / `agent`), constrained the reasoning (`思考过程`) box width, and removed the timestamp from tool-call rows.
- PDF reader right rail: made the drag-to-resize handle visible and discoverable.
- PDF reader right rail: replaced the segmented context picker with a vertical icon tab bar, and made the AI panel full-height so its composer stays pinned to the bottom (incl. narrow-rail layout).
- Performance foundations: extracted `TodoQueries` (behavior-preserving todo filtering and sorting) and an `AgentStreamStore` that isolates high-frequency streaming-text updates from app-wide view invalidation.

### Fixed

- Added a formal version-management and release-process foundation for the beta line.
- The AI assistant can now read user-selected PDF text through the selection action bar.

### Known Issues

- App `MARKETING_VERSION` set to `0.2.0` and `CURRENT_PROJECT_VERSION` to `2`; release packaging had not yet been performed for that build.

## [0.1.0] - 2026-06-08

### Status

- Initial beta/test version baseline.

### Notes

- App version is currently configured in Xcode build settings as `MARKETING_VERSION = 0.1.0` and `CURRENT_PROJECT_VERSION = 1`.
- Diagnostics export records `app_version` using `CFBundleShortVersionString` and `CFBundleVersion`.

[Unreleased]: https://github.com/Funyday-k/Sci-Station/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/Funyday-k/Sci-Station/releases/tag/v0.2.0
[0.1.0]: https://github.com/Funyday-k/Sci-Station/releases/tag/v0.1.0
