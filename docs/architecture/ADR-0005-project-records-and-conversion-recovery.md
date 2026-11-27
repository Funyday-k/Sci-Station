# ADR-0005 — Project authority and recoverable paper conversions

Accepted on 2026-11-27. The maintainer approved the persistence and directory reassignment decisions in [RFC-0003](../rfcs/RFC-0003-project-records-and-conversion-recovery.md) for [Issue #27](https://github.com/Funyday-k/Sci-Station/issues/27). [Decision and implementation PR #28](https://github.com/Funyday-k/Sci-Station/pull/28).

Use the Research project record as the authority for the current directory grant. Store confirmed project rules with their stable project identity. Earlier path-indexed records remain readable for compatibility. Write version 1 on the next ordinary save of an unversioned project or paper. Persist one local MinerU submission receipt per source so a restart can recover a known batch or present an uncertain outcome for review.

After a confirmed directory replacement, retire all conversations and unsent drafts owned by the project ID and begin a fresh history for its new grant. Track cleanup in the authoritative project record so it can finish across a restart. Reassignment preserves published research records, external files and other projects.

The RFC describes alternatives and the compatibility obligations. The [versioning guide](../VERSIONING.md) describes the on-disk records and recovery procedure.
