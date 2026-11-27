# ADR-0006: Keep zero-build native ES modules with opt-in JSDoc type checking

## Status

Accepted on 2026-11-27. The maintainer accepted Option 2 from [RFC-0004](../rfcs/RFC-0004-frontend-build-layer.md) for [Issue #46](https://github.com/Funyday-k/Sci-Station/issues/46) (part of [Epic #29](https://github.com/Funyday-k/Sci-Station/issues/29)). [Design review in PR #63](https://github.com/Funyday-k/Sci-Station/pull/63).

## Context

Sci-Station’s Go/Wails desktop host serves embedded assets to WKWebView. Studio and Research each load one native ES module entry alongside classic scripts. Roundtable requests additional assets when users open setup, a meeting, its tools, or document review. The frontend review asked whether a bundler or component framework would improve startup or make the code easier to maintain. [Embedded assets](../../web/assets.go) · [Native ESM implementation](https://github.com/Funyday-k/Sci-Station/pull/62)

## Decision

Retain zero-build native ES modules served directly from `web/static/` via `//go:embed static/*`, and permit opt-in static type checking of selected JavaScript modules with JSDoc and `tsc --noEmit`. Do not introduce a frontend bundler or component framework runtime in this cycle.

- Defer the optional type-checker configuration and pinned toolchain to a separate follow-up issue, starting as a local contributor task before considering CI integration.
- Keep relative ES module imports for now, and defer evaluating an import map to a follow-up issue if Studio and Research begin sharing browser modules.
- Reopen this decision only via a superseding RFC and ADR if the revisit triggers in [RFC-0004](../rfcs/RFC-0004-frontend-build-layer.md#revisit-triggers) are met, accompanied by the cold/warm WKWebView startup comparison protocol in that RFC.

## Alternatives

1. **Native ESM alone** keeps the existing workflow and relies on runtime tests and review for interface changes.
2. **A bundler alone** could reduce requests and minify assets. The release pipeline would have to generate reproducible assets before they are embedded. The WKWebView performance effect remains to be measured.
3. **A bundler with a component framework** also provides declarative components. Each migrated surface would incur runtime initialization and require tests around its rendered markup, focus management and localized content.

## Consequences

Contributors continue to edit authored assets under `web/static/`, rebuild and relaunch the Go host to exercise changes, while Go builds and macOS packaging remain Node-free at build time with zero generated bundles in Git. Opt-in JSDoc type checking can catch errors in annotated interfaces without emitting browser code, while native and browser tests continue exercising runtime behavior. Go services retain responsibility for persistent state and permissions. [Developer guide](../DEVELOPER.md)

The existing metrics check tracks design tokens and counts HTML sink patterns in first-party JavaScript. The ESM tests check Studio and Research entry points, exercise selected DOM builders, and restrict the three remaining assignments to built-in SVG illustrations in seating and setup. [Metric limits](../../Tools/frontend-metrics.json) · [ESM and DOM tests](../../tests/esm-modules-and-sinks.test.cjs)

## Validation

The workbench smoke opens Roundtable views, exercises their controls and checks which assets WKWebView requested. This covers interaction and resource-loading regressions. Earlier, at `04a3c29`, the PR author reported 72 Chromium screenshots without page errors and three macOS-only cases skipped during Linux Node validation. The cold and warm WKWebView startup comparison between the four options remains unmeasured and is required before any future proposal to adopt a bundler or framework. [Workbench smoke](../../tests/workstation-workbench-smoke.cjs) · [PR #62 validation](https://github.com/Funyday-k/Sci-Station/pull/62) · [Startup comparison protocol](../rfcs/RFC-0004-frontend-build-layer.md#measuring-startup-before-changing-the-build)

Documentation hygiene and governance tests (`python3 Tools/scripts/check-docs-hygiene.py`, `python3 Tools/scripts/check-version-consistency.py`, `python3 Tools/scripts/check-frontend-metrics.py`, `Tools/scripts/check-repository-hygiene.sh`, and `python3 -m unittest discover -s Tools/tests -v`) validate the accepted records and both indexes.

## References

- [RFC-0004](../rfcs/RFC-0004-frontend-build-layer.md) and [its design review](https://github.com/Funyday-k/Sci-Station/pull/63)
- [ADR-0004 on the Go/Wails host](ADR-0004-roundtable-workstation.md)
- [Epic #29](https://github.com/Funyday-k/Sci-Station/issues/29), [Issue #45 on native ES modules](https://github.com/Funyday-k/Sci-Station/issues/45), and [Issue #46](https://github.com/Funyday-k/Sci-Station/issues/46)
