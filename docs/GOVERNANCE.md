# Repository governance

The delivery chain is **Issue → RFC/ADR when needed → short-lived branch → PR → required CI → main → versioned release**. [CONTRIBUTING](../CONTRIBUTING.md) is the contributor entry point. [BACKLOG](BACKLOG.md) records the initial governance and architecture work without inventing historical GitHub Issue or PR numbers.

## Branches and review

`main` is the product integration and release source. `dev` remains a protected transitional integration branch so existing work can move through PRs; do not delete it while it contains unmerged work. Start new branches from `main`. Both branches require a PR, the `Required CI` check from GitHub Actions, an up-to-date base, and resolved review conversations. Administrators are subject to these rules; force pushes and deletion are disabled.

The current owner is `@Funyday-k`, recorded in [CODEOWNERS](../.github/CODEOWNERS). A single maintainer can merge a PR after recording a self-review and passing CI; required independent approvals are zero because authors cannot approve their own PRs. When another regular maintainer joins, raise this to one and require code-owner review for architecture, security and release tooling. Do not weaken CI to work around a failure.

## Enforced checks

The [macOS CI workflow](../.github/workflows/macos-ci.yml) has no path filters. Its `Required CI` job runs with `always()` and fails unless all of these jobs succeed:

| Check | Evidence |
| --- | --- |
| Repository hygiene | Tracked artifact checks, documentation links, app/runtime version consistency, governance tooling tests, AppViewModel and core runner budgets |
| Change traceability | A PR description links an Issue or a real, accepted/versioned local decision or backlog item |
| SwiftLint and SwiftFormat | Pinned tools and existing baseline; no new style debt |
| Swift test gates | Swift Testing, coverage floor, every legacy integration check |
| Python sidecar tests | Full `AgentRuntime/tests` suite |
| Apple Silicon Release build and smoke test | Unsigned app build, bundled runtime, installation and UI checks |

CI cannot judge whether an Issue's acceptance criteria are actually met; that remains part of review. A linked Issue reference is syntactically checked; the maintainer verifies that it exists and is relevant. Local RFC/ADR paths and backlog anchors are checked against the checkout. Proposed RFCs are design artifacts, not permission to silently ship a new architecture.

## Remote configuration

[repository-settings.json](../.github/repository-settings.json) records the intended description, topics and branch protection payload. These files alone do not configure GitHub. Inspect live settings with:

```bash
gh api repos/Funyday-k/Sci-Station --jq '{description,topics}'
gh api repos/Funyday-k/Sci-Station/branches/main/protection
gh api repos/Funyday-k/Sci-Station/branches/dev/protection
gh api repos/Funyday-k/Sci-Station/private-vulnerability-reporting
```

Require private vulnerability reporting to be enabled before advertising the security form. The repository already uses secret scanning and push protection; preserve those controls. The branch-protection contract uses the stable aggregate check name, so changing individual CI job names must also update the aggregate dependencies. A new PR containing this workflow must pass before merging; the existing default-branch history does not acquire new check results retroactively.

The governance change applied the checked-in metadata and protection payload to both branches and enabled private reporting; GitHub API readback confirmed `protected: true` for `main` and `dev`. The `release` environment was absent during this audit, so no credentialed release was attempted. Treat the readback as change evidence and rerun the commands above when auditing current settings.

Use the official [branch protection API](https://docs.github.com/en/rest/branches/branch-protection) and [private reporting documentation](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/configure-vulnerability-reporting/configure-for-a-repository) when changing these settings. Avoid undocumented bypasses or emergency direct pushes; record an incident and restore the normal gates after resolving a repository administration problem.

## Release controls

The release workflow verifies that the exact tag matches [VERSION](../VERSION), its commit is reachable from `origin/main`, and the build number advances. It reruns repository/docs/version/architecture, style, Swift and Python checks before importing signing credentials. Signed artifacts must pass notarization, Gatekeeper, installation, minimum-macOS and provenance checks before publication.

Tag-triggered releases are published as GitHub prereleases during the preview phase. Stable publication is an explicit workflow-dispatch choice after readiness review; signing alone does not establish product stability. The `release` environment needs real Developer ID and Apple notary secrets configured by the owner. Configure environment deployment rules for release tags and reviewer protection when a second maintainer is available. See [DEVELOPER](DEVELOPER.md) for the exact credentials and packaging commands. Never store them in this repository.
