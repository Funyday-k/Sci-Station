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

- Priority: P1. Status: focused stores and the paper-project membership use case are implemented; further domain isolation remains planned.
- GitHub tracking: https://github.com/Funyday-k/Sci-Station/issues/3
- Current implementation: AppViewModel facade, ten focused extensions and Workspace/Library/Knowledge/Recommendation/Agent/Navigation stores; total family and published-state budgets prevent uncontrolled growth.
- Delivered increment: project membership, core, pinned, purpose and folder mutations use a Core use case; metadata updates preserve unsaved UI drafts and unknown YAML fields. A failed metadata update conditionally compensates only the affected association. `PaperProjectMembershipTests` covers failures, concurrent changes, cancellation, drafts and workspace revisions.
- Next acceptance: continue moving other business decisions into tested Core use cases and reduce cross-domain observers and facade forwarding state. Cross-process crash recovery is not provided by the two-file compensation scheme; see ADR-0003.
- Decision: [ADR-0002](architecture/ADR-0002-application-state-and-testing.md).
- Evidence: `AppDomainStoreTests`, `AppDomainStores`, `check-appviewmodel-architecture.sh`. Splitting files is an intermediate structural step, not proof that all coupling is removed.

## TEST-001 — Domain-based legacy verification

- Priority: P1. Status: domain runner split and five MarkdownRepository checks migrated to Swift Testing; continued migration planned.
- GitHub tracking: https://github.com/Funyday-k/Sci-Station/issues/4
- Acceptance for this change: preserve all legacy check names and assertions, group checks by domain, share fixtures, retain a fail-fast-on-empty filter and fail-on-any-check exit status, and run the full suite in CI.
- Next acceptance: migrate cohesive domain suites to Swift Testing with equivalent assertions, then remove the corresponding legacy registration only after coverage parity is shown. Keep subprocess/system scenarios in the integration runner when appropriate.
- Delivered increment: `MarkdownRepositoryTests` preserves the load/save, create, absolute-path rejection, rename and archive assertions with isolated fixtures. The corresponding legacy registrations were removed after equivalent assertions passed. Both test entry points remain required.
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

## READ-001 — Source-backed paper reading and reviewed writeback

- Priority: P1. Status: implementation and bounded public-paper validation completed; scientific content still requires human review.
- Scope: actual body evidence before paper answers and writeback, citations in the proposed file body, optional read pagination, recoverable invalid tool arguments, approval/checkpoint restoration, correctly paired single-pending revision feedback, and consistent bibliography keys.
- Evidence: `PaperReadingWorkflowTests`, `BibTeXExportTests`, the default Swift Loop, and public-paper checks on 2026-10-16 using arXiv 2404.10066v1, 2402.18535v2 and 2405.12267v2.
- Measured behavior: all three real PDFs imported and produced non-placeholder PDFKit text; metadata, project links, tasks, notes and bibliography survived repository reopening. Bibliography keys match app citekeys and duplicate appends preserve bytes. The configured model produced three substantive drafts; rejection did not write, and a separate process restored each checkpoint and saved/reloaded identical content after test approval.
- Boundaries: PDFKit fallback did not extract figure assets or structured display math. Import metadata was supplied from verified public article records, so this is not an automatic-metadata-provider acceptance result. Model tests used public HTML-derived text and production Core services; UI, PDF conversion and model quality are separate checks. The samples still contain terminology, parameter-dependence, citation-location and length issues. One bounded live feedback revision per paper also completed through persisted/reloaded reconstructions of the original pending states, preserving actual recorded evidence. Each returned to a fresh approval pause without modifying the original saved note. The targeted factual errors improved, but parameter conditions, citation precision and compression requirements remain partly unmet; the revised drafts were not approved. The single-pending request protocol is also covered by a provider-request fixture. General multi-tool batches that pause before processing sibling calls still need separate resume-protocol work. Test approval is not human scientific acceptance. Mechanical source checks do not establish that a claim is supported.
- Experimental sidecar paper-reading scaffolds cannot request approval or present themselves as completed scientific notes. Swift Loop remains the default.
