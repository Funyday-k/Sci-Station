# Agent guidelines

This is the entry point for coding agents in Sci-Station. Codex reads it directly and Claude Code reads [CLAUDE.md](CLAUDE.md), which imports it. This document owns the agent collaboration rules. The linked documents own their respective technical and delivery contracts.

## Sources of truth

| Topic | Authoritative document |
| --- | --- |
| Requirement-to-merge workflow, review checklist | [CONTRIBUTING.md](CONTRIBUTING.md) |
| Branch protection, required checks, release controls | [docs/GOVERNANCE.md](docs/GOVERNANCE.md) |
| Architecture, code map, build and test commands | [docs/DEVELOPER.md](docs/DEVELOPER.md) |
| Version sources and compatibility contracts | [docs/VERSIONING.md](docs/VERSIONING.md) |
| Planned work | GitHub Issues and [docs/BACKLOG.md](docs/BACKLOG.md) |
| Design proposals and decisions | [RFCs](docs/rfcs/README.md) and [ADRs](docs/architecture/README.md) |
| Vulnerability reporting | [SECURITY.md](SECURITY.md) |

`docs/development/` and `docs/user-feedback/` are local notes. They can be stale. Keep requirements and hand-off context in the linked issue or PR and keep tracked documentation independent of local notes.

## Before changing anything

1. Work from a GitHub Issue or an anchored item in [docs/BACKLOG.md](docs/BACKLOG.md) with acceptance criteria. Ask the maintainer or draft an Issue for review when there is no requirement. Follow [SECURITY.md](SECURITY.md) for privately reported vulnerabilities.
2. Before introducing a new domain, persisted format, permission boundary or runtime, obtain acceptance for the RFC and record an ADR.
3. Read the owning implementation and its tests. Extend the existing Go service and the shared desktop shell.

## Branches, commits and pull requests

- Branch from up-to-date `origin/main` as `<type>/<issue>-<slug>`, using `feat`, `fix`, `docs`, `refactor`, `test`, `chore` or `release`. Prefix each commit subject with the same type.
- Use the [PR template](.github/PULL_REQUEST_TEMPLATE.md). Put the Issue reference, RFC or ADR path, or backlog anchor in visible text, outside comments, code spans and fences.
- Preserve `main` protection and immutable tags. The maintainer merges reviewed work with green `Required CI`, an up-to-date base and resolved review conversations, as described in [GOVERNANCE](docs/GOVERNANCE.md).
- Record user-facing changes under `Unreleased` in [CHANGELOG.md](CHANGELOG.md). Update `VERSION` and `BUILD_NUMBER` in release-preparation changes only. Changes to persisted schemas and plugin manifests follow their own [version contracts](docs/VERSIONING.md).

## Working with several agents

- Give each agent its own branch and its own `git worktree`. Never let two agents edit the same checkout at the same time.
- The agent that implements a change does not approve it. A different agent or the maintainer reviews the final diff before merge.
- Put hand-off state that the maintainer or another agent needs in the Issue or pull request. Local notes and chat history may supplement it but are never the only record.

## Code and test boundaries

- Domain services own state, validity and persistence. The Wails shell coordinates native lifecycle and navigation. Frontend code should use the same workspace and project identity as native menus and routes.
- Recheck the current workspace and project grant at the point of file access. Use operation IDs and revisions for app-owned reviewed writes. Route local AI file editing through the selected CLI's permission policy and forward the decision to its original live request.
- Keep persistent credentials in macOS Keychain. Keep research roots, papers, environment files, local CLI/MCP and tool configuration, tokens, generated bundles and `.tmp/` out of Git.
- Use isolated temporary roots, clearly labelled fixtures and production data paths. For persistence changes cover supported older inputs, unknown fields, failed writes and recovery. Keep CI, coverage and release enforcement intact.

## Minimum local validation

Start with the narrowest relevant test. See the [developer guide](docs/DEVELOPER.md#verify-a-change) for command combinations and fixture scope. CI runs every required gate on each pull request.

| Change | Minimum local checks |
| --- | --- |
| Any change | `Tools/scripts/check-repository-hygiene.sh` |
| Markdown, governance, CI or versions | `python3 Tools/scripts/check-docs-hygiene.py`, `python3 Tools/scripts/check-version-consistency.py`, `python3 -m unittest discover -s Tools/tests -v` |
| Go application or domain code | Focused Go test, race suite with coverage, coverage gate and Go vet |
| Frontend, navigation or native bridges | Node tests; build and exercise the affected screen; run the relevant native smoke scenario |
| Packaging or release scripts | Shell syntax check, app bundle verification and relevant packaged smoke for distribution changes |

Report the commands and results, any check that could not be run, and the behavioral or environment limits of the evidence. Keep remaining acceptance items in the Issue.

Read the [security policy](SECURITY.md) before handling vulnerabilities. Keep reproduction details in the private advisory.
