# ADR-0003: Paper-project association updates and recovery

- Status: Accepted for this change; records the bounded Core use case authorized for the workflow-hardening increment.
- Requirement: [ARCH-001](../BACKLOG.md#arch-001--application-state-boundaries).

## Context

Association changes previously coordinated link and paper metadata writes in AppViewModel. Saving a selected UI draft as the metadata mirror could persist unrelated unsaved edits, while a full workspace reload could discard those edits. The two files can fail independently.

## Decision

`PaperProjectMembershipUseCase` serializes association mutations, writes current repository state, and patches only `project_ids` and `core_project_ids` in the paper metadata. Known unrelated fields and unknown YAML structure are preserved. The UI refreshes papers and links, merges untouched association fields into the draft, and rejects stale results using workspace and request revisions.

If the metadata write throws, compensate only the affected link when its committed entry and in-memory association revision are still current. Preserve unrelated changes and reject compensation across a newer update. Expose idempotent metadata synchronization from current links for recovery without replaying a toggle. Keep legacy metadata fallback behavior and existing file formats.

## Alternatives

Persisting the UI draft or reloading the entire workspace retains the original failure modes. Rewriting the complete links document from an old snapshot could destroy concurrent changes. A durable journal could provide stronger crash recovery, but introduces a new persistent protocol and is outside this increment.

## Consequences

This is conditional compensation around two atomic file writes, not a crash-atomic transaction. Process termination between writes has no automatic journal recovery. Independent repository instances and external simultaneous edits are outside the serialization guarantee. Conflicting compensation reports an explicit error and preserves newer state. No destructive migration is introduced.

## Validation

`PaperProjectMembershipTests` covers membership/core/pinned changes, legacy inputs, unknown fields, failed stages, association-level conflict detection including same-second same-value updates, explicit synchronization, queued cancellation, draft merging and workspace revisions. Public PDF imports additionally verified persisted links after repository reopening. Application compilation and UI gates remain required independently of Core tests.

## References

- `Sci-Station/Library/PaperProjectMembershipUseCase.swift`
- `Sci-Station/Library/ProjectPaperLinkRepository.swift`
- `Tests/SciStationCoreTests/PaperProjectMembershipTests.swift`
- [ADR-0002](ADR-0002-application-state-and-testing.md)
