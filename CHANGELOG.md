# Changelog

All notable user-facing changes to Sci-Station are tracked in this file.

Development, validation, versioning, and release conventions are maintained in `docs/DEVELOPER.md`.

## [Unreleased]

No user-facing changes yet.

## [0.1.0] - 2026-07-11

### Added

- Added a cancellable workspace session coordinator so overlapping open/create requests cannot publish stale state.
- Added Swift Testing coverage, macOS CI, repository-hygiene checks, and a Codex build-and-run environment.
- AI Lab now shows a visible collaboration/status rail with runtime, evidence, writeback, Prompt, and MCP summaries derived from existing run state.
- Prompt patch review now records rationale/source, impact scope, rollback hints, and explicit Apply/Reject decisions.
- Skill Manager now exposes catalog/search/import/toggle/trust basics with confirmation before enabling or trusting workspace skills.
- Structured architecture, module, process, testing, versioning, release, roadmap, and template documentation.
- AI-executable Proposal workflow and implementation-summary template.
- Gitignored user feedback intake area for user requests, bugs, questions and feature ideas.
- Design-system foundations: extended `SciStationDesignTokens` and a reusable component kit.
- AI Lab selection actions for explaining, summarizing, and creating Todo drafts from selected PDF text.

### Changed

- Set macOS 15 and Apple Silicon as the supported baseline, aligned local Xcode builds with Sign to Run Locally, and made certificate-free release packaging default to ad-hoc signing with an explicit unsigned option.
- Reworked the AI Lab conversation and composer into a borderless, responsive layout that remains usable at narrow window sizes.
- Tightened home, project, library, settings, PDF, and shell layouts for more stable native macOS resizing and presentation.
- Consolidated tracked development, validation, compatibility, signing, and release guidance in `docs/DEVELOPER.md`; local process notes under `docs/development/` are no longer versioned.
- Updated AI platform documentation to state Swift Loop is the production default, sidecar/Auto remain experimental, and synthetic/sample evidence is not production evidence.
- AI Lab writeback status now treats Brief/Wiki/Tasks as first-class target kinds with target path, diff/summary, risk, and approval state.
- Localized AI Lab assistant modes, refined reasoning and tool-call presentation, and improved the PDF reader right rail.
- Extracted `TodoQueries` and `AgentStreamStore` to reduce unnecessary app-wide updates.

### Fixed

- Prevented workspace-relative file operations from escaping the selected Research Root during imports, moves, and legacy migration.
- Removed SwiftUI state-update loops and unstable layout feedback paths that produced runtime warnings during navigation and resizing.
- AI run records now retain runtime provenance, prompt metadata, and fallback reasons across replay/debug paths.
- Remote MCP status now reports discovery, credential resolution, and liveness instead of collapsing to a generic unsupported state.
- Sidecar production workflows now block artifact drafts when real workspace evidence is unavailable instead of packaging sample evidence as production evidence.
- The AI assistant can now read user-selected PDF text through the selection action bar.

### Known Issues

- Certificate-free distribution requires users to confirm the first launch through Finder because the app is not Developer ID signed or notarized.

[Unreleased]: https://github.com/Funyday-k/Sci-Station/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Funyday-k/Sci-Station/releases/tag/v0.1.0
