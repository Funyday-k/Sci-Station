# ADR-0006: Keep zero-build native ES modules with opt-in JSDoc type checking

## Status

Proposed. The maintainer’s decision is pending, and Issue #46 remains open. [Design review in PR #63](https://github.com/Funyday-k/Sci-Station/pull/63) · [Issue #46](https://github.com/Funyday-k/Sci-Station/issues/46) · [RFC-0004](../rfcs/RFC-0004-frontend-build-layer.md)

## Context

Sci-Station’s Go/Wails desktop host serves embedded assets to WKWebView. At the revision evaluated by RFC-0004, Studio and Research each load a native ES module entry alongside classic scripts. The frontend review asked whether a bundler or component framework would improve startup or make the code easier to maintain. [Embedded assets](../../web/assets.go) · [Native ESM implementation](https://github.com/Funyday-k/Sci-Station/pull/62)

## Decision

RFC-0004 recommends retaining native ES modules and permitting opt-in static checking of selected JavaScript modules with JSDoc and `tsc --noEmit`. A follow-up issue could define the checker configuration and pinned toolchain after the maintainer accepts the proposal.

## Alternatives

1. **Native ESM alone** keeps the existing workflow and relies on runtime tests and review for interface changes.
2. **A bundler alone** could reduce requests and minify assets. The release pipeline would have to generate reproducible assets before they are embedded. The WKWebView performance effect remains to be measured.
3. **A bundler with a component framework** also provides declarative components. Each migrated surface would incur runtime initialization and require tests around its rendered markup, focus management and localized content.

## Consequences

Under the proposed option, contributors would rebuild and relaunch the Go host to exercise asset changes. Type checking could catch errors in annotated interfaces, while native and browser tests would continue exercising behavior. Go services would retain responsibility for persistent state and permissions. [Developer guide](../DEVELOPER.md)

The existing metrics check tracks design tokens and counts HTML sink patterns in first-party JavaScript. The ESM tests check Studio and Research entry points, exercise selected DOM builders, and require adjacent comments for tracked sinks. [Metrics script](../../Tools/scripts/check-frontend-metrics.py) · [ESM and DOM tests](../../tests/esm-modules-and-sinks.test.cjs)

## Validation

PR #62 reports Linux Node validation with three macOS-only cases skipped and 72 Chromium visual captures without page errors at `04a3c29`. RFC-0004 specifies a separate cold and warm startup comparison in native WKWebView to evaluate the performance hypotheses. [PR #62](https://github.com/Funyday-k/Sci-Station/pull/62) · [Startup comparison protocol](../rfcs/RFC-0004-frontend-build-layer.md#measuring-startup-before-changing-the-build)

Review the documentation with `python3 Tools/scripts/check-docs-hygiene.py` and `python3 -m unittest discover -s Tools/tests -v`. On acceptance, record the decision PR and update both indexes before closing Issue #46.

## References

- [RFC-0004](../rfcs/RFC-0004-frontend-build-layer.md) and [its design review](https://github.com/Funyday-k/Sci-Station/pull/63)
- [ADR-0004 on the Go/Wails host](ADR-0004-roundtable-workstation.md)
- [Epic #29](https://github.com/Funyday-k/Sci-Station/issues/29) and [Issue #45 on native ES modules](https://github.com/Funyday-k/Sci-Station/issues/45)
