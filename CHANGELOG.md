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

## [0.1.1] - 2026-06-08

### Added

- New development documentation center under `docs/development/`.
- Architecture, module, process, testing, versioning, release, roadmap and template documentation.
- AI-executable Proposal workflow and implementation-summary template.
- `0.1.1` Proposal and release record.

### Changed

- Replaced historical taskbook-style development docs with a module/process/version/release structure.
- Updated root and developer documentation links to the new development documentation center.

### Fixed

- Added a formal version-management and release-process foundation for the `0.1.x` beta line.

### Known Issues

- App `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` are still unchanged until packaging is explicitly requested.

## [0.1.0] - 2026-06-08

### Status

- Initial beta/test version baseline.

### Notes

- App version is currently configured in Xcode build settings as `MARKETING_VERSION = 0.1.0` and `CURRENT_PROJECT_VERSION = 1`.
- Diagnostics export records `app_version` using `CFBundleShortVersionString` and `CFBundleVersion`.

[Unreleased]: https://github.com/Funyday-k/Sci-Station/compare/v0.1.0...HEAD
[0.1.1]: https://github.com/Funyday-k/Sci-Station/releases/tag/v0.1.1
[0.1.0]: https://github.com/Funyday-k/Sci-Station/releases/tag/v0.1.0
