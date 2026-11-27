# Contributing to Sci-Station

Read the [developer guide](docs/DEVELOPER.md) for the Go/Wails architecture and verification commands, the [code of conduct](CODE_OF_CONDUCT.md) for collaboration, and the [security policy](SECURITY.md) for private vulnerability reporting. Coding agents start from [AGENTS.md](AGENTS.md).

## From requirement to release

1. Open an issue with the problem and observable acceptance criteria. Small documentation changes can use an existing issue or an anchored backlog item. Report vulnerabilities privately.
2. For a new domain, persisted format, permission boundary or runtime change, propose an [RFC](docs/rfcs/README.md) and record the accepted decision in an [ADR](docs/architecture/README.md).
3. Branch from up-to-date `origin/main` as `<type>/<issue>-<slug>`, for example `fix/124-path-check`. Prefix the commit subject with the same type. Keep each branch and PR to one requirement.
4. Complete the [PR template](.github/PULL_REQUEST_TEMPLATE.md) with behavior, requirements, evidence, and any recovery or rollback steps. Put `Closes #123`, an Issue URL, an existing RFC/ADR path or an anchored backlog item in the visible PR description.
5. Review the final diff and acceptance evidence before merge. On the Go/Wails cutover, require green `Required CI` and independent review. The maintainer merges on an up-to-date base with all review conversations resolved. Follow the [governance policy](docs/GOVERNANCE.md) for review and branch protection.
6. Record user-visible changes under `Unreleased` in the [changelog](CHANGELOG.md). Tags identify reviewed commits on `main` and are immutable. The [release workflow](.github/workflows/release.yml) builds and verifies the tagged commit.

## Local verification

On Apple Silicon with macOS 15 or later, use Go 1.26, Xcode Command Line Tools, Node.js and Python 3. Start with the smallest relevant package or test.

```sh
make test
Tools/scripts/check-repository-hygiene.sh
python3 Tools/scripts/check-docs-hygiene.py
python3 Tools/scripts/check-version-consistency.py
python3 -m unittest discover -s Tools/tests -v
```

See the [developer guide](docs/DEVELOPER.md#verify-a-change) for Go race, coverage and vet; browser and native smoke checks; and package validation. CI runs every gate on each PR, including documentation changes. Record the commands and results in the PR, and name any checks that could not run.

## Review checklist

- Check state and persistence in the owning domain, supported older data, unknown fields, failure paths and recovery. Use isolated roots for tests.
- Check workspace and project scope, stale requests, and privilege when touching files, credentials, reviewed actions or direct CLI editing.
- Verify visible behavior, accessibility and compliance with the [workbench layout rules](docs/DEVELOPER.md#workbench-layout-rules) for UI PRs, and describe changes to data compatibility in the [versioning policy](docs/VERSIONING.md).
- Keep credentials, private papers, research roots, local configuration and generated packages out of commits. Security fixes may cite the private advisory reference in a public PR.

Contributions use the repository's [MIT license](LICENSE).
