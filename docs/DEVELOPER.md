# Sci-Station developer guide

Use [CONTRIBUTING](../CONTRIBUTING.md) for change review and [GOVERNANCE](GOVERNANCE.md) for required checks and releases. The [desktop architecture decision](architecture/ADR-0004-roundtable-workstation.md) and [cutover acceptance matrix](rfcs/RFC-0002-roundtable-workstation.md) define the Go/Wails host.

## Build and run

Use Apple Silicon, macOS 15 or newer, Go 1.26 and Xcode Command Line Tools. Node.js runs the frontend tests, and Python 3 runs the release and native smoke tooling. Run commands from the repository root. The Go build uses the committed module checksums, and the frontend assets are embedded in the executable.

```sh
make run
make test
```

`make run` builds and opens the desktop application. `make app` builds it without opening it, and `make verify` checks the resulting bundle. Use the same `APP_OUTPUT` for both if you choose a separate build location. The app reads its version and build number from [VERSION](../VERSION) and [BUILD_NUMBER](../BUILD_NUMBER). Normal development needs no DMG or ZIP.

Use a disposable workspace for manual checks. The desktop application accepts an explicit root; its native folder chooser and the Workspace menu also let you create and open roots. Browser-only testing uses the same services through a loopback server. Choose a new or disposable data path.

```sh
make headless
build/bin/sci-station-server serve -port 18765 -data-dir /path/to/test-workspace
```

Open `http://127.0.0.1:18765/research`. Open the macOS app to exercise PDFKit, EventKit, dialogs, menus and trusted window callbacks.

## Code map

| Area | Entry points | Responsibility |
| --- | --- | --- |
| Executable | [cmd/sci-station/](../cmd/sci-station/) | Start the shared host in desktop or headless builds. |
| Desktop host and API | [internal/desktop/](../internal/desktop/), including [desktop_darwin.go](../internal/desktop/desktop_darwin.go), [workspace_shell.go](../internal/desktop/workspace_shell.go) and [api.go](../internal/desktop/api.go) | Coordinate Wails and AppKit, the active workspace, validated navigation, loopback origins and API routes. |
| Frontend | [web/static/](../web/static/) | Store the embedded HTML, CSS, JavaScript and assets. The host serves assets at `/static/`. Update shared interface text through the interface catalog. |
| Research records | [internal/research/](../internal/research/), [internal/workspace/](../internal/workspace/) | Workspace and project identity, domain records, versions, revisions, papers, Wiki, material paths, tasks and reviewed writes. |
| AI Lab, meetings and reports | [internal/meeting/](../internal/meeting/), [internal/deliberation/](../internal/deliberation/), [internal/sessionstore/](../internal/sessionstore/) | Shared meeting engine supports single-seat runs and multi-seat Roundtable, stable evidence references, turn history and resumable results. |
| Models, CLI access and credentials | [internal/gateway/](../internal/gateway/), [internal/cliedit/](../internal/cliedit/), [internal/credentials/](../internal/credentials/) | Provider connections, session-specific CLI decisions and macOS Keychain. |
| Plugins | [internal/plugins/](../internal/plugins/) | Load and check versioned plugins. |
| Packaging and verification | [packaging/macos/](../packaging/macos/), [tests/](../tests/), [Tools/](../Tools/) | Build and verify the signed arm64 bundle, exercise frontend behavior and native workflows, and run repository and release checks. |

## Desktop layout and AI navigation

The [workspace shell](../web/static/workspace-shell.html) renders navigation, the project tree, a toolbar and a single content region for every desktop route. Pages supply optional sidebar, breadcrumb and tool content through Go templates. Document pages use the shared page heading and gutters. Chat, Roundtable and Reader use the available viewport and own their internal transcript or PDF scroll area. Width and panel placement are managed by the shell. Home and project overviews use a row-aligned CSS grid. AI uses a second independently collapsible pane for conversation history. Settings substitutes its own categories for the regular navigation and restores the originating route on return.

Roundtable declares feature assets in inert `template[data-view-assets]` groups in `studio.html`. The shell activates them at their declared cascade position. Project navigation, handoff and composer controls are shared by setup and the room. Creating a meeting prepares the room before submitting the draft. Document review and plugin tools load at their own entry points, and the AI rail can request the shared Markdown renderer separately.

