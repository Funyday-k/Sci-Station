# Changelog

All notable user-facing changes to Sci-Station are tracked in this file.

This project follows the release process in `docs/development/versioning/ReleaseProcess.md` and the versioning policy in `docs/development/versioning/VersioningPolicy.md`.

## [Unreleased]

### Added

- None yet.

### Changed

- None yet.

### Fixed

- None yet.

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
- Performance foundations: extracted `TodoQueries` (behavior-preserving todo filtering and sorting) and an `AgentStreamStore` that isolates high-frequency streaming-text updates from app-wide view invalidation.

### Fixed

- Added a formal version-management and release-process foundation for the beta line.
- The AI assistant can now read user-selected PDF text through the selection action bar.

### Known Issues

- App `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` are still unchanged until packaging is explicitly requested.
- The PDF right-rail tab bar redesign (vertical icon style) and the pinned/narrow AI chat layout are still in progress.

## [0.1.0] - 2026-06-08

### Status

- Initial beta/test version baseline.

### Notes

- App version is currently configured in Xcode build settings as `MARKETING_VERSION = 0.1.0` and `CURRENT_PROJECT_VERSION = 1`.
- Diagnostics export records `app_version` using `CFBundleShortVersionString` and `CFBundleVersion`.

[Unreleased]: https://github.com/Funyday-k/Sci-Station/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/Funyday-k/Sci-Station/releases/tag/v0.2.0
[0.1.0]: https://github.com/Funyday-k/Sci-Station/releases/tag/v0.1.0
