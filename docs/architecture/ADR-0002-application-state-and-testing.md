# ADR-0002: Focused application state and incremental test migration

- Status: Historical. The production architecture is superseded by [ADR-0004](ADR-0004-roundtable-workstation.md).
- Requirements: [ARCH-001](../BACKLOG.md#arch-001--application-state-boundaries), [TEST-001](../BACKLOG.md#test-001--domain-based-legacy-verification).

The predecessor separated domain decisions from global view coordination and split verification into named domain suites. Its test migration retained behavior assertions and ran both old and new checks until parity. The [original decision](https://github.com/Funyday-k/Sci-Station/blob/9434ea8b67e21d7573c08356c5144d23a959d144/docs/architecture/ADR-0002-application-state-and-testing.md) describes the former implementation and gates. Current state ownership and regression commands are in the [developer guide](../DEVELOPER.md).
