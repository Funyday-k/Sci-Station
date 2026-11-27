# Architecture decision records

ADRs record decisions and their consequences. Use an [RFC](../rfcs/README.md) to propose a significant change before implementation. After review, add a numbered ADR, link its requirement and implementation PR, and update this index. Never invent an approval, Issue number or historical rationale that cannot be established from the code or discussion.

| ADR | Status | Decision |
| --- | --- | --- |
| [ADR-0001](ADR-0001-repository-governance.md) | Accepted for this change | PR-based delivery and required CI |
| [ADR-0002](ADR-0002-application-state-and-testing.md) | Historical | Predecessor state and test migration, superseded by ADR-0004 |
| [ADR-0003](ADR-0003-paper-project-membership.md) | Historical | Predecessor paper associations and conditional compensation, superseded by ADR-0004 |
| [ADR-0004](ADR-0004-roundtable-workstation.md) | Accepted | One Go/Wails host for Sci-Station and Roundtable |
| [ADR-0005](ADR-0005-project-records-and-conversion-recovery.md) | Accepted | Research project authority, record versions and local conversion receipts |
| [ADR-0006](ADR-0006-frontend-build-layer.md) | Accepted | Zero-build native ES modules with opt-in JSDoc type checking |

Use the following structure: **Status; Context; Decision; Alternatives; Consequences; Validation; References**. Accepted records remain as history; supersede them with a new linked ADR instead of rewriting the original decision. Rejected and superseded records remain indexed. Reference implementation paths and test names so the decision can be audited.
