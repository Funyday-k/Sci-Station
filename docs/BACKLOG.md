# Versioned backlog

Entries are repository-local identifiers. Where applicable, each has a GitHub tracking link. Completion requires implementation and verification appropriate to the scope.

## GOV-001 — Repository governance and delivery gates

- GitHub tracking: [Issue #1](https://github.com/Funyday-k/Sci-Station/issues/1).
- Protected `main`, the unconditional `Required CI` aggregate, private reporting and traceability remain the delivery gates. [ADR-0001](architecture/ADR-0001-repository-governance.md) records their introduction; [ADR-0004](architecture/ADR-0004-roundtable-workstation.md) records the transition to a single integration branch.
- Evidence and live verification commands are in [governance](GOVERNANCE.md).

## GOV-002 — Shared coding-agent guidelines

- GitHub tracking: [Issue #8](https://github.com/Funyday-k/Sci-Station/issues/8).
- [AGENTS.md](../AGENTS.md) maps change types to checks and requires reporting skipped verification. [CLAUDE.md](../CLAUDE.md) imports the same instructions. Agent changes follow the same acceptance and review rules as any other contribution.

## ARCH-001 — Application state boundaries

- GitHub tracking: [Issue #3](https://github.com/Funyday-k/Sci-Station/issues/3).
- Historical decisions for application state and association failures are in [ADR-0002](architecture/ADR-0002-application-state-and-testing.md) and [ADR-0003](architecture/ADR-0003-paper-project-membership.md). The current ownership and file recovery paths are described in the [developer guide](DEVELOPER.md) and [workspace guide](workspaces.md).

## TEST-001 — Domain-based legacy verification

- GitHub tracking: [Issue #4](https://github.com/Funyday-k/Sci-Station/issues/4).
- The prior verifier reorganization is part of the historical [state and testing decision](architecture/ADR-0002-application-state-and-testing.md). The Go/Wails regression entry points and cutover obligations are in the [developer guide](DEVELOPER.md) and [RFC-0002](rfcs/RFC-0002-roundtable-workstation.md#validation-and-rollout).

## KNOW-001 — Knowledge Architecture V1

- GitHub tracking: [Issue #5](https://github.com/Funyday-k/Sci-Station/issues/5).
- Status: proposed. [RFC-0001](rfcs/RFC-0001-knowledge-architecture.md) and its [review and recovery proposal](rfcs/knowledge-v1-review-and-recovery.md) preserve the work from [draft PR #12](https://github.com/Funyday-k/Sci-Station/pull/12) for the current host.
- Acceptance before implementation includes stable identity, valid source locators, reviewed revisions, relations, storage, conflict behavior, archive/rebuild and recovery. An accepted RFC and ADR are required before assigning a persisted format.

## REL-001 — Verified certificate-free public distribution

- GitHub tracking: [Issue #6](https://github.com/Funyday-k/Sci-Station/issues/6).
- Acceptance: tag on `main`, consistent version and increasing build number, complete tests, ad-hoc signing with hardened runtime, arm64 deployment target checks, ZIP and DMG with checksums, macOS 15 installation and rollback smoke tests, and GitHub provenance.
- The [release workflow](../.github/workflows/release.yml) enforces the packaging gates. The [developer guide](DEVELOPER.md#package-and-install) documents installation evidence and first-launch Gatekeeper handling.

## READ-001 — Source-backed paper reading and reviewed writeback

- Goal: Show the actual paper body and source locators before a human accepts a proposed research note or task. Preserve annotations, citation keys, chosen evidence and review decisions across reopen, including refusal and stale revisions.
- The prior app validated bounded examples with arXiv 2404.10066v1, 2402.18535v2 and 2405.12267v2. The real PDFs imported and yielded PDFKit text; metadata, project links, notes, tasks and bibliography survived reopen. Model drafts used public HTML-derived body text and verified metadata. PDFKit did not supply structured equations or figure assets in those checks. Bounded feedback improved specific errors while leaving citation precision, parameter conditions and compression unresolved. Human scientific acceptance remains necessary even when checks of source hashes and locators pass.
- For the Go/Wails workflow and its native test, see the [cutover evidence map](rfcs/RFC-0002-roundtable-workstation.md#implementation-and-release-evidence). Fixture-assisted workflow evidence and live provider output are evaluated independently.

## WORK-001 — Single Go/Wails research workstation

- GitHub tracking: [Issue #13](https://github.com/Funyday-k/Sci-Station/issues/13).
- The [accepted RFC](rfcs/RFC-0002-roundtable-workstation.md) and [desktop ADR](architecture/ADR-0004-roundtable-workstation.md) cover one macOS application, research and CLI permissions, compatibility and recovery, and the acceptance evidence required for cutover.
