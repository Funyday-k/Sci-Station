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
python3 -m unittest discover -s Tools/tests -v
go test -race -tags nogui -coverprofile=coverage.out ./...
Tools/scripts/check-go-coverage.sh coverage.out
go vet -tags nogui ./...
node --test tests/*.test.cjs
```

The coverage check enforces a 74.0% statement coverage floor. On a Mac with a logged-in graphical session, exercise startup, window gestures, trusted callbacks and persistent writes against a freshly built bundle.

```sh
make app verify
app=build/Sci-Station.app
python3 tests/macos-close-smoke.py "$app"
node tests/workstation-workflow-smoke.cjs --native "$app"
node tests/workstation-workbench-smoke.cjs "$app" "$TMPDIR/workbench-ui"
node tests/workstation-native-menu-smoke.cjs "$app"
```

The shutdown smoke checks the signed app process and uses a separate test driver for window gestures. The workflow smoke exercises native PDF selection, a two-seat discussion, a refusal, confirmed writeback and return to the original passage after reopen, using a local model fixture. The workbench smoke checks calendar navigation, library search and selection, project switching and saved AI Lab appearance at 900×620 and 1440×900 in WKWebView. It saves screenshots and observed results in the supplied output directory. The native menu smoke exercises actual menu navigation and revocation of a window capability after switching roots. The Go and Node suites exercise CLI approval protocols with fixtures. To exercise an installed Codex executable against the isolated model fixture, run `SCI_STATION_TEST_CODEX=/path/to/codex node tests/workstation-cli-edit-smoke.cjs --native "$app"`. Name the binary, model or CLI, OS version and test mode in validation reports. Finder approval, Keychain and EventKit prompts require separate observation.

## Package and install

[Public Release](../.github/workflows/release.yml) uses the same Go/Wails build. For explicit packaging validation from the repository root:

```sh
Tools/scripts/package-release.sh --app build/Sci-Station.app
Tools/scripts/verify-release.sh path/to/Sci-Station.dmg
Tools/scripts/test-release-install.sh --native-ui path/to/previous.dmg path/to/candidate.dmg
Tools/scripts/test-release-install.sh --native-ui path/to/previous.zip path/to/candidate.zip
```

Installer smokes require two archives with the same app version and a lower build number on the first. Put their SHA-256 sidecars beside the archives. CI makes the lower build from the same checkout and tests both formats on macOS 15 using disposable application and research directories. The fixture verifies install, overwrite, persistent data reopening and rollback for those builds. The `--native-ui` option adds an independent Xcode test target that launches the exact installed bundle and clicks between Home and Library after the initial install and upgrade. It requires a graphical macOS session. CI always enables it for both archive formats. Record any specific historical release upgrade test separately.

The distribution model uses ad-hoc code signing with hardened runtime. The verifier checks the expected signature, app layout, arm64 and macOS deployment target, plus archive integrity and checksum. Developer ID and Apple notarization are outside the distribution model. GitHub releases provide SHA-256 and build provenance. Downloaders may verify that provenance with `gh attestation verify path/to/Sci-Station.dmg --repo Funyday-k/Sci-Station`. If macOS blocks first launch after download, check the download source and hash before explicitly choosing **Open Anyway** for Sci-Station in **System Settings → Privacy & Security**.

See [versioning](VERSIONING.md) for tag and build number rules. Daily builds and published previews use the same application source and separate acceptance steps.
