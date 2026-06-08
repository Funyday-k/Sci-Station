# Implementation Summary: 0.2.0 Documentation Reset, Foundations and AI/PDF UX

## Metadata

- Version: `0.2.0`
- Branch: `release/0.2.0`
- Date: 2026-06-08
- Proposal: `docs/development/proposals/Proposal-0.2.0.md`
- Commit range: pending

## Completed work

- Rebuilt `docs/development/` as a clean development documentation center.
- Removed the old taskbook-oriented development documentation tree.
- Added architecture, module, process, testing, versioning, release, roadmap and template documentation.
- Added `docs/user-feedback/` as a human-facing intake area, with local gitignored inbox/drafts/archive-local folders.
- Added `0.2.0` Proposal and release record.
- Added root `CHANGELOG.md` with `0.1.0` baseline and `0.2.0` documentation reset entry.
- Updated root README, developer docs and UI automation README references to the new structure.
- Landed Phase 0 foundations: extended `SciStationDesignTokens`, added the `Sci*` component kit, and extracted `TodoQueries` and `AgentStreamStore` (see `Proposal-Phase0-Foundations.md`).
- Landed AI Lab + PDF reader UX fixes: localized assistant mode labels (`询问`/`助理`), constrained the reasoning box width, removed tool-call row timestamps, made the right-rail resize handle visible, added the `询问 AI` selection action, switched the right rail to a vertical icon tab bar, and pinned the AI composer with a narrow-rail layout.
- Bumped app `MARKETING_VERSION` to `0.2.0` and `CURRENT_PROJECT_VERSION` to `2`; added `/.github/` to `.gitignore`.

## Files changed

- `CHANGELOG.md`
- `README.md`
- `docs/DEVELOPER.md`
- `AgentRuntime/sci_station_agent/uitest/README.md`
- `docs/development/README.md`
- `docs/development/architecture/`
- `docs/development/modules/`
- `docs/development/process/`
- `docs/user-feedback/`
- `docs/development/proposals/`
- `docs/development/releases/`
- `docs/development/roadmap/`
- `docs/development/templates/`
- `docs/development/testing/`
- `docs/development/versioning/`
- `Sci-Station/UI/SciStationDesignTokens.swift`, `Sci-Station/UI/Components/SciStationComponents.swift`
- `Sci-Station/Tasks/TodoQueries.swift`, `Sci-Station/App/AgentStreamStore.swift`
- `Sci-Station/Agent/AgentModels.swift`, `Sci-Station/UI/AILabWorkspaceView.swift`, `Sci-Station/ContentView.swift`, `Sci-Station/UI/Shell/ShellRightRailViews.swift`

## Data and compatibility impact

- New user data paths: none.
- Changed user data paths: none.
- Schema changes: none.
- Migration required: none.
- Privacy impact: documentation-only; no user data, secrets or Research Root content added.

## Validation results

| Check | Result | Notes |
|---|---:|---|
| `find docs/development -maxdepth 3 -type f` | Passed | New structure contains 37 Markdown files after adding the feedback intake process. |
| `.gitignore` feedback intake rules | Passed | Raw inbox/drafts/archive-local feedback paths are ignored. |
| Stale deleted-doc link scan | Passed | No remaining Markdown references to deleted old taskbook paths were found. |
| `git diff --check` | Passed | No whitespace errors reported. |
| `git status --short` | Passed | Shows expected doc deletions, new docs and reference updates. |
| `swift run --quiet SciStationCoreTestRunner` | Passed | All SciStation core checks passed. |
| `xcodebuild ... build` | Passed | macOS Debug `BUILD SUCCEEDED` after the AI Lab + rail + selection changes. |
| AgentRuntime pytest | Not run | Only README text changed. Run if UI automation code changes. |
| Manual regression | Not run | Not required for documentation-only restructure; run if app version/build is bumped. |

## Changelog entry

### Added

- New development documentation center under `docs/development/`.
- Architecture, module, process, testing, versioning, release, roadmap and template documentation.
- AI-executable Proposal workflow and implementation-summary template.
- Gitignored user feedback intake area for user requests, bugs, questions and feature ideas.
- `0.2.0` Proposal and release record.

### Changed

- Replaced historical taskbook-style development docs with a module/process/version/release structure.
- Separated raw user feedback from AI-maintained development documentation.
- Updated root and developer documentation links to the new development documentation center.

### Fixed

- Added a formal version-management and release-process foundation for the beta line.

### Known Issues

- App `MARKETING_VERSION` is now `0.2.0` and `CURRENT_PROJECT_VERSION` is `2`; packaging/signing/notarization not yet performed.

## Release risks

- Historical taskbook details are removed from the active documentation tree and should be recovered from Git history if needed.
- Packaging remains pending until version/build bump and final automated validation are requested.

## Follow-ups

- App `MARKETING_VERSION` bumped to `0.2.0` and `CURRENT_PROJECT_VERSION` to `2`; packaging/notarization still pending.
- Run full automated validation before creating a release tag or package.
- Add release artifact metadata once packaging is performed.
