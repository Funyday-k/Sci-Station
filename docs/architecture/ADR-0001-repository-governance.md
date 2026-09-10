# ADR-0001: PR-based delivery and required CI

- Status: Accepted for this governance change, implementing the requested review recommendations.
- Requirement: [GOV-001](../BACKLOG.md#gov-001--repository-governance-and-delivery-gates).

## Context

Sci-Station has an app, a Python sidecar, persistent user data, security boundaries and downloadable artifacts. Written local checks alone do not prevent unchecked changes from reaching a release branch. A single maintainer also cannot supply an independent approval on their own PR.

## Decision

Use `main` as the release source and short-lived PR branches for new work. Preserve and protect `dev` during transition. Require up-to-date PRs, resolved conversations and an aggregate `Required CI` result for all maintainers including administrators. Require zero independent approvals during single-maintainer operation, record self-review, and move to one independent approval when another regular maintainer joins.

Every PR links an Issue or an existing versioned RFC/ADR/backlog item. CI validates reference syntax and local targets. Release tags must identify a tested commit reachable from `main`, pass version and quality checks, and produce verified signed artifacts. Preview maturity and artifact signing are described separately.

## Alternatives

Direct pushes plus voluntary checks do not establish a gate. Mandatory independent approval would block a sole maintainer. Deleting `dev` immediately could discard a useful integration reference. A single large release PR with no requirement links would preserve little design context.

## Consequences

Hosted GitHub settings must be applied and checked independently of repository files. A failing or absent required check blocks merging. Repository-local backlog references allow this initial governance change to be reviewed before historical Issues exist. Reviewers still assess relevance and acceptance criteria; a syntactically valid link is insufficient evidence of correctness.

## Validation

Run governance script tests, docs/version checks and the full CI suite. Query branch protection and private reporting through GitHub. Test the empty-template and missing-local-reference failure paths. See [GOVERNANCE](../GOVERNANCE.md) for the live-check commands.
