# Proposal 0.1.1: Documentation Reset and Version Management

## 0. Metadata

- Version: `0.1.1`
- Branch: `release/0.1.1`
- Type: Docs / Release / Process
- Owner: Funyday
- Date: 2026-06-08
- Status: Ready for Review

## 1. Goal

Create the documentation, versioning and release-management foundation needed for the `0.1.x` beta line. This Proposal is designed to be executable by AI: it defines what to change, how to summarize the work, how to update changelog, and how to prepare a new version for packaging.

## 2. Non-goals

- Do not introduce major user-facing features.
- Do not change Research Root schema.
- Do not change Agent protocol.
- Do not rewrite AppViewModel or product architecture.
- Do not commit build artifacts, private workspace data or secrets.

## 3. Current state

- App baseline is `0.1.0` beta.
- Xcode version settings currently use `MARKETING_VERSION = 0.1.0` and `CURRENT_PROJECT_VERSION = 1`.
- Old development docs were organized as many historical Proposal taskbooks.
- `CHANGELOG.md` was missing before this branch.
- Release and version-management rules were not centralized.

## 4. Scope

### 4.1 Documentation changes

- [x] Remove old `docs/development/` taskbook-based structure.
- [x] Create new `docs/development/README.md`.
- [x] Create architecture docs.
- [x] Create module docs.
- [x] Create process docs.
- [x] Create testing docs.
- [x] Create versioning docs.
- [x] Create release records.
- [x] Create reusable templates.

### 4.2 Version-management changes

- [x] Define SemVer policy.
- [x] Define build number rule.
- [x] Define branch and tag policy.
- [x] Define release checklist.
- [ ] Optionally bump Xcode `MARKETING_VERSION` to `0.1.1`.
- [ ] Optionally bump Xcode `CURRENT_PROJECT_VERSION` to next build number.

### 4.3 AI workflow changes

- [x] Create AI-assisted development process.
- [x] Create Proposal template for AI execution.
- [x] Create implementation summary template.
- [x] Create changelog entry template.

### 4.4 Repository reference updates

- [x] Update root `README.md` documentation links.
- [x] Update `docs/DEVELOPER.md` development documentation links.
- [x] Update `AgentRuntime/sci_station_agent/uitest/README.md` stale Proposal references.

## 5. Data and compatibility

- New data paths: none in user Research Root.
- Changed data paths: none in user Research Root.
- Schema changes: none.
- Migration strategy: not applicable.
- Rollback strategy: revert docs branch or restore prior docs from Git history.
- Privacy impact: documentation-only; no user data should be added.

## 6. Implementation plan for AI

AI should execute these steps:

1. Confirm branch is `release/0.1.1`.
2. Rebuild `docs/development/` with the new structure.
3. Update root and developer documentation links.
4. Update `CHANGELOG.md` with `0.1.1` draft.
5. Update `releases/0.1.1.md` with completed scope.
6. Run link/file structure checks.
7. If requested, bump Xcode version/build.
8. Summarize changes using `templates/ImplementationSummaryTemplate.md`.

## 7. Tasks

- [x] P0.1.1.1: Create `release/0.1.1` branch.
- [x] P0.1.1.2: Create root `CHANGELOG.md`.
- [x] P0.1.1.3: Delete old development taskbook tree.
- [x] P0.1.1.4: Rebuild development documentation architecture.
- [x] P0.1.1.5: Add versioning and release docs.
- [x] P0.1.1.6: Add Proposal/release/test templates.
- [x] P0.1.1.7: Update stale documentation links.
- [x] P0.1.1.8: Finalize changelog and release record.
- [ ] P0.1.1.9: Optional app version/build bump.
- [x] P0.1.1.10: Run documentation validation and produce implementation summary.

## 8. Validation

Required:

- [x] `find docs/development -maxdepth 3 -type f | sort`
- [x] Search repository Markdown for stale deleted-doc links.
- [x] `git status --short`
- [x] `git diff --check`

If App project version changes:

- [ ] `swift run --quiet SciStationCoreTestRunner`
- [ ] `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -configuration Debug -destination 'platform=macOS' build`

## 9. Changelog draft

### Added

- Added a new development documentation center.
- Added versioning, release and packaging policy docs.
- Added AI-executable Proposal and release templates.
- Added `0.1.1` Proposal and release record.

### Changed

- Replaced old historical taskbook-based docs with a module/process/version/release structure.

### Fixed

- Fixed missing version-management foundation for beta releases.

### Known Issues

- App version/build bump remains optional until packaging is requested.

## 10. Release notes draft

`0.1.1` prepares Sci-Station for repeatable beta releases by introducing structured development docs, version-management rules, release records, AI-executable Proposal templates and changelog discipline.

## 11. Completion summary

Documentation restructure is complete and ready for review. See `ImplementationSummary-0.1.1.md`. App version/build bump remains optional until packaging is requested.