The sidebar and native Workspace menu open one AI destination. The shared switch selects single chat at `/lab` or a discussion at `/studio`. Legacy deep links still open the requested conversation. Project context comes from the route or the saved session. Switching modes prepares a scoped transfer for explicit review. Both conversation engines keep their own sessions, run controls and approvals.

## Workbench layout rules

UI changes and reviews apply these layout and interaction rules across all desktop surfaces:

- **Three AI concepts, one entry point each:**
  - *Ask* — quick assistance scoped to the current object (paper, note, task or meeting), opened in the context rail;
  - *Chat* — persisted single-agent conversation session (`/lab`);
  - *Roundtable* — multi-seat meeting (`/studio`).

  In-room views such as meeting chat and discussion stances are tabs inside the room side panel, never separate global entries.
- **Horizontal bars:** render at most two horizontal bars above the main content area (the global workspace bar plus at most one page bar), with an optional single-line status foot below content.
- **Sidebars:** show at most one sidebar by default. Secondary sidebars (such as conversation history or an inspector) stay collapsed by default or fold into tabs / an icon rail so default sidebar chrome does not crowd the main content region.
- **Primary actions:** place at most one primary-styled action per page. Secondary and lower-frequency actions use secondary, ghost, action-link or overflow-menu controls.
- **Empty states:**
  - modules with no data render as a compact row (≤ 56px tall);
  - reserve a full empty card strictly for first-run onboarding;
  - render at most one full empty card per screen.
- **No first-viewport duplication:** the same record (such as an active task, paper or note) appears at most once in the first viewport.
- **Command parity:** frontend menus and toolbars for actions that also exist in the native macOS menu dispatch the same command IDs so behavior and availability stay consistent.

## Shared UI components

`web/static/components.css` owns base element styles (`button`, `input`, `select`, `textarea`, `dialog`) and shared workbench primitives using semantic tokens from `web/static/tokens.css`. Page stylesheets must not declare bare base-element rules for these controls; `Tools/scripts/check-frontend-metrics.py` enforces this through `base_control_allowlist`. All interactive controls share one focus ring (`2px solid var(--focus-ring)` with `2px` offset), one disabled state (`opacity: 0.48; cursor: not-allowed`), one radius per size (`--radius-sm` controls, `--radius-md` cards/menus, `--radius-lg` dialogs), and honor `prefers-reduced-motion: reduce`.

| Component | Markup contract | Localization attributes | Keyboard behaviour |
| --- | --- | --- | --- |
| Buttons | `<button type="button" class="button [primary\|secondary\|ghost\|danger]">` or `.btn-icon` / `.icon-button` / `.workspace-icon` | `data-l10n-text` / `data-en`; icon-only buttons require `aria-label` + `data-l10n-aria-label` (or `data-en-aria-label`) | Native `Enter`/`Space` activation; visible focus ring on `:focus-visible` |
| Form fields & switch | `<label>` wrapping or `for`-linked `<input>`, `<select>`, `<textarea>`, or `<input type="checkbox" role="switch">` | `<label>` text with `data-en` / `data-l10n-text`; input hint attributes localized via `interface-catalog.json` | Standard tab order; switch toggles on `Space` |
| Dialog & footer | `<dialog aria-labelledby="…">` containing body and `<footer class="dialog-footer">` (`.dialog-footer-leading` / `.dialog-footer-trailing` or `.dialog-footer__actions`) | Heading `data-en` / `data-l10n-text`; close button `aria-label` | Modal `Escape` closes and restores focus to opener; `Tab` cycles inside |
| Card variants | `<section class="card card--primary\|card--secondary\|card--compact\|card--empty">` | Heading uses `data-l10n-text` / `data-en` | Static landmark container; interactive children follow normal tab order |
| Empty row | `<section class="empty-row">` with `.empty-row__title` and `.empty-row__meta` (≤ 56px tall) | `data-l10n-text` / `data-en` on title and status text | Non-interactive summary row (optional trailing `.action-link`) |
| Action link | `<a class="action-link" href="…">` or `<button type="button" class="action-link">` | Link label uses `data-l10n-text` / `data-en` (trailing `→` is decorative CSS) | `Enter` activates link (`Enter`/`Space` on button); high-contrast `:focus-visible` ring |
| Quick add strip | `<section class="quick-add-row">` with `.quick-add-row__label` and `.quick-add-row__items` containing `.action-link` items | `aria-label` + label text via `interface-catalog.json` | Sequential tab stops across empty-module action links |
| Badge / status badge | `<span class="badge">` or `<span class="status-badge status-badge--accent\|success\|warning\|danger">` | Status label localized via `interface-catalog.json` | Non-interactive indicator; never convey state by color alone |
| Menu | Trigger with `aria-haspopup="menu"` + `aria-expanded` + `aria-controls`; container `.menu` (`role="menu"`) with `.menu-item` (`role="menuitem"`) | Trigger `aria-label` and item text localized | `ArrowDown`/`ArrowUp`/`Home`/`End` navigate items; `Escape` closes and restores focus to trigger |
| Drawer | `<aside class="drawer">` paired with toggle button (`aria-controls`, `aria-expanded`) | `aria-label` or `aria-labelledby` localized | `Escape` closes overlay drawers and restores focus to trigger |
| Disclosure | `<details class="disclosure"><summary>…</summary>…</details>` | Summary label uses `data-en` / `data-l10n-text` | Native `Enter`/`Space` toggles `<details>`; auto-opens on validation error or non-default value |
| Diff view | `<div class="diff-view" role="region" aria-label="…">` containing `.diff-line` rows (`.diff-add`, `.diff-remove`, `.diff-context`, `.diff-hunk`, `.diff-header`) with `.diff-gutter` + `.diff-text` | Region `aria-label` localized; diff text rendered via `textContent` only | Scrollable region; line gutters (`+`/`−`) preserve non-color meaning |
| Page header & toolbar | `<header class="page-header">` (`.page-header__title`, `.page-header__subtitle`) and `<div class="toolbar">` | Title/subtitle and toolbar control labels localized | Standard horizontal tab order without wrapping above two bars |

