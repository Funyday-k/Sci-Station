# Agent guidelines

This is the entry point for coding agents working in this repository. Codex reads this file directly; Claude Code reads [CLAUDE.md](CLAUDE.md), which imports it. Human contributors can use it as a summary.

This file states rules and points to the documents that define them. It is the source of truth only for the agent-collaboration rules in [Working with several agents](#working-with-several-agents). If anything else here disagrees with a linked document, the linked document wins; fix this file in the same pull request.

## Sources of truth

| Topic | Authoritative document |
| --- | --- |
| Requirement-to-merge workflow, review checklist | [CONTRIBUTING.md](CONTRIBUTING.md) |
| Branch protection, required checks, release controls | [docs/GOVERNANCE.md](docs/GOVERNANCE.md) |
| Architecture, code map, build and test commands | [docs/DEVELOPER.md](docs/DEVELOPER.md) |
| Version sources and compatibility contracts | [docs/VERSIONING.md](docs/VERSIONING.md) |
| Planned work | GitHub Issues and [docs/BACKLOG.md](docs/BACKLOG.md) |
| Design proposals and accepted decisions | [RFCs](docs/rfcs/README.md) and [ADRs](docs/architecture/README.md) |
| Vulnerability reporting | [SECURITY.md](SECURITY.md) |

`docs/development/` and `docs/user-feedback/` are gitignored local notes. They can be stale. Do not treat them as requirements, and do not link to them from tracked files.

## Before changing anything

1. Work from a GitHub Issue or an anchored `docs/BACKLOG.md` item that states acceptance criteria. If none exists, ask the maintainer or draft an Issue for approval; do not invent scope.
   Security vulnerabilities are the exception: follow [SECURITY.md](SECURITY.md), and never put exploitation details in a public Issue, pull request, commit or log. A public pull request may cite only the private advisory reference.
2. A new domain, persisted format, permission boundary or runtime change needs an accepted RFC and a recorded ADR first. A proposed RFC does not authorize implementation.
3. Read the closest domain directory and its existing tests first. Extend existing implementations instead of adding parallel ones.

## Branches, commits and pull requests

- Branch from an up-to-date `origin/main` as `<type>/<issue>-<slug>`, where type is `feat`, `fix`, `docs`, `refactor`, `test`, `chore` or `release` (for example `fix/124-path-check`). Keep each branch and pull request to one linked requirement.
- Never push to `main` or `dev`, force-push a shared branch, move or reuse a published tag, or merge a pull request. The maintainer merges once `Required CI` passes on an up-to-date base, review conversations are resolved and a self-review is recorded, as [GOVERNANCE](docs/GOVERNANCE.md) requires.
- Prefix commit subjects with the same types (`fix: ...`) and keep each commit to one logical change.
- Fill in [the PR template](.github/PULL_REQUEST_TEMPLATE.md). The description must link `Closes #123`, an Issue URL, an existing RFC/ADR path or an anchored `docs/BACKLOG.md#...` item, or the traceability gate fails. Write the reference as plain text: the gate ignores HTML comments and fenced code, and does not count Issue references inside code spans.
- Record user-visible changes under `[Unreleased]` in [CHANGELOG.md](CHANGELOG.md). Change `VERSION`, marketing versions or build numbers only in a release-preparation pull request.
- Runtime, sidecar protocol, workspace schema and manifest versions follow their own contracts in [VERSIONING](docs/VERSIONING.md). Bump them only when that component changes, never by bulk replacement, and cover the compatibility effect with tests.

## Working with several agents

- Give each agent its own branch and its own `git worktree`. Never let two agents edit the same checkout at the same time.
- The agent that implements a change does not approve it. A different agent or the maintainer reviews the final diff before merge.
- Put hand-off state that the maintainer or another agent needs in the Issue or pull request. Local notes and chat history may supplement it but are never the only record.

## Code boundaries

- Put domain decisions and state in Core stores, services and repositories under the matching `Sci-Station/<Domain>/` directory. `AppViewModel` only coordinates; `Tools/scripts/check-appviewmodel-architecture.sh` enforces its budget.
- Core code is `nonisolated` by default. Mark only UI, state stores and coordinators `@MainActor`, and keep Swift 6 concurrency checks clean.
- Paper `meta.yaml` writes must preserve unknown fields and nested structure, and malformed YAML must produce an explicit error instead of an overwrite. Other persisted formats follow their compatibility contracts; for any persisted-data change, test older input, unknown fields, failed writes and recovery.
- AI write actions go through the permission model and user approval. Production paths never use synthetic or sample evidence. Swift Loop is the production default; the Python sidecar is experimental.
- Credentials belong in the macOS Keychain only. Never commit Research Roots, papers, API keys, tokens, `.env*`, `.mcp.json`, `.claude/`, `.codex/config.toml`, local bridge configuration, build products or `.tmp/`.
- Do not lower coverage floors or architecture budgets, refresh `.swiftlint-baseline.json`, or weaken a CI job to make a change pass.

## Tests

- Add new Swift tests as Swift Testing suites in `Tests/SciStationCoreTests/`. The legacy runner in `Tools/SciStationCoreTestRunner/` remains required; when migrating a check, keep its assertions and remove the legacy registration only after parity is shown.
- Every Python sidecar change needs pytest coverage in `AgentRuntime/tests/`.
- Use isolated temporary workspaces and clearly labeled fixtures.

## Minimum local validation

CI runs every gate on every pull request. Before opening one, run at least the checks for each kind of change you made, starting with the most focused test. Python tooling expects a virtual environment: `python3 -m venv .venv && .venv/bin/python -m pip install -e './AgentRuntime[test,uitest]'`.

| Change | Minimum local checks |
| --- | --- |
| Any change | `Tools/scripts/check-repository-hygiene.sh` |
| Markdown, governance, CI or version files | `python3 Tools/scripts/check-docs-hygiene.py`, `python3 Tools/scripts/check-version-consistency.py`, `python3 -m unittest discover -s Tools/tests -v` |
| Swift Core | `swift test --filter <Suite>`, then `swift test --enable-code-coverage`, `Tools/scripts/check-swift-coverage.sh "$(swift test --show-codecov-path)" 14.0` and `swift run SciStationCoreTestRunner`; `Tools/scripts/check-appviewmodel-architecture.sh`; the pinned Swift style check from the developer guide |
| Legacy runner layout | `python3 Tools/scripts/check-core-runner-architecture.py` |
| SwiftUI, layout or navigation | Build the app (`script/build_and_run.sh` or Xcode) and exercise the changed screen; run the native UI smoke test when navigation changes |
| Python sidecar | `.venv/bin/python -m pytest AgentRuntime/tests` |
| Packaging and release scripts | `bash -n` on changed scripts; run full packaging only when preparing a release |

## Reporting

- In the pull request and in the final hand-off, list the commands run and their results.
- Name every relevant check that was not run and why. Never report a skipped or failed check as passing.
- Separate verified behavior from expectations, and record remaining limitations in the Issue.
