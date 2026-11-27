# Requests for comments

Use an RFC for a new domain, persistent schema, runtime promotion, permission boundary or other change with significant alternatives. Routine fixes can go directly through an Issue and PR.

1. Copy [TEMPLATE.md](TEMPLATE.md) to the next `RFC-NNNN-short-title.md` and set its status to `Proposed`.
2. Link the requirement, describe the user outcome, alternatives, data/permission effects, migration, validation and rollback.
3. Discuss in the design PR. Record unanswered questions and do not represent proposed behavior as shipped functionality.
4. On acceptance, update status, record the actual decision PR link and create an ADR. Split implementation into Issues with concrete acceptance criteria and release links.

| RFC | Status | Topic |
| --- | --- | --- |
| [RFC-0001](RFC-0001-knowledge-architecture.md) | Proposed | Knowledge Architecture V1 and its [review and recovery proposal](knowledge-v1-review-and-recovery.md) |
| [RFC-0002](RFC-0002-roundtable-workstation.md) | Accepted | One Sci-Station workstation on the Roundtable desktop host |
| [RFC-0003](RFC-0003-project-records-and-conversion-recovery.md) | Accepted | Project and paper record versions and recoverable conversion submissions |
| [RFC-0004](RFC-0004-frontend-build-layer.md) | Accepted | Evaluate a frontend build layer or component framework |

Status values are `Proposed`, `Accepted`, `Rejected`, and `Superseded`.
