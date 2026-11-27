# RFC-0003 — Research record versions and conversion recovery

Accepted by the maintainer on 2026-11-27 for [Issue #27](https://github.com/Funyday-k/Sci-Station/issues/27). The maintainer chose local MinerU submission receipts and version 1 on the next normal save of project and paper records. The maintainer also chose a fresh conversation history when an existing project is assigned to a different directory.

## Project and paper records

Research owns project IDs, directory grants and paper identities. A project keeps its ID through a directory change. Roundtable resolves a meeting's project and its current authorized directory through Research. Legacy path-indexed settings remain available for inspection and explicit selection.

Project and paper files carry a top-level integer `schema_version`. A missing field denotes the supported, unversioned format. New records and ordinary saves write version 1. Opening a file leaves its bytes intact. An incompatible version stops the operation and preserves the original. Existing revisions continue to detect concurrent edits. Public API records retain their established representation.

## Reassigning a project directory

Before replacing the directory, show the researcher which conversation data will be removed and require confirmation. Cancel leaves the original grant and history intact. Keep the project ID. A confirmed replacement clears all single-seat conversations, Roundtables and unsent drafts owned by that ID, including archived sessions from earlier assignments. Returning to an earlier directory starts another empty history. Keep the contents of external directories, shared papers, research notes and tasks. Other projects and conversations without a project keep their own histories.

Prevent a new assignment while an affected conversation is active. Commit a new conversation generation and a pending-cleanup marker with the directory change. Complete any interrupted cleanup before opening that project's new history. Stale windows must reload before they can save a draft or create a conversation. A change of project name or a new approval for the same directory does not erase conversations.

## Conversion requests

Before requesting a new MinerU batch, record the submission intent locally under the current library. Record a known batch number before starting its upload. A subsequent attempt can then resume the known batch. A connection loss with an unknown outcome requires the user to check the provider or explicitly choose to submit again.

Each version 1 receipt belongs to a paper and its original PDF fingerprint. It contains an attempt identifier, state and an optional batch number. Per-source locking serializes submissions and atomic file replacement protects the receipt on interruption. Credentials and upload URLs stay out of the receipt.

## Alternatives, recovery and verification

Bulk rewriting on launch would change old records simply by inspecting them. Keeping the batch only in a browser tab would lose recovery state across a restart. On-demand writes preserve existing libraries and allow recovery after the app quits. A recent request with an unknown outcome may require human review at the provider.

Back up the research root before downgrading. Reopen a matching backup with the app version that created it. Test old records, a normal save, unsupported versions, concurrent writers and restart after both a known batch and an interrupted submission. The adopted decision is recorded in [ADR-0005](../architecture/ADR-0005-project-records-and-conversion-recovery.md).
