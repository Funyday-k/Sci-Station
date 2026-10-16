# Contributing to Sci-Station

Sci-Station welcomes bug reports, documentation improvements and focused code contributions. Read the [developer guide](docs/DEVELOPER.md) for architecture and build commands, the [code of conduct](CODE_OF_CONDUCT.md) for collaboration expectations, and the [security policy](SECURITY.md) before reporting a vulnerability.

## From requirement to release

1. Open an Issue describing the problem and observable acceptance criteria. For a security issue, use private reporting instead. Small documentation corrections may link an existing Issue or a versioned backlog item.
2. For a new domain, persistent format, permission boundary or runtime change, propose an [RFC](docs/rfcs/README.md). Record the accepted decision in an [ADR](docs/architecture/README.md).
3. Create a short-lived branch from `main`, for example `feat/123-paper-import`, `fix/124-path-check`, or `codex/governance-refactor`. `dev` is a transitional integration branch; it is not a release source and new work should target `main`.
4. Open a PR with the problem, resulting behavior, linked requirement, validation evidence and any migration or rollback steps. Use `Closes #123`, an Issue URL, or an existing `docs/rfcs/RFC-*.md`, `docs/architecture/ADR-*.md` or `docs/BACKLOG.md#...` reference in its description. The traceability check verifies local references and rejects an empty template.
5. Merge only after `Required CI` succeeds and review conversations are resolved. During single-maintainer operation, the maintainer records a self-review in the PR; GitHub does not count an author's review as an independent approval. Add one required independent approval when a second regular maintainer is available.
6. Update [CHANGELOG.md](CHANGELOG.md) under `Unreleased`. Release tags point to commits reachable from `main`; the [release workflow](.github/workflows/release.yml) builds and verifies that commit.

Do not push directly to `main` or `dev`, force-push shared branches, or reuse a published release tag. See the [governance policy](docs/GOVERNANCE.md) for the settings and their verification commands.

## Local verification

Use an Apple Silicon Mac with macOS 15 or later and an Xcode toolchain supporting Swift Testing. For Python tooling use Python 3.11 or later in an isolated environment:

```bash
python3 -m venv .venv
.venv/bin/python -m pip install -e './AgentRuntime[test,uitest]'
python3 Tools/scripts/check-docs-hygiene.py
python3 Tools/scripts/check-version-consistency.py
python3 Tools/scripts/check-core-runner-architecture.py
python3 -m unittest discover -s Tools/tests -v
Tools/scripts/check-repository-hygiene.sh
Tools/scripts/check-appviewmodel-architecture.sh
swift test --enable-code-coverage
Tools/scripts/check-swift-coverage.sh "$(swift test --show-codecov-path)" 14.0
swift run SciStationCoreTestRunner
.venv/bin/python -m pytest AgentRuntime/tests
```

The developer guide also covers pinned SwiftLint/SwiftFormat, Release builds, installation checks and UI smoke tests. CI runs all required gates even for documentation PRs so required checks cannot remain pending due to path filters. If a local check cannot run, describe the limitation in the PR; do not report it as passing.

## Code and test boundaries

- Put domain decisions and state in focused Core stores, services or repositories; keep AppViewModel responsible for coordination. Its family-wide budget applies across extensions.
- Put new unit and domain tests in `Tests/SciStationCoreTests/`. Legacy integration checks are grouped under `Tools/SciStationCoreTestRunner/Suites/`; shared fixtures belong under `Support/`. Keep the runner entry point small. Preserve each check's assertions when migrating it to Swift Testing.
- Use isolated temporary workspaces and labeled fixtures. Never commit private papers, Research Roots, API credentials, certificates, generated packages or machine-specific configuration.
- Document compatibility and migration effects using the [versioning policy](docs/VERSIONING.md). A component version is not automatically the app version.

## Review checklist

Review behavior and failure paths, tests, source of truth, actor/thread ownership, file and credential boundaries, accessibility when relevant, and documentation. For persisted data changes, check older input, unknown fields, failed writes and recovery. For security changes, record the private advisory reference without disclosing exploitation details in a public PR.

Contributions are distributed under the repository's [MIT license](LICENSE).
