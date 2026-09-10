# RFC-0001: Knowledge Architecture V1

- Status: Proposed
- Requirement: [KNOW-001](../BACKLOG.md#know-001--knowledge-architecture-v1).
- Decision PR: Not yet reviewed. This is a design proposal, not an implementation claim.

## Problem and acceptance criteria

Researchers need claims and relationships that can be traced to paper, PDF or Markdown evidence, reused across projects and projected into a graph. Each accepted record should retain its sources, stable identity and revision history. Existing paper/Wiki/project content must remain readable and recoverable.

## Proposed design and boundaries

Introduce a KnowledgeAtom model with identity, kind, content, source locators, provenance and timestamps; model relationships separately. A KnowledgeRepository owns serialization, validation and atomic persistence. KnowledgeStore owns selection and observed domain state. Extraction produces reviewable drafts with evidence and an explicit approval step before writeback. Graph indexing derives projections from accepted records and can rebuild them without destroying source records.

AppViewModel should call narrow use cases rather than accumulate another set of atom/relation/extraction/merge arrays. Reuse existing permission, artifact and provenance mechanisms where their contracts fit.

## Alternatives and tradeoffs

Embedding all new state into AppViewModel is quick but deepens coupling. Treating SQLite graph nodes as the only record format simplifies queries but complicates portable evidence and recovery. Extending Markdown frontmatter may preserve readable files but needs a clear identity and concurrent-edit policy. Evaluate these choices before selecting the persistent format.

## Compatibility, migration and recovery

Do not assign a new schema version until the record format is agreed. Establish how existing knowledge artifacts map to atoms, preserve unknown fields and source locators, prevent silent overwrite, and define backup/rollback and graph rebuild behavior. No destructive automatic migration is authorized by this proposal.

## Validation and rollout

Test stable identity, round-trip serialization, unsupported versions, stale/absent evidence, duplicate extraction, approval rejection, workspace switching, concurrent edits, interrupted writes, relation deletion and graph rebuild. Start with repository/model tests and an opt-in fixture-backed workflow before user-facing rollout. Implementation Issues should separately cover models, persistence, extraction review and graph projection.

## Open questions

- Which atom kinds and evidence locators are required for the first usable workflow?
- Which readable storage format best supports external edits and stable identity?
- How are conflicting edits and duplicate claims reviewed and merged?
- Which existing Knowledge artifact behavior remains unchanged, and which requires migration?
- What minimum AppViewModel/use-case extraction is required before UI integration?
