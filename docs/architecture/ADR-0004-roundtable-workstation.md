# ADR-0004: One Go/Wails host for Sci-Station and Roundtable

- Status: Accepted on 2026-11-25.
- Requirement: [Issue #13](https://github.com/Funyday-k/Sci-Station/issues/13).
- Design PR: [#14](https://github.com/Funyday-k/Sci-Station/pull/14).

## Context

The Swift application defines the research workflows and their regression tests. The Roundtable-based Sci-Station prototype provides a Go/Wails shell, native launch and PDF integration, a shared paper library and a multi-seat meeting engine. It distributes some project and evidence context across separate pages and project registries. This complicates actions that start in the reader, continue in a meeting and write back to the project.

On 2026-11-25, the maintainer was explicitly asked in the project work session to accept RFC-0002 and replied “继续” (“proceed”). The accepted direction covers a single Go/Wails workstation, continuity of the product identity and launch animation, and retirement of the Swift production framework after behavioral and release validation.

## Decision

Use one macOS executable, native window lifecycle, navigation model, workspace and project context, and research permission boundary. Compose the existing Go research services, Roundtable meeting engine and gateway in that host. Mount research, reader, AI Lab and discussion within the same application context. Preserve the Sci-Station name, Roundtable logo and Sci-Station launch animation. Each paper, project, meeting and evidence locator retains its own identity. Scope reviewed writes to the project and revision presented for approval.

Start fresh by default. Leave existing Swift Research Roots and the Go prototype data intact. Before switching production builds, save a restorable copy of prototype application data, account for external research directories separately, and verify restoration against an isolated copy. Any future import needs an explicit source and destination and validation before publishing the result.

## Alternatives

Embedding the Swift client would duplicate project routing, authority over files and shutdown ownership. Keeping independent research and meeting screens with browser-only handoffs would preserve their divergent state. Port the affected workflows onto the existing Go services in independently testable slices.

## Consequences

The new production app will have no legacy Swift compatibility client or Python sidecar. Remove the old production stack only after the acceptance evidence below exists. Preserve the protected branch, unconditional Required CI aggregate and release controls through cutover. The maintainer's architecture decision authorizes implementation work. CI, code review, implementation acceptance and release continue through their own gates.

## Validation

Follow the domain-by-domain acceptance matrix in RFC-0002. Port the behavioral assertions of Swift and sidecar tests before retiring them, or record a maintainer-approved feature retirement. Exercise the shared-paper selection, multi-seat discussion, reviewed writeback, refusal, retry, restart and return to the original evidence through the packaged application. Verify close button, Command-W and Command-Q with idle and active work; capture PID exit, lock and port release, prompt relaunch and durable data after each. Record data restoration, offline behavior, packaging and installation results with the implementation changes.

## References

- [RFC-0002 and its acceptance matrix](../rfcs/RFC-0002-roundtable-workstation.md)
- [State ownership and test migration](ADR-0002-application-state-and-testing.md)
- [Paper-project association semantics](ADR-0003-paper-project-membership.md)
- [Repository governance](../GOVERNANCE.md)
