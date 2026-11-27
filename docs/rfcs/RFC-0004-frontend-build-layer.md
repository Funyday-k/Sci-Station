# RFC-0004: Evaluate a frontend build layer or component framework

- Status: Proposed
- Requirement: [Issue #46](https://github.com/Funyday-k/Sci-Station/issues/46) (part of [Epic #29](https://github.com/Funyday-k/Sci-Station/issues/29))
- Decision PR: Pending maintainer review on the Issue #46 pull request

## Problem and acceptance criteria

During the frontend UX and design-system remediation ([Epic #29](https://github.com/Funyday-k/Sci-Station/issues/29)), an initial architecture review suggested adopting Vite with Preact, Vue, or React. Introducing a frontend bundler or UI component runtime changes the build graph, the `//go:embed static/*` packaging boundary, macOS CI and release pipelines, and the repository policy in [AGENTS.md](../../AGENTS.md) that generated bundles stay out of Git. Therefore, per `AGENTS.md`, any decision to adopt—or decline—a frontend build layer or component framework must go through an RFC and an ADR before any implementation work.

Following [Issue #44](https://github.com/Funyday-k/Sci-Station/issues/44) (template and CSS decomposition) and [Issue #45](https://github.com/Funyday-k/Sci-Station/issues/45) (native ES modules and pure-DOM rendering across Roundtable and Research), the codebase now has:

- A three-tier semantic token system (`web/static/tokens.css`, 0 hex colors outside palette) and shared component library (`web/static/components.css`, 0 bare control rules outside components).
- Container-query layouts across 3 documented viewport breakpoints (`680px`, `999px`, `1000px`).
- Feature-split native ES modules (`web/static/modules/studio/*.js`, `web/static/modules/research/*.js`) loaded via `<script type="module">` with zero build step and 11 remaining justified HTML sinks (down from 48).
- 159 passing Node unit tests (`node --test tests/*.test.cjs`), 24 Python tooling tests, and 72 automated Chromium visual-baseline captures.

This RFC evaluates four concrete options against six architectural criteria and proposes a clear decision with measurable revisit triggers.

## Proposed design and boundaries

**Recommended option: Option 2 — Native ES modules as delivered in #45, plus optional opt-in static type checking via JSDoc and `tsc --noEmit` (zero build output, zero runtime framework).**

Under this design:

1. **No runtime or build artifact is added to `web/static/`.** The Go server continues to serve authored source files directly via `//go:embed static/*` in [web/assets.go](../../web/assets.go). No `dist/` directory, source-map pipeline, or generated bundle enters Git or the release tarball.
2. **Feature-split native ES modules remain the module format.** Each desktop surface loads at most one `<script type="module">` entry (with browser-native import maps allowed if shared module specifiers become useful), using WebKit's native ESM support in macOS WKWebView.
3. **Static safety grows incrementally via JSDoc + `tsc --noEmit` (opt-in follow-up).** When contributors want static verification of API contracts (for example, Go JSON payload shapes or module boundaries under `web/static/modules/`), TypeScript can run purely as a linter (`tsc --noEmit --allowJs --checkJs`) in a dedicated `package.json` / `jsconfig.json` check without emitting files or changing runtime execution.
4. **Domain ownership and security boundaries stay unchanged.** Go services under `internal/` own state, persistence, and directory-grant enforcement. Frontend modules remain a thin presentation layer using pure DOM APIs (`createElement`, `textContent`, `replaceChildren`) enforced by `Tools/scripts/check-frontend-metrics.py` and `tests/esm-modules-and-sinks.test.cjs`.

## Alternatives and tradeoffs

The four candidate architectures are:

1. **Option 1 — Native ESM as delivered in #45:** Author standard ES modules directly in `web/static/modules/`, serve them unbundled via `//go:embed static/*`, and validate with `node --test` and `check-frontend-metrics.py`.
2. **Option 2 — Native ESM + JSDoc / `tsc --noEmit` (Recommended):** Keep Option 1's zero-build runtime and `go:embed` model, and allow incremental JSDoc type annotations checked by an offline `tsc --noEmit` pass (no transpilation, no emitted JS).
3. **Option 3 — Bundler only (e.g., esbuild or Vite without a UI framework):** Add a Node build step to bundle/minify TypeScript or ESM into a generated output directory embedded by Go at build time.
4. **Option 4 — Bundler + component framework (e.g., Vite + Preact, Vue, or React):** Add both a bundler and a declarative UI runtime, progressively rewriting surfaces from Go HTML templates and imperative DOM modules into framework components.

### Evaluation matrix across the six required criteria

| Criterion | Option 1: Native ESM (#45) | Option 2: Native ESM + JSDoc/`tsc --noEmit` (Recommended) | Option 3: Bundler only (Vite / esbuild) | Option 4: Bundler + component framework (Preact / Vue / React) |
| --- | --- | --- | --- | --- |
| **1. Bundle and startup cost in WKWebView** | Lowest parse/compile cost: zero framework runtime, assets served from local loopback (`127.0.0.1`) with sub-millisecond fetch latency. Small module graphs (4–7 files per surface) avoid network waterfalls on loopback. | Identical to Option 1: JSDoc comments add negligible bytes and zero runtime overhead; `tsc --noEmit` ships nothing to WKWebView. | Slightly fewer HTTP requests per surface and smaller minified text, but on localhost WKWebView the savings are single-digit milliseconds while adding source-map indirection for debugging. | Adds framework runtime (4–45 KB gzipped) plus hydration/virtual-DOM initialization on every surface navigation; requires managing dual runtimes during a multi-release migration. |
| **2. CI and release impact** | Zero new build dependencies in `Makefile`, `.github/workflows/macos-ci.yml`, or `Tools/scripts/` packaging scripts. `go build` works directly from a clean checkout. | Minimal CI impact if adopted later: one optional lint job running `tsc --noEmit` with a pinned lockfile; `go build` and macOS `.app` / `.dmg` packaging remain completely independent of Node. | Every `go test`, `go build`, `make headless`, Wails build, and macOS release workflow must run `npm ci && npm run build` first; adds Node/npm supply-chain surface and build-cache maintenance to `Required CI`. | Same CI and release coupling as Option 3, plus ongoing framework, plugin, and transitive dependency upgrades across macOS 15 and macOS 26 runners. |
| **3. Reproducibility of embedded assets (`go:embed`)** | Fully deterministic: `web/static/` in Git is byte-for-byte what `//go:embed static/*` embeds, satisfying `AGENTS.md` ("generated bundles out of Git"). | Fully deterministic: identical to Option 1 because `tsc --noEmit` produces no output files. | Tension with `AGENTS.md`: either generated bundles are kept out of Git (breaking plain `go test ./...` until a pre-build step generates `web/static/dist/`), or generated artifacts are committed (violating repository hygiene). Requires deterministic bundler versions and hash-stable builds. | Same `go:embed` tension as Option 3, compounded by CSS extraction, asset hashing, and Go `html/template` integration across 10 surfaces (`workspace-shell.html`, `studio.html`, `research.html`, etc.). |
| **4. Test migration** | Zero migration cost: all 159 `node --test` cases already run cleanly via `tests/lib/esm-vm-loader.cjs`, and Go `workspace_shell_test.go` asserts server-rendered templates directly. | Zero migration cost: existing `node --test` and Go shell tests stay unchanged; JSDoc types catch contract drift before runtime without rewriting test harnesses. | Moderate cost: `vm`-based unit tests either have to test pre-build sources separately from shipped bundles (risking bundle-only regressions) or add a bundler test runner (Vitest/tsx). | High cost: requires migrating DOM-mock `node --test` suites to a DOM/framework test harness (e.g., jsdom/happy-dom + Testing Library) and rewriting Go HTML assertions that inspect server-rendered template markup. |
| **5. Localization and accessibility tooling** | Works directly with existing `data-en`, `data-l10n-text`, `web/static/localization.js`, `tests/localization.test.cjs`, and native HTML semantics (`<dialog>`, `<details>`, ARIA live regions). | Same as Option 1, plus JSDoc types can validate localization key maps and component option objects statically. | Neutral for localization and accessibility; JSX/TSX is not needed, though static lint plugins (ESLint a11y rules) can be wired independently of a bundler. | Strong ecosystem for JSX a11y lints and reactive ARIA state binding, but requires replacing or bridging the existing Go-template + `data-l10n-text` pipeline so bilingual copy and WCAG checks do not split across two systems. |
| **6. Contributor onboarding** | Very low friction: edit a `.js`/`.css`/`.html` file and reload. Requires discipline on shared globals and manual DOM wiring, mitigated by `docs/DEVELOPER.md` and `check-frontend-metrics.py`. | Low friction: edit and reload with no watcher process; IDE hover types and optional `tsc --noEmit` help new contributors navigate Go API payloads and module exports safely. | Medium friction: contributors must run a dev build/watch step alongside `go run`, troubleshoot Node/npm versions, and keep Go templates aligned with bundled asset paths. | Mixed: familiar to web framework developers once migrated, but during a partial migration contributors must learn both legacy Go-template/DOM modules and the new framework plus build tooling. |

### Why Option 2 wins today

1. **The pain points that prompted the build-layer question are already solved by #39–#45.** Token discipline (`0` stray hex colors), base control ownership (`0` outside `components.css`), `!important` sprawl (`2` total), layout responsiveness (`3` viewport widths + `@container`), Settings isolation (`5` stylesheets / `6` scripts), and untrusted `innerHTML` sinks (`48 -> 11` justified) were achieved without introducing a bundler or framework runtime.
2. **Go-first reproducibility is a high-value invariant for a desktop app.** `go test ./...`, `make headless`, and Wails macOS signing/packaging work cleanly with zero Node pre-build step and zero generated bundles in Git.
3. **Incremental static checking captures the main TypeScript benefit without the build tax.** JSDoc + `tsc --noEmit` gives IDE autocomplete, refactoring safety, and CI type checks over `web/static/modules/**/*.js` while keeping `web/static/` directly embeddable.

### Revisit triggers

Re-open this decision with a superseding RFC and ADR if two or more of the following become true:

- Interactive client-side state graphs (such as multi-cursor collaborative editing, rich graph canvases, or complex multi-pane synchronization) outgrow imperative DOM modules and produce recurring state-desynchronization bugs across releases.
- More than 50% of active frontend surfaces require deeply nested reactive views where pure DOM builders (`createElement`/`replaceChildren`) measurably slow feature delivery compared to declarative templates.
- Native ESM HTTP/module loading in WKWebView shows measurable startup regressions (> 150 ms added time-to-interactive on macOS 15 hardware) as module graphs grow past ~40 modules per surface.
- External third-party packages required by a product milestone cannot be vendored cleanly as standalone ESM/UMD files under `web/static/research-vendor/`.

## Compatibility, migration and recovery

- **No migration is required for existing users or workspaces.** Persisted data formats, workspace layouts, and API payloads are untouched.
- **No packaging or release changes occur in this RFC.** If a future Issue adopts the opt-in `tsc --noEmit` check from Option 2, it will add only a dev-time lint configuration (`jsconfig.json` / `package.json` devDependency or pinned toolchain) with zero changes to `web/assets.go` or shipped `.app` bundles.
- **Rollback is trivial.** Declining a build layer introduces no irreversible dependency; adopting Option 3 or Option 4 later remains straightforward because feature code is already modularized into standard ES modules under `web/static/modules/`.

## Validation and rollout

- This RFC and its companion [ADR-0006](../architecture/ADR-0006-frontend-build-layer.md) contain documentation only; no production code changes are made in Issue #46.
- Validate documentation integrity with `python3 Tools/scripts/check-docs-hygiene.py`, `python3 Tools/scripts/check-version-consistency.py`, `python3 Tools/scripts/check-frontend-metrics.py`, `Tools/scripts/check-repository-hygiene.sh`, and `python3 -m unittest discover -s Tools/tests -v`.
- If the maintainer accepts Option 2, a separate follow-up Issue may introduce the opt-in `jsconfig.json` + `tsc --noEmit` check over `web/static/modules/` without blocking Epic #29 completion.

## Open questions

1. Should an opt-in `jsconfig.json` + `tsc --noEmit` check be scheduled as a standalone P3 follow-up Issue after Epic #29 closes, or remain strictly local/IDE-driven until more classic scripts move into `web/static/modules/`?
2. Should `web/static/studio.html` and `web/static/research.html` adopt a small `<script type="importmap">` once shared frontend helpers (for example, `workspace-nav.js` and `ui-icons.js`) are promoted into `web/static/modules/shared/`?
