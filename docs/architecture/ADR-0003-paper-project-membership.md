# ADR-0003: Paper-project association updates and recovery

- Status: Historical. The production architecture is superseded by [ADR-0004](ADR-0004-roundtable-workstation.md).
- Requirement: [ARCH-001](../BACKLOG.md#arch-001--application-state-boundaries).

The predecessor updated the association and its metadata mirror without writing unrelated draft edits. A failure in the mirror could compensate only the affected association and only while its committed revision remained current. Compensation across the two files had no process-crash transaction guarantee. The [original decision](https://github.com/Funyday-k/Sci-Station/blob/9434ea8b67e21d7573c08356c5144d23a959d144/docs/architecture/ADR-0003-paper-project-membership.md) documents that recovery behavior. In the Go workstation, a shared paper and PDF retain their own identity, and membership, core status, pins and order are scoped to the project.
