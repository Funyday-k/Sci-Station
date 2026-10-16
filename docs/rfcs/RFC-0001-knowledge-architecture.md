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

## Recommended first slice after workflow validation

The public-paper reading validation recorded in [READ-001](../BACKLOG.md#read-001--source-backed-paper-reading-and-reviewed-writeback) supports a smaller initial workflow: a user selects one statement from a paper note, reviews its evidence and conditions, and accepts it as a reusable claim. Automatic extraction must remain a draft. An accessible source path or successful citation-shape check is insufficient to accept scientific meaning.

Recommended decisions for RFC review:

| Question | Recommended boundary | Alternative and tradeoff |
| --- | --- | --- |
| Initial atom kind | A claim with explicit conditions and a distinction between the source author's statement and a reader/model inference | Adding method, result and research-question taxonomies immediately needs examples beyond the current workflow |
| Primary record | One readable Markdown record with frontmatter identity/provenance, stable UUID independent of filename, and explicit revision metadata | SQLite-only records simplify queries but weaken portable editing and recovery |
| Evidence | Paper identity plus source representation, path, source hash and section/equation/line locator; distinguish PDF pages from text/character pagination | A filename or generated line number alone cannot reliably survive conversion or edits |
| Acceptance | A reviewable draft; acceptance records the reviewed revision and reviewer action. Changed source hashes make support stale and require review | Automatic acceptance would misrepresent the observed model-quality limits |
| Relationships | Separate records by stable atom IDs; begin with explicit source/support links. Contradiction and equivalence remain reviewed judgments | Inferring semantic relations directly from graph proximity is unsupported |
| Compatibility | Existing paper, Wiki and project notes stay readable without conversion. Import into atoms is explicit and reversible | Automatic bulk migration can erase distinctions and has no accepted mapping yet |
| Deletion and rebuild | Archive the source record and explicitly handle incident relations; rebuild graph projections without deleting source files | Treating graph deletion as source deletion risks losing accepted knowledge |
| External edits | Compare the loaded revision/content hash before save and show a conflict instead of overwriting | Last-write-wins is simpler but unsafe for externally edited research notes |

These are concrete recommendations, not an accepted schema or shipped feature. This RFC remains **Proposed**. A decision PR must resolve field definitions, supported locator types and conflict behavior before a schema version or production migration is introduced. Initial implementation should cover model/repository round trips and source-staleness tests before extraction or graph UI.
