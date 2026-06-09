# Proposal <version>: <title>

## 0. Metadata

- Version:
- Branch:
- Type: Feature / Fix / Performance / Docs / Test / Release
- Owner:
- Date:
- Status: Draft / In Progress / Ready for Review / Done
- Source feedback: none / local user-feedback item summarized by AI

## 1. Goal

Describe the user-visible or engineering outcome. Keep this section short and testable.

## 2. Non-goals

List what must not be changed in this proposal.

## 3. Current state

Summarize relevant code, docs, data paths, bugs, and known constraints.

## 4. Scope

### 4.1 User-facing changes

- [ ]

### 4.2 Engineering changes

- [ ]

### 4.3 Documentation changes

- [ ]

### 4.4 Testing changes

- [ ]

## 5. Data and compatibility

- New data paths:
- Changed data paths:
- Schema changes:
- Migration strategy:
- Rollback strategy:
- Privacy impact:

## 6. Implementation plan for AI

AI should execute these steps in order:

1. Read this Proposal and related module docs.
2. Inspect the authoritative code/docs entry points.
3. Implement the smallest safe change.
4. Update tests and docs.
5. Update changelog and release record.
6. Summarize results using `ImplementationSummaryTemplate.md`.

## 7. Tasks

- [ ] P<version>.1:
- [ ] P<version>.2:
- [ ] P<version>.3:

## 8. Validation

Required:

- [ ] `swift run --quiet SciStationCoreTestRunner`
- [ ] `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -configuration Debug -destination 'platform=macOS' build`

Conditional:

- [ ] `.venv/bin/python -m pytest AgentRuntime/tests/uitest/ -q`
- [ ] UI smoke scenario:
- [ ] Manual regression:

## 9. Changelog draft

### Added

-

### Changed

-

### Fixed

-

### Known Issues

-

## 10. Release notes draft

Write concise user-facing release notes here.

## 11. Completion summary

Fill this when done or link to an implementation summary.