Tests and smokes should select interactive targets using stable `id` or `data-*` / `data-testid` attributes rather than styling classes.

### Responsive containers and shell breakpoints

Page and component layouts respond to their owning container's inline size (`@container`) rather than the viewport width, because sidebars and the context rail change the content width inside a 900×620 or 1380×900 native window:

- **Shell containers (`container-type: inline-size`):** `.workspace-region` (`workspace`), `#context-rail` (`context-rail`), and `dialog` (`dialog`), alongside widget containers (`dashboard`, `dashboard-card`, `.room-context`, `#create-form`, `#meeting-board`).
- **Viewport `@media` widths (3 shell-level values maximum):**
  - `680px` (`max-width: 680px`) — compact global `.workspace-bar` utility controls;
  - `999px` (`max-width: 999px`) — switch sidebars and the context rail from docked columns into overlay drawers;
  - `1000px` (`min-width: 1000px`) — dock the context rail beside `.workspace-region` and enable multi-column desktop dashboard tracks.

## Work within the domain boundaries

- Put persistence and validation in the owning service or repository. The shell coordinates navigation and dispatch, and the frontend presents state. Share one paper and PDF, with per-project state kept as an association. Use test fixtures with conflicting revisions, missing references or partially completed operations when changing state transitions.
- Route project file actions through the current root, stable project ID, and current directory grant. Recheck grants at the point of use, including on cancellation, revoke, directory replacement or root switch. The hardened runtime is a bundle signing setting. The workspace grant is enforced by the application. Apple Calendar and Reminders have their own OS prompts.
- Project AI file edits are delegated to a supported local CLI running with its configured permission policy. Sci-Station presents the CLI's proposed action and forwards a one-time decision to the same live request. App-owned reviewed notes and tasks use the domain repository's revision and operation IDs. Cover refusal, cancellation, conflicts, restart and stale approvals when editing those paths.
- Keep PDF/Markdown evidence addressable by identity and revision. Add providers through the domain and gateway interfaces. Treat synthetic context as test fixtures, and keep provider keys in macOS Keychain. Use [workspaces](workspaces.md) and [versioning](VERSIONING.md) when changing storage or recovery behavior.

## Verify a change

For a new check, test the narrowest owning package first. Use isolated roots and fixtures. Run the repository checks when changing scripts, governance, versions or documentation.

