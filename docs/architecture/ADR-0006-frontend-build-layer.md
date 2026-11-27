# ADR-0006: Keep zero-build native ES modules with opt-in JSDoc type checking

## Status

Proposed — awaiting maintainer review for [Issue #46](https://github.com/Funyday-k/Sci-Station/issues/46) (part of [Epic #29](https://github.com/Funyday-k/Sci-Station/issues/29)), based on [RFC-0004](../rfcs/RFC-0004-frontend-build-layer.md).

## Context

Sci-Station embeds its web frontend into the single Go/Wails desktop binary via `//go:embed static/*` in [web/assets.go](../../web/assets.go) and renders pages inside macOS WKWebView. A pre-remediation review suggested adopting Vite with Preact, Vue, or React. Per [AGENTS.md](../../AGENTS.md), introducing a new runtime or build layer requires an accepted RFC and ADR, and generated bundles must stay out of Git.

Issues #39 through #45 resolved the core maintainability and security defects in the unbundled frontend: three-tier semantic tokens (`tokens.css`, 0 hex colors outside palette), shared components (`components.css`, 0 stray bare control rules), container-query layouts (3 viewport breakpoints), an isolated `/settings` surface, decomposed `studio.html` partials and stylesheets (`important_lines` reduced to 2), and feature-split native ES modules under `web/static/modules/` (`html_sinks` ratcheted from 48 down to 11 justified sinks).

## Decision

Keep Sci-Station on **zero-build native ES modules** (`<script type="module">`) served directly from `web/static/` via `//go:embed static/*`, and permit **opt-in static type checking via JSDoc + `tsc --noEmit`** as an offline lint step rather than introducing a frontend bundler or component framework runtime.

- Do not add Vite, esbuild, Webpack, Preact, Vue, or React to the desktop build or runtime.
- Continue migrating classic scripts incrementally into feature-split ES modules under `web/static/modules/` with one module entry per HTML surface and pure DOM APIs for untrusted data.
- Revisit this decision through a superseding RFC/ADR only if the measurable revisit triggers in [RFC-0004](../rfcs/RFC-0004-frontend-build-layer.md) are met.

## Alternatives

1. **Option 1 — Native ESM only (#45):** Identical runtime and `go:embed` simplicity, but leaves no sanctioned path for optional static type checking of Go-to-frontend JSON contracts.
2. **Option 3 — Bundler only (Vite / esbuild):** Adds a mandatory Node pre-build step before `go build` / `go test` and creates tension with keeping generated bundles out of Git for marginal localhost WKWebView latency savings.
3. **Option 4 — Bundler + component framework (Preact / Vue / React):** Adds runtime overhead, dual-stack migration cost across Go templates and 159 existing `node --test` suites, and ongoing npm/framework maintenance across macOS CI runners.

## Consequences

- **Positive:** `go test ./...`, `make headless`, and macOS `.app`/`.dmg` packaging remain deterministic, Node-free at build time, and compliant with keeping generated bundles out of Git. WKWebView incurs zero framework runtime startup cost. Existing `node --test` suites (`tests/lib/esm-vm-loader.cjs`), Go shell tests (`internal/desktop/workspace_shell_test.go`), localization hooks (`data-en` / `data-l10n-text`), and visual baselines (`tests/workbench-visual-baselines-smoke.cjs`) continue working unchanged.
- **Negative / Tradeoffs:** Complex interactive views still rely on disciplined imperative DOM helpers rather than a declarative component reconciler. Static type coverage is opt-in and requires JSDoc discipline until a follow-up lint gate is added.
- **Guardrails:** `Tools/scripts/check-frontend-metrics.py` (scanning `web/static/**/*.js` excluding `research-vendor/`) and `tests/esm-modules-and-sinks.test.cjs` enforce design-system tokens, HTML sink discipline, and single-entry module structure on every PR.

## Validation

- No implementation code is changed by Issue #46.
- Documentation and tooling checks: `Tools/scripts/check-repository-hygiene.sh`, `python3 Tools/scripts/check-docs-hygiene.py`, `python3 Tools/scripts/check-version-consistency.py`, `python3 Tools/scripts/check-frontend-metrics.py`, and `python3 -m unittest discover -s Tools/tests -v`.
- Baseline evidence referenced from [Issue #45](https://github.com/Funyday-k/Sci-Station/issues/45): `node --test tests/*.test.cjs` (159 passing) and `tests/workbench-visual-baselines-smoke.cjs` (72 captures, 0 page errors).

## References

- [RFC-0004: Evaluate a frontend build layer or component framework](../rfcs/RFC-0004-frontend-build-layer.md)
- [ADR-0004: Roundtable workstation](ADR-0004-roundtable-workstation.md)
- [Issue #46](https://github.com/Funyday-k/Sci-Station/issues/46) and [Epic #29](https://github.com/Funyday-k/Sci-Station/issues/29)
- [Issue #45](https://github.com/Funyday-k/Sci-Station/issues/45) (Native ES modules and HTML sink closure)
- [Developer guide](../DEVELOPER.md), [web/assets.go](../../web/assets.go), [Tools/scripts/check-frontend-metrics.py](../../Tools/scripts/check-frontend-metrics.py), and [tests/lib/esm-vm-loader.cjs](../../tests/lib/esm-vm-loader.cjs)
