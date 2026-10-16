# Requests for comments

Use an RFC for a new domain, persistent schema, runtime promotion, permission boundary or other change with significant alternatives. Routine fixes can go directly through an Issue and PR.

1. Copy [TEMPLATE.md](TEMPLATE.md) to the next `RFC-NNNN-short-title.md` and set its status to `Proposed`.
2. Link the requirement, describe the user outcome, alternatives, data/permission effects, migration, validation and rollback.
3. Discuss in the design PR. Record unanswered questions and do not represent proposed behavior as shipped functionality.
4. On acceptance, update status, record the actual decision PR link and create an ADR. Split implementation into Issues with concrete acceptance criteria and release links.

| RFC | Status | Topic |
| --- | --- | --- |
| [RFC-0001](RFC-0001-knowledge-architecture.md) | Proposed | Knowledge Architecture V1 |

Status values are `Proposed`, `Accepted`, `Rejected`, and `Superseded`. This directory replaces references to an unversioned Proposal as the sole authority for promoting an experimental runtime.