```sh
Tools/scripts/check-repository-hygiene.sh
python3 Tools/scripts/check-docs-hygiene.py
python3 Tools/scripts/check-version-consistency.py
python3 Tools/scripts/check-frontend-metrics.py
python3 -m unittest discover -s Tools/tests -v
go test -race -tags nogui -coverprofile=coverage.out ./...
Tools/scripts/check-go-coverage.sh coverage.out
go vet -tags nogui ./...
node --test tests/*.test.cjs
```

The coverage check enforces a 74.0% statement coverage floor. The frontend metrics ratchet checks `web/static/*.css`, `*.js` and `*.html` against [Tools/frontend-metrics.json](../Tools/frontend-metrics.json); run `python3 Tools/scripts/check-frontend-metrics.py --print-baseline` to print updated counts when lowering a baseline. On a Mac with a logged-in graphical session, exercise startup, window gestures, trusted callbacks and persistent writes against a freshly built bundle.

```sh
make app verify
app=build/Sci-Station.app
python3 tests/macos-close-smoke.py "$app"
node tests/workstation-workflow-smoke.cjs --native "$app"
node tests/workstation-workbench-smoke.cjs "$app" "$TMPDIR/workbench-ui"
node tests/workstation-native-menu-smoke.cjs "$app"
node tests/workstation-storage-smoke.cjs "$app"
```

The shutdown smoke checks the signed app process and uses a separate test driver for window gestures. The workflow smoke exercises native PDF selection, a two-seat discussion, a refusal, confirmed writeback and return to the original passage after reopen, using a local model fixture. The workbench smoke checks calendar navigation, library search and selection, project switching and saved AI Lab appearance at 900×620 and 1440×900 in WKWebView. On the shorter GitHub virtual display, CI passes `--short-display` to exercise the same interactions at exactly 900×620 and 1440×620. It saves screenshots and observed results in the supplied output directory. The storage smoke starts the native app without command-line arguments in a disposable macOS home. It exercises default and custom data locations, scoped reopens, and recovery for missing or damaged selections. The native menu smoke exercises actual menu navigation and revocation of a window capability after switching roots. The Go and Node suites exercise CLI approval protocols with fixtures. To exercise an installed Codex executable against the isolated model fixture, run `SCI_STATION_TEST_CODEX=/path/to/codex node tests/workstation-cli-edit-smoke.cjs --native "$app"`. Name the binary, model or CLI, OS version and test mode in validation reports. Finder approval, Keychain and EventKit prompts require separate observation.

## Package and install

[Public Release](../.github/workflows/release.yml) uses the same Go/Wails build. For explicit packaging validation from the repository root:

```sh
Tools/scripts/package-release.sh --app build/Sci-Station.app
Tools/scripts/verify-release.sh path/to/Sci-Station.dmg
Tools/scripts/test-release-install.sh --native-ui path/to/previous.dmg path/to/candidate.dmg
Tools/scripts/test-release-install.sh --native-ui path/to/previous.zip path/to/candidate.zip
```

Installer smokes require two archives with the same app version and a lower build number on the first. Put their SHA-256 sidecars beside the archives. CI makes the lower build from the same checkout and tests both formats on macOS 15 using disposable application and research directories. The fixture verifies install, overwrite, persistent data reopening and rollback for those builds. The `--native-ui` option adds an independent Xcode test target that launches the exact installed bundle and clicks between Home and Library after the initial install and upgrade. It requires a graphical macOS session. CI always enables it for both archive formats. Record any specific historical release upgrade test separately.

The distribution model uses ad-hoc code signing with hardened runtime. The verifier checks the expected signature, app layout, arm64 and macOS deployment target, plus archive integrity and checksum. Developer ID and Apple notarization are outside the distribution model. This preview stores credentials in the user's file-based login keychain. Enforcing device-only accessibility requires a provisioned access group and the macOS data protection keychain. [Apple TN3137](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains) describes the two implementations. GitHub releases provide SHA-256 and build provenance. Downloaders may verify that provenance with `gh attestation verify path/to/Sci-Station.dmg --repo Funyday-k/Sci-Station`. If macOS blocks first launch after download, check the download source and hash before explicitly choosing **Open Anyway** for Sci-Station in **System Settings → Privacy & Security**.

See [versioning](VERSIONING.md) for tag and build number rules. Daily builds and published previews use the same application source and separate acceptance steps.
