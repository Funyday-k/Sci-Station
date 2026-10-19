# ADR-0002: Focused application state and incremental test migration

- Status: Accepted for this change; documents the existing store extraction and the runner reorganization.
- Requirements: [ARCH-001](../BACKLOG.md#arch-001--application-state-boundaries), [TEST-001](../BACKLOG.md#test-001--domain-based-legacy-verification).

## Context

AppViewModel coordinates many domains. Its existing extraction into a facade, domain extensions and Core stores improves navigation and testability, but the entire family remains large. The legacy core runner also contains substantial integration coverage that must survive reorganization.

## Decision

Keep domain state in focused stores and pure/business decisions in Core services or use cases. Keep AppViewModel as the UI-facing coordinator while progressively narrowing its API. Enforce both individual-file and total-family/published-state budgets so file splitting alone cannot hide growth.

Organize legacy checks under named domain suites with common support fixtures and a minimal entry point. Preserve check identifiers and assertions, expose suite and substring filters for local investigation, fail when a filter matches no checks, and execute all suites in CI. New unit/domain tests use Swift Testing. Migrate existing cases in bounded groups and delete duplicates only after assertion parity is verified.

### Recommendation presentation increment (Issue #3)

`RecommendationStore` owns history selection, the existing archive fallback, refresh presentation transitions and per-destination import admission. Recommendation views observe this store directly, without AppViewModel forwarding properties or app-wide import-progress publications. `RecommendationFeedbackStore` derives display feedback from the latest candidate-alias match with global or matching-project scope. AppViewModel retains asynchronous service calls, localized messages, cross-domain import coordination and navigation.

Workspace snapshots continue to capture recommendation presentation state. In-flight import IDs stay outside snapshot/restore/reset because they belong to coordinator tasks; only completion releases their admission guard, matching the previous facade-owned sets. This increment does not change workspace staging, route restoration or membership compensation.

Existing limitations remain: archiving the selected run replaces only that run with the first remaining history entry; candidate count, feedback and status messages are not recomputed. Recommendation tasks retain their existing lifetime and do not gain workspace-generation checks in this extraction. Broader cancellation and stale-result handling remain part of open ARCH-001 work.

## Alternatives

A simultaneous rewrite of app state and all tests increases regression risk and obscures lost coverage. Keeping one giant runner makes ownership and diagnosis harder. Splitting AppViewModel into extensions without moving state or decisions cannot complete the architectural refactor.

## Consequences

The runner uses internal support declarations within its executable module so suites in different files can share fixtures; this does not expand the public Core API. Test execution remains sequential to preserve fixture assumptions. Two test entry points remain during migration and both are required gates. Remaining state isolation work stays visible in the backlog.

## Validation

Compare the complete old and new check-name sets and the moved assertion bodies; run Swift Testing and all integration suites. Runner and AppViewModel budgets fail if entry points or domain files grow beyond their limits. Retain workspace cancellation, persistence recovery, permission and protocol failure-path tests during later extraction.

For the recommendation increment, `RecommendationStoreTests` verifies history selection/archive fallback, refresh retention, latest applicable feedback and per-destination import admission with exact observable-change assertions. The focused five tests, all 120 Swift tests and all 323 legacy checks passed; Core coverage was 26.78% against the 14.0% floor. Architecture, repository/document/version hygiene, tooling tests and pinned Swift style gates passed, as did the unsigned macOS Release build. The Accessibility probe reported `trusted: false`, so recommendation-screen interaction remains unverified and requires manual validation. No navigation behavior changed.
