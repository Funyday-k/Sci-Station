# Changelog

All notable user-facing changes to Sci-Station are tracked in this file.

Development, validation, versioning, and release conventions are maintained in `docs/DEVELOPER.md`.

## [Unreleased]

- The desktop meeting window can forward one-time native Codex and supported Claude Code edit approvals for selected project files. The CLI applies the reviewed change and reports its result.

### Added

- Restore the inspector and single-seat AI side panel across the workstation, with resizable panels, a collapsible project tree and draggable project tabs remembered by each workspace.
- Rename, search, archive, and reopen single-seat conversations in AI Lab. Save unsent questions and follow-ups to the active research root and recover them without sending a model request.

- Review a project CLI’s proposed file changes in its meeting, forward a one-time decision, cancel the run, and check its reported outcome.
- Import a paper's Markdown source or adopt a verified PDFKit or MinerU conversion. AI Lab can find and cite its sections and lines, reopen a reviewed quote, and display evidence-linked comparison rows or candidate research tasks.

- Build and launch the combined macOS research workstation with `make run`. Its native window hosts the shared library, PDF reader, project tools, AI Lab, and multi-seat Roundtable.
- Keep one copy of a paper across projects with independent pins, ordering and core status. Preview imports, resume failed items, organize collections and tags, and export citations from the library or reader.
- Follow individual references between Wiki pages, tasks and source passages. Preserve reading position, selected-text offsets and the PDF fingerprint when returning from a meeting.
- Review proposals to write meeting results to notes or tasks, retry a confirmation and recover decisions after a restart. AI Lab can reopen a single-seat session and export redacted diagnostics.
- Preview, enable, and trust local Markdown skills for a specific project. Save an optional public MCP resource endpoint, with confirmation before each connection.
- Inspect each single-seat claim’s citations and reopen verified source excerpts. Formal research templates require cited source text before entering human review.
- Search the active project’s Markdown papers, notes and text materials offline. Optionally use deterministic local ranking, rebuild an index and open the verified original passage by line.
- Choose project modules and dashboard widgets, create tasks with optional project and paper associations, and explicitly connect selected Apple calendars and reminders. Literature discovery keeps ranked runs, filters and feedback.
- Save MinerU tokens and credentials for OpenAI-compatible model profiles in macOS Keychain. The desktop model directory shares these profiles between research workflows.
- Added shared coding-agent guidelines in `AGENTS.md`, imported by `CLAUDE.md`, and included both files in documentation checks.

### Changed

- Roundtable discussions and continuous runs use read-only project file access. AI-file changes go through a host-initiated CLI session and its review controls. Existing meeting histories retain old edit records.

### Fixed

- Close the desktop window during an active meeting or a native folder picker. Pending operations are cancelled, committed records are preserved and the next process can immediately reopen the workspace.
- Reopen meetings under their original project after a folder changes. Verify the active folder grant whenever a project file is accessed.

## [0.2.0] - 2026-10-16

### Fixed

- Keep the welcome page scrollable so its content cannot push sidebar navigation outside the window.
- Return local MCP startup/initialize errors without reading the exit status of an unstarted or still-running process.
- Preserve unsaved paper edits when changing project membership, core status, pins and project classification; safely compensate a failed metadata mirror without overwriting newer associations.
- Require actual paper text and references in reading-note writeback drafts; keep experimental sidecar scaffolds out of approval and distinguish source checks from scientific review.
- Keep read pagination arguments optional and let models correct invalid tool JSON within the existing budgets and approval boundaries.
- Preserve paper intent and executed evidence through approval/resume; recheck edited drafts. Older pending paper writes without evidence snapshots remain readable but require a fresh body read before approval.
- Pair a pending write with an explicit not-executed tool result before sending revision feedback, preserving provider protocol ordering.
- Keep exported BibTeX entry keys aligned with app citekeys while preserving provider fields; reject damaged existing bibliography files without overwriting them.

### Changed

- Verify packaged-app navigation with an independent native macOS UI runner using an isolated initial state and a real Library button click.
- Migrate five Markdown repository checks to isolated Swift Testing suites while retaining equivalent assertions and the remaining integration runner.

- Added contribution/security policies, Issue/PR templates, ownership, versioned backlog, ADR/RFC records, and checked app/runtime version boundaries.
- Added documentation/version/traceability/runner-organization gates and an aggregate required CI check; release tags must point to a commit reachable from main.
- Grouped legacy core verification into domain suites and shared fixtures while preserving check identifiers; unmatched local filters now fail explicitly.
- Corrected the 0.1.0 product status to Developer Preview; tag-triggered publication defaults to prerelease.
- Public release automation now uses verified certificate-free distribution: ad-hoc app/sidecar signing, entitlement and bundle-integrity checks, SHA-256 checksums, macOS install/upgrade smoke tests, and GitHub build provenance. Developer ID signing and Apple notarization are intentionally not required.

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

- Certificate-free distribution requires users to confirm the first launch through Finder or macOS Privacy & Security because the app is not Developer ID signed or notarized.

[Unreleased]: https://github.com/Funyday-k/Sci-Station/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/Funyday-k/Sci-Station/releases/tag/v0.2.0
[0.1.0]: https://github.com/Funyday-k/Sci-Station/releases/tag/v0.1.0
