# ADR-0006: Keep zero-build native ES modules with opt-in JSDoc type checking

## Status

Proposed. The maintainer’s decision is pending, and Issue #46 remains open. [Design review in PR #63](https://github.com/Funyday-k/Sci-Station/pull/63) · [Issue #46](https://github.com/Funyday-k/Sci-Station/issues/46) · [RFC-0004](../rfcs/RFC-0004-frontend-build-layer.md)

## Context

Sci-Station’s Go/Wails desktop host serves embedded assets to WKWebView. Studio and Research each load one native ES module entry alongside classic scripts. Roundtable requests additional assets when users open setup, a meeting, its tools, or document review. The frontend review asked whether a bundler or component framework would improve startup or make the code easier to maintain. [Embedded assets](../../web/assets.go) · [Native ESM implementation](https://github.com/Funyday-k/Sci-Station/pull/62)

## Decision

RFC-0004 recommends retaining native ES modules and permitting opt-in static checking of selected JavaScript modules with JSDoc and `tsc --noEmit`. A follow-up issue could define the checker configuration and pinned toolchain after the maintainer accepts the proposal.

## Alternatives

1. **Native ESM alone** keeps the existing workflow and relies on runtime tests and review for interface changes.
2. **A bundler alone** could reduce requests and minify assets. The release pipeline would have to generate reproducible assets before they are embedded. The WKWebView performance effect remains to be measured.
3. **A bundler with a component framework** also provides declarative components. Each migrated surface would incur runtime initialization and require tests around its rendered markup, focus management and localized content.

## Consequences

Under the proposed option, contributors would rebuild and relaunch the Go host to exercise asset changes. Type checking could catch errors in annotated interfaces, while native and browser tests would continue exercising behavior. Go services would retain responsibility for persistent state and permissions. [Developer guide](../DEVELOPER.md)

The existing metrics check tracks design tokens and counts HTML sink patterns in first-party JavaScript. The ESM tests check Studio and Research entry points, exercise selected DOM builders, and restrict the three remaining assignments to built-in SVG illustrations in seating and setup. [Metric limits](../../Tools/frontend-metrics.json) · [ESM and DOM tests](../../tests/esm-modules-and-sinks.test.cjs)

## Validation

The workbench smoke opens Roundtable views, exercises their controls and checks which assets WKWebView requested. This covers interaction and resource-loading regressions. Earlier, at `04a3c29`, the PR author reported 72 Chromium screenshots without page errors and three macOS-only cases skipped during Linux Node validation. The cold and warm WKWebView startup comparison between the four options remains unmeasured. [Workbench smoke](../../tests/workstation-workbench-smoke.cjs) · [PR #62 validation](https://github.com/Funyday-k/Sci-Station/pull/62) · [Startup comparison protocol](../rfcs/RFC-0004-frontend-build-layer.md#measuring-startup-before-changing-the-build)

Review the documentation with `python3 Tools/scripts/check-docs-hygiene.py` and `python3 -m unittest discover -s Tools/tests -v`. On acceptance, record the decision PR and update both indexes before closing Issue #46.

## References

- [RFC-0004](../rfcs/RFC-0004-frontend-build-layer.md) and [its design review](https://github.com/Funyday-k/Sci-Station/pull/63)
- [ADR-0004 on the Go/Wails host](ADR-0004-roundtable-workstation.md)
- [Epic #29](https://github.com/Funyday-k/Sci-Station/issues/29) and [Issue #45 on native ES modules](https://github.com/Funyday-k/Sci-Station/issues/45)
