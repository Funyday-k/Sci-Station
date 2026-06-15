# Documentation Cleanup Plan

Status: Active
Last updated: 2026-06-16

This file records the current documentation hygiene pass and the next migrations. It is a working process note, not a product roadmap.

## Current Findings

- Public docs should not point readers directly to the local `docs/user-feedback/` inbox. That directory is a gitignored intake area and belongs only in process docs.
- The development branch is `dev`; distribution packaging should come from `main`.
- README should describe current user-visible capability. Future work belongs in `roadmap/Backlog.md` or a Proposal.
- `Queue` and `ReadingPlan` should remain only as retired terms or historical references. The active terms are `Recommendation` and reading Todo.
- Internal phase labels are acceptable in historical Proposal or UI-test IDs, but should not appear in user-facing product copy.

## Next Migrations

1. Review and extend `Tools/scripts/check-docs-hygiene.py` as terminology and release rules evolve.
2. Review completed Proposals after each cleanup pass and move true deferred work to Backlog instead of leaving it as current execution scope.
3. Recheck English docs after every Chinese README change, especially current features, roadmap, and quick-start wording.
4. Review module docs for one-time execution notes that should move to `ImplementationSummary-*` or release records.
5. Review code comments for `Pending:`, `Compatibility:`, and `Unavailable:` ownership links once the documentation scan script exists.

## Acceptance Checks

- Root README and developer entry docs do not expose local feedback inbox as a public navigation item.
- `docs/development/README.md` names `dev` as the development branch and `main` as the distribution source.
- `DocumentationPolicy.md` defines content status, source-of-truth ownership, terminology, and blank-space rules.
- Backlog contains follow-up documentation hygiene work that is not part of the current cleanup.
- `python3 Tools/scripts/check-docs-hygiene.py` reports no errors.
