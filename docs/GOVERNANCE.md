# Repository governance

Changes follow **Issue → RFC/ADR when needed → short-lived branch → PR → Required CI → main → versioned release**. See the [contributor entry point](../CONTRIBUTING.md), [backlog](BACKLOG.md) and [cutover decision](architecture/ADR-0004-roundtable-workstation.md).

## Branch and review

`main` is the integration and release branch, and new work starts from its current remote head. The Go/Wails cutover retires the transitional `dev` branch after its needed work has an enduring reference. The protection on `main` requires a PR, an up-to-date base, the GitHub Actions `Required CI` result and resolved review conversations. It covers administrators and disallows force pushes and branch deletion.

The current owner is `@Funyday-k`, recorded in [CODEOWNERS](../.github/CODEOWNERS). The maintainer records a review in the PR. The Go/Wails cutover requires a separate reviewer to check the final diff and acceptance evidence alongside green `Required CI`. Agent-authored work also requires a review by a different agent or the maintainer. GitHub's required approving-review count remains zero during single-maintainer operation because authors cannot approve their own PRs. When another regular maintainer joins, require one approval and code-owner review for architecture, security and release tooling.

## Required CI

The [macOS CI workflow](../.github/workflows/macos-ci.yml) has no path filters. Its `Required CI` aggregate runs with `always()` and fails unless all four jobs succeed.

| Job | Evidence |
| --- | --- |
| Repository hygiene | Tracked artifact checks, documentation links, app version and build number consistency, and governance tool tests. |
| Change traceability | A PR description links a real Issue, a versioned decision or a backlog item. |
| Workstation | Go race, coverage and vet, frontend tests, signed arm64 bundle and deployment target, native shutdown and relaunch, PDF-to-Roundtable writeback, and native menu navigation. Go and Node fixtures cover the CLI approval protocol. |
| Workstation install, upgrade and rollback | Verified ZIP, DMG and SHA-256 from the same checkout on Apple Silicon macOS 15, with a lower-build fixture and a disposable workspace. |

Reviewers verify the requirement link and the behavior claimed by each change. For a new runtime or permission boundary, the relevant RFC and ADR must record acceptance before implementation. See [developer verification](DEVELOPER.md) for local checks and the limits of controlled fixtures.

## Remote configuration

[Repository settings](../.github/repository-settings.json) describe the intended repository metadata and the protection payload for `main`. Verify the corresponding GitHub settings when auditing the remote.

```sh
gh api repos/Funyday-k/Sci-Station --jq '{default_branch,description,topics}'
gh api repos/Funyday-k/Sci-Station/branches/main/protection
gh api repos/Funyday-k/Sci-Station/private-vulnerability-reporting
```

Keep private reporting, secret scanning and push protection enabled. GitHub settings take effect independently of these files. Preserve the stable aggregate name and update its job dependencies when changing the required workflow. A PR containing workflow changes must pass the revised checks before merging. Use the [GitHub branch protection API](https://docs.github.com/en/rest/branches/branch-protection) and [private reporting documentation](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/configure-vulnerability-reporting/configure-for-a-repository) for changes.

## Release controls

The [release workflow](../.github/workflows/release.yml) checks that the tag matches [VERSION](../VERSION), its commit is reachable from `origin/main` and [BUILD_NUMBER](../BUILD_NUMBER) advances from the previous release. It verifies the Go/Wails app, macOS 15 installation and rollback, archives, checksums and GitHub provenance before publication. Artifact signing is ad-hoc with hardened runtime; a downloaded app may require explicit macOS approval on first open. See [packaging and installation](DEVELOPER.md#package-and-install) for verification and first-launch instructions.

Tag-triggered releases publish as Developer Previews. Stable publication is an explicit workflow-dispatch choice after readiness review. Only the attestation job has provenance write permissions and only publication can write release assets. Tags are immutable. The [release history](../CHANGELOG.md) preserves the behavior and limitations of earlier downloads.
