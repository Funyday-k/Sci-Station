# Versioned backlog

This is the initial traceability register for the governance work. Entries are repository-local identifiers, not GitHub Issue numbers. When an Issue is opened, add its real URL here. Completion means implementation plus verification evidence; planned architecture is not an existing product capability.

## GOV-001 — Repository governance and delivery gates

- Priority: P0. Status: implemented in this change; hosted CI results follow its PR.
- GitHub tracking: https://github.com/Funyday-k/Sci-Station/issues/1
- Scope: protected `main`/transitional `dev`, required aggregate CI, private reporting, repository metadata, contributing/security/templates, version checks and traceable changes.
- Acceptance: live branch protection requires PR and `Required CI`; all jobs are aggregate dependencies; docs and versions are checked in PR and release workflows; an empty PR template fails traceability.
- Decisions: [ADR-0001](architecture/ADR-0001-repository-governance.md), [versioning policy](VERSIONING.md).
- Evidence: [CI workflow](../.github/workflows/macos-ci.yml), [settings payload](../.github/repository-settings.json), `Tools/tests/test_governance.py`. Validate remote state with the commands in [GOVERNANCE](GOVERNANCE.md).

## ARCH-001 — Application state boundaries

- Priority: P1. Status: initial extraction present; further domain isolation planned.
- GitHub tracking: https://github.com/Funyday-k/Sci-Station/issues/3
- Current implementation: AppViewModel facade, ten focused extensions and Workspace/Library/Knowledge/Recommendation/Agent/Navigation stores; total family and published-state budgets prevent uncontrolled growth.
- Next acceptance: move transaction and business decisions into tested Core use cases, reduce cross-domain observers and facade forwarding state without changing workspace cancellation or recovery behavior.
- Decision: [ADR-0002](architecture/ADR-0002-application-state-and-testing.md).
- Evidence: `AppDomainStoreTests`, `AppDomainStores`, `check-appviewmodel-architecture.sh`. Splitting files is an intermediate structural step, not proof that all coupling is removed.

## TEST-001 — Domain-based legacy verification

- Priority: P1. Status: runner split in this change; continued migration planned.
- GitHub tracking: https://github.com/Funyday-k/Sci-Station/issues/4
- Acceptance for this change: preserve all legacy check names and assertions, group checks by domain, share fixtures, retain a fail-fast-on-empty filter and fail-on-any-check exit status, and run the full suite in CI.
- Next acceptance: migrate cohesive domain suites to Swift Testing with equivalent assertions, then remove the corresponding legacy registration only after coverage parity is shown. Keep subprocess/system scenarios in the integration runner when appropriate.
- Evidence: `Tools/SciStationCoreTestRunner/Suites/`, `Tools/SciStationCoreTestRunner/Support/`, `Tests/SciStationCoreTests/` and the runner architecture gate.

## KNOW-001 — Knowledge Architecture V1

- Priority: P1. Status: proposed; no target release committed.
- GitHub tracking: https://github.com/Funyday-k/Sci-Station/issues/5
- Scope: source-backed KnowledgeAtom records, relations, repository boundaries and graph projections.
- Acceptance before implementation: review storage and migration, stable identifiers, evidence provenance, approval semantics, deletion/rebuild behavior, and tests; accept an RFC and write the resulting ADR.
- Proposal: [RFC-0001](rfcs/RFC-0001-knowledge-architecture.md).

## REL-001 — Verified certificate-free public distribution

- Priority: P1. Status: pipeline present; first release through the new pipeline remains to be executed.
- GitHub tracking: https://github.com/Funyday-k/Sci-Station/issues/6
- Distribution model: ad-hoc signed macOS app and bundled sidecar, with no Apple Developer ID certificate and no Apple notarization.
- Acceptance: tag reachable from `main`, full tests, matching versions, increasing build number, valid ad-hoc signatures and entitlements, arm64 and deployment-target verification, DMG/ZIP checksums, macOS 15 install/upgrade smoke tests, documented first-launch Gatekeeper behavior, and GitHub build provenance.
- Evidence: [release workflow](../.github/workflows/release.yml), `Tools/scripts/package-release.sh`, `Tools/scripts/verify-release.sh`, and [developer guide](DEVELOPER.md).
- Security boundary: the release must never silently claim Apple developer identity or notarization. Downloaders are expected to verify the GitHub Release source, SHA-256, or provenance before explicitly allowing the app in macOS Privacy & Security when required.
