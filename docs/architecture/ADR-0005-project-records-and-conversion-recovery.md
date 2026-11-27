# ADR-0005 — Project authority and recoverable paper conversions

Accepted on 2026-11-27. The maintainer approved both persistence choices in [RFC-0003](../rfcs/RFC-0003-project-records-and-conversion-recovery.md) for [Issue #27](https://github.com/Funyday-k/Sci-Station/issues/27).

Use the Research project record as the authority for the current directory grant. Store confirmed project rules with their stable project identity. Earlier path-indexed records remain readable for compatibility. Write version 1 on the next ordinary save of an unversioned project or paper. Persist one local MinerU submission receipt per source so a restart can recover a known batch or present an uncertain outcome for review.

The RFC describes alternatives and the compatibility obligations. The [versioning guide](../VERSIONING.md) describes the on-disk records and recovery procedure.
