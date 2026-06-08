# Proposal Phase 0: Foundations (Design System + AppViewModel Domain Stores)

## 0. Metadata

- Version: `0.2.0` (engineering addition; scope relaxation accepted by owner)
- Branch: `release/0.2.0`
- Type: Performance / UI / Refactor
- Owner: Funyday
- Date: 2026-06-08
- Status: In Progress
- Source feedback: local user request summarized by AI (midterm roadmap, foundations-first)

## 1. Goal

Lay the engineering foundations that the two headline features (P1 AI Lab redo, P2 Todo redo) depend on, so later work does not accrue rework or jank debt:

- A consistent design-token + component layer to replace ad-hoc styling.
- Domain stores extracted from the 10k-line `AppViewModel` so high-frequency state stops triggering app-wide `objectWillChange`.

Outcome is testable: build + core tests stay green, behavior is unchanged, and new tokens/components/stores are adopted in at least one real call site each.

## 2. Non-goals

- No new user-facing features (P1/P2/P5 are separate Proposals).
- No data schema changes; no Research Root path changes.
- No Agent protocol or LLM provider behavior changes.
- No mass UI rewrite; pilot adoption only.
- Do not change observable behavior of Todo/Agent flows during store extraction.

## 3. Current state

- `Sci-Station/UI/SciStationDesignTokens.swift`: only panel/surface/hairline tokens + magic opacities; corner radii `7/8/12` mixed; semantic colors absent; spacing/typography scales absent.
- `Sci-Station/App/AppViewModel.swift`: ~10,372 lines, `@MainActor final class AppViewModel: ObservableObject`, 100+ `@Published`. Any published change fires app-wide invalidation. `HomeDashboardStore` already extracted (`AppViewModel.swift:270-276`) and proves the pattern (focused store + revision tokens).
- Todo state lives on `AppViewModel` (`todos` at `AppViewModel.swift:254`, with `markWorkspaceDashboardChanged` didSet). UI in `Sci-Station/UI/DashboardViews.swift`.
- Agent streaming/session state lives on `AppViewModel`; AI Lab UI in `Sci-Station/UI/AILabWorkspaceView.swift`.

## 4. Scope

### 4.1 User-facing changes

- [ ] None intended (visual parity required). Pilot swaps must not change layout/behavior.

### 4.2 Engineering changes

- [x] A1: Extend `SciStationDesignTokens` with spacing scale, typography roles, semantic colors, unified radii; keep existing API.
- [x] A2: Add `Sci-Station/UI/Components/` with `SciSectionCard`, `SciEmptyState`, `SciBadge`, `SciActionButton`.
- [x] A3: Adopt new tokens/components in one AI Lab spot (permission badge) and one Todo spot (`TodoCardView` project labels).
- [x] B1 (logic slice): Extract `TodoQueries` (date/project filtering, sort, open-count, completion predicates) into `Tasks/` (SciStationCore) and delegate `AppViewModel` + `DashboardViews`; behavior-preserving + unit-tested.
- [ ] B1b (deferred): Promote to an observable `TodoStore` and migrate todo-reading views to observe it (the actual invalidation win; warrants manual UI verification).
- [x] B2 (streaming-text seam): Extract `AgentStreamStore` (`Sci-Station/App/AgentStreamStore.swift`) holding `streamingResponseText` (the ~10fps hot field, AI-Lab-only); `AppViewModel` keeps a forwarding getter, `AgentPanelView` observes the store via an injected `@ObservedObject` at all 4 call sites. Per-token streaming no longer fires app-wide `objectWillChange`.
- [ ] B2b (deferred): Move `agentSessionEvents` + the `agentTimelineItems` machinery into the store too (deeply entangled mutation logic; warrants manual UI verification of Agent streaming).

### 4.3 Documentation changes

- [ ] Update `docs/development/modules/` or architecture notes if store ownership changes meaningfully.
- [ ] Update `CHANGELOG.md` (Changed/Performance) when landed.

### 4.4 Testing changes

- [ ] Add SciStationCore tests for `TodoStore` (mutations, persistence forwarding) and `AgentStore` (event merge/no-op-on-unchanged).
- [ ] Keep existing tests green.

## 5. Data and compatibility

- New data paths: none.
- Changed data paths: none.
- Schema changes: none.
- Migration strategy: not applicable (in-memory refactor; persistence paths unchanged).
- Rollback strategy: revert per-step commits; each store extraction is independent and behavior-preserving.
- Privacy impact: none.

## 6. Implementation plan for AI

Execute in order, building + testing after each step:

1. A1 tokens (zero behavior risk).
2. A2 components.
3. A3 pilot adoption (AI Lab + Todo).
4. B1 `TodoStore` extraction.
5. B2 `AgentStore` extraction.
6. Update tests, changelog, and summary.

## 7. Tasks

- [x] PF0.A1: Extend design tokens.
- [x] PF0.A2: Create core component kit.
- [x] PF0.A3: Pilot adoption in AI Lab + Todo.
- [x] PF0.B1: Extract `TodoQueries` (behavior-preserving logic slice) + core test.
- [ ] PF0.B1b: Observable `TodoStore` + view migration (deferred).
- [x] PF0.B2: Extract `AgentStreamStore` for `streamingResponseText` + wire AI Lab call sites.
- [ ] PF0.B2b: Move session events + timeline machinery into the store (deferred).
- [ ] PF0.V: Changelog + summary when Phase 0 fully lands.

## 8. Validation

Required (after each step):

- [x] `swift run --quiet SciStationCoreTestRunner` (green; one unrelated sidecar handshake test is timing-flaky and passes on rerun)
- [x] `xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -configuration Debug -destination 'platform=macOS' build` (BUILD SUCCEEDED)

Conditional:

- [ ] `.venv/bin/python -m pytest AgentRuntime/tests/uitest/ -q` (if Agent bridge affected)
- [ ] Manual regression: Todo CRUD + AI Lab streaming visually unchanged.

## 9. Changelog draft

### Added

- Added shared design tokens (spacing/typography/semantic colors) and a reusable component kit.

### Changed

- Extracted `TodoStore` and `AgentStore` from `AppViewModel` to reduce app-wide view invalidation.

### Fixed

- Reduced unnecessary SwiftUI invalidation during Agent streaming and Todo updates.

### Known Issues

- Full domain-store split and broad component adoption continue in later phases.

## 10. Release notes draft

Internal foundations release: consistent UI building blocks and reduced view-invalidation churn; no user-facing feature changes.

## 11. Completion summary

In progress. Landed this session (all green): A1 design tokens, A2 component kit (`Sci-Station/UI/Components/SciStationComponents.swift`), A3 pilots, B1 `TodoQueries` (`Sci-Station/Tasks/TodoQueries.swift`) with delegation from `AppViewModel`/`DashboardViews` and a new `todoQueriesDeriveDateProjectSortAndOpenCount` core test, and B2 `AgentStreamStore` (`Sci-Station/App/AgentStreamStore.swift`) isolating the ~10fps streaming-text field from app-wide invalidation (4 `AgentPanelView` call sites updated). Remaining: B1b observable `TodoStore` + view migration, and B2b moving session/timeline state into the agent store — both warrant a dedicated pass with manual UI verification. Recommended manual check now: open AI Lab, send a prompt, confirm streaming renders normally and Todo CRUD/board behave as before.
