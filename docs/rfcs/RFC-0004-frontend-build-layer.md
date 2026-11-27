# RFC-0004: Evaluate a frontend build layer or component framework

- Status: Accepted
- Requirement: [Issue #46](https://github.com/Funyday-k/Sci-Station/issues/46), part of [Epic #29](https://github.com/Funyday-k/Sci-Station/issues/29)
- Design review: [PR #63](https://github.com/Funyday-k/Sci-Station/pull/63)
- Decision PR: [PR #64](https://github.com/Funyday-k/Sci-Station/pull/64)

## Problem and acceptance criteria

The frontend review raised two questions. Would bundling improve startup for someone opening Research or Roundtable in WKWebView? Would static types or a component framework make these surfaces easier for contributors to change? Issue #46 calls for comparing four options and recording the maintainer’s choice in an ADR. A new browser runtime also requires prior design acceptance under the [agent guidelines](../../AGENTS.md).

The comparison starts from the frontend delivered by PR #62. Studio and Research each load one native ES module entry alongside classic scripts. Roundtable loads additional styles and scripts for the active view. Opening a meeting requests its room assets, opening meeting tools adds the plugin assets, and opening document review adds the diff stylesheet. The first-party HTML sink baseline is three assignments, each reserved for a built-in SVG illustration: the preset, the seating figure and the tabletop. [Frontend metrics](../../Tools/frontend-metrics.json) · [SVG allowlist and DOM tests](../../tests/esm-modules-and-sinks.test.cjs) · [Workbench resource and navigation checks](../../tests/workstation-workbench-smoke.cjs)

## Proposed design and boundaries

**Accepted decision: Option 2, native ES modules with opt-in JSDoc type checking.** Go continues embedding authored assets from `web/static/`. Contributors may check annotated module interfaces using a pinned TypeScript compiler with `allowJs`, `checkJs` and `noEmit`. Any type-checker configuration and toolchain setup belongs in a separate follow-up issue, starting as a local contributor task rather than a mandatory build step. The compiler runs only for that check and emits no browser code. [Embedded assets](../../web/assets.go) · [Developer guide](../DEVELOPER.md)

Go services continue to own workspace identity, file grants and persisted data. Frontend modules use DOM builders for user-provided text. The metrics script counts tracked sink patterns in first-party JavaScript. Tests check the three allowed assignments and their justification comments, exercise selected DOM helpers with untrusted text, and verify the Studio and Research module entries. [Frontend metrics](../../Tools/scripts/check-frontend-metrics.py) · [ES module and DOM tests](../../tests/esm-modules-and-sinks.test.cjs)

## Alternatives and tradeoffs

1. **Native ESM.** Serve authored JavaScript with the Go host as in PR #62.
2. **Native ESM and JSDoc type checking.** Use the same browser code and allow a development-time check of selected annotated modules.
3. **Bundler only.** Use esbuild or Vite to generate the JavaScript imported by the embedded pages.
4. **Bundler and component framework.** Bundle a runtime such as Preact, Vue or React and migrate selected views to components.

| Criterion | 1. Native ESM | 2. ESM and type checking | 3. Bundler only | 4. Bundler and framework |
| --- | --- | --- | --- | --- |
| Bundle and startup cost in WKWebView | WKWebView requests authored modules over loopback. Initial navigation and opening another view can load different resources, depending on the active view and cache. | The checker emits no JavaScript. JSDoc comments contribute source bytes. | Bundling could reduce requests and minify source, or make a surface load code it does not use. | A mounted component also loads and initializes its runtime. The cost depends on the chosen framework, build and view. |
| CI and release | Current Go builds embed assets from a clean checkout. Node runs frontend tests. | A pinned checker and configuration would be needed to run the optional lint step. Packaging follows the existing Go build. | CI and release would generate assets before building binaries that embed them. Independent Go package tests could still run directly. | The same build ordering applies. Runtime and compiler upgrades also need compatibility checks in supported WKWebViews. |
| Reproducibility of embedded assets | The executable embeds the source tree compiled by Go. | The same files are embedded after a type check. | Keep generated files out of Git, pin the toolchain and lockfile, and verify a clean build generates the expected assets before embedding. | Also verify generated CSS, chunks and any asset manifest referenced by Go templates. |
| Test migration | CommonJS tests use the ESM loader where needed. Go shell tests exercise server-rendered templates. | Existing runtime tests still apply. Annotated interfaces give the checker an additional way to catch incompatible property access. | Keep source-level tests and add a smoke check against the generated assets shipped in the binary. | Retain shell and end-to-end coverage. Migrated views also need component interaction tests for state, focus and accessibility. |
| Localization and accessibility | Templates use native controls, ARIA and the bilingual interface catalog through `interface-language.js`. | Typed message keys and options could catch some mistakes while editing. Keyboard and assistive-technology checks still exercise the rendered UI. | The same catalog and semantic HTML can be used in bundled modules. | Components can share localized labels and focus behavior. Each migrated view must preserve catalog lookup, keyboard navigation and accessible names. |
| Contributor onboarding | Edit the asset, rebuild and relaunch the host. For the desktop app, quit the previous instance and run `make run`. | The same edit cycle applies. Contributors opting into the checker also need its pinned toolchain. | Contributors must generate the asset bundle before rebuilding the embedding host. | Contributors also learn the framework and the boundary between components and Go templates during migration. |

Option 2 addresses module and JSON payload mistakes while preserving the current packaging path. The runtime tradeoff is still open. At the earlier revision `04a3c29`, the PR author reported running the Node suite on Linux with three macOS-only cases skipped and capturing 72 Chromium screenshots with zero page errors. These historical results describe rendering before the final view-based loading changes. The workbench smoke exercises those changes by navigating between Roundtable views and inspecting the resources actually requested. A comparison of startup time or framework bundle sizes in WKWebView is still needed before revisiting a bundler or framework. [PR #62 validation](https://github.com/Funyday-k/Sci-Station/pull/62) · [Visual capture plan](../../tests/workbench-visual-baselines-smoke.cjs) · [Localization tests](../../tests/localization.test.cjs) · [Interface language implementation](../../web/static/interface-language.js)

### Measuring startup before changing the build

A follow-up comparing runtimes should build release-mode variants of the same revision and pin the proposed bundler and framework versions. Use the same macOS 15 Apple Silicon machine, WebKit version, workspace fixture, locale and viewport. For both Research and Roundtable, record the interval from navigation start to the first successful use of the same enabled control, along with the resource request count and total JavaScript bytes served. The Research sidebar and the Roundtable meeting menu provide reproducible interactions.

Alternate the variants and collect at least 20 observations per surface and cache condition. Start each cold trial in a new app process with a fresh WebKit data store. Use a repeat navigation for warm trials. Publish the commit, build commands, fixture, raw timings, median and 95th percentile for each group. This would establish whether reduced request overhead offsets additional JavaScript loading or initialization.

### Revisit triggers

Reopen the comparison if two or more of the following arise:

- State-synchronization defects in interactive views recur across releases.
- More than half of active surfaces need deeply nested reactive views and delivery data identifies manual DOM updates as a significant cost.
- As a surface grows past about 40 modules, repeated WKWebView measurements show more than 150 ms additional time to interaction against the recorded baseline. This is a proposed investigation threshold.
- A product milestone requires a third-party package that cannot be vendored as standalone ESM or UMD under `web/static/research-vendor/`.

## Compatibility, migration and recovery

All four options concern presentation assets. Option 2 keeps workspace formats, API payloads and user data compatible. Removing a future checker or its annotations requires no workspace migration. A later proposal to bundle assets would need to specify clean-checkout generation, release validation and rollback to the previous embedded assets.

## Validation and rollout

Run `python3 Tools/scripts/check-docs-hygiene.py` and `python3 -m unittest discover -s Tools/tests -v` on the decision record. The maintainer accepted Option 2 on 2026-11-27 and recorded the decision in [ADR-0006](../architecture/ADR-0006-frontend-build-layer.md). No production code is changed in Issue #46; any future JSDoc type-checking setup belongs in a separate follow-up issue. [Design review](https://github.com/Funyday-k/Sci-Station/pull/63) · [ADR-0006](../architecture/ADR-0006-frontend-build-layer.md) · [RFC process](README.md)

## Open questions (disposition)

1. **Local task vs. opt-in CI job for type checking:** Deferred to a separate follow-up issue; start as an opt-in local contributor task before evaluating CI wiring.
2. **Import map for shared browser modules:** Deferred to a separate follow-up issue; keep relative imports until Studio and Research begin sharing browser modules.
