# ADR-0004: Knowledge Architecture V1

- Status: Draft for review; no accepted decision or implementation authorization.
- Requirement: [KNOW-001](../BACKLOG.md#know-001--knowledge-architecture-v1), https://github.com/Funyday-k/Sci-Station/issues/5
- RFC: [RFC-0001](../rfcs/RFC-0001-knowledge-architecture.md), still Proposed.
- Draft revised: 2026-10-19.
- Decision and implementation PRs: not yet recorded.

## Context

Existing paper notes, Wiki pages and graph artifacts remain the supported knowledge surfaces. A reusable claim needs stable identity, reviewable evidence and a revision boundary independent of its filename. Successful citation parsing does not establish scientific support, as the bounded validation in [READ-001](../BACKLOG.md#read-001--source-backed-paper-reading-and-reviewed-writeback) demonstrates.

This draft resolves design choices for review. It does not introduce production types, create directories, assign a schema version, or change existing graph and note contracts. Acceptance of the RFC and a recorded accepted ADR must precede implementation.

## Proposed decision

### Record ownership and identity

Use one Markdown record with YAML frontmatter per atom, with separate YAML relation records. Proposed locations are `knowledge/atoms/`, `knowledge/relations/` and `knowledge/archive/` under the Research Root. These locations are not yet supported workspace paths. Any implementation must explicitly integrate them with workspace module gating and the permission model; their mention here grants no read or write permission.

The atom's UUID is its identity. Its title, citation key, filename and user-supplied aliases are lookup aids, never identity. Renaming a file preserves its UUID. Duplicate UUIDs in different files are an explicit load conflict: neither file wins based on enumeration order. Titles and aliases may be ambiguous; resolution returns candidates and requires a selection instead of silently selecting one.

Initial atoms represent a single claim with explicit conditions and distinguish a source author's statement from a reader/model inference. Methods, results and other taxonomies are deferred. Proposed semantic fields are:

| Field | Contract |
| --- | --- |
| `id` | UUID, immutable across revisions and renames |
| `kind` | `claim` in the initial format; unknown kinds cannot be overwritten by an older writer |
| `title`, `aliases` | Display title and optional user-maintained aliases; collisions are allowed and reported |
| Markdown body | Claim text and explicit conditions; content is reviewed as part of the record |
| `claim_origin` | Source statement or inference, visibly distinguished during review |
| `sources` | At least one source reference for acceptance; locators and hashes defined below |
| `provenance` | Manual/model extraction origin and available model/tool identifiers; no credentials or hidden reasoning |
| `created_at`, `updated_at` | UTC timestamps; not concurrency tokens |
| `review` | Reviewer action, timestamp and digest of the exact reviewed payload |
| schema discriminator | Required once a format is accepted; no version value is assigned by this draft |

Unknown YAML fields and nested structures must survive supported read/edit/write cycles. Unsupported schema versions, malformed YAML and missing required fields are explicit errors; readers must never turn them into empty records and overwrite them. A missing atoms directory means no atoms, while an unreadable directory means an error.

### Evidence and source health

A source reference records the paper identity when available, the source representation, Research Root-relative path, SHA-256 digest of the exact source bytes, a typed locator and an optional quoted passage. Paths must pass the existing containment and symlink checks at read/write boundaries. An arbitrary URL is not fetched automatically and does not qualify as verified local evidence.

The initial locator set is deliberately small:

- PDF page: a one-based physical page index in the hashed PDF, with an optional displayed page label and quote. A PDF page index is not a text offset.
- UTF-8 Markdown line range: inclusive, one-based start/end lines in the hashed representation. CRLF is one line break; a final line terminator does not create an additional addressable line. An optional heading provides context but is not the locator identity.

Equation labels, section-only locators, character offsets and external URL anchors are deferred until their representation and recovery rules are specified and tested. A quoted equation or section can be described within a supported page/line locator without claiming independent equation resolution.

Source health is separate from approval: `fresh`, `changed`, `missing`, `unreadable` or `invalidLocator`. New acceptance and re-review require every attached supporting reference to be locally readable, fresh and locator-valid at review time and again before persistence. Unavailable references must be resolved or removed from the proposed supporting set before acceptance; historical revisions retain their original references. A previously accepted record can later become stale or unavailable and remains visibly historical support rather than fresh evidence. A source hash change never silently retargets evidence. It preserves the historical review and flags current support for re-review. Scientific validity remains a human judgment even when all hashes match.

### Drafts, review and revisions

Manual selection and machine extraction both produce drafts. Acceptance requires explicit review of claim wording, conditions, origin, sources and any proposed relations. AI write actions still pass through the existing approval system. A rejected draft does not write an accepted atom; any rejection audit must follow the existing privacy and retention contract.

The review digest covers the complete payload presented for acceptance: identity, kind, title, aliases, claim body and conditions, provenance and source references, including their hashes and locators. It excludes the review envelope itself and derived indexes. Compute SHA-256 over an RFC 8785 canonical JSON object with two members: `frontmatter` (the full semantic mapping except the top-level `review` envelope) and `body` (the exact decoded UTF-8 body, including its line endings). YAML mappings must have unique string keys; the accepted value subset is JSON-compatible strings, booleans, null, finite numbers, arrays and mappings. Dates are quoted strings. Numeric YAML scalars are supported only as integers in the inclusive range -(2^53 - 1) through 2^53 - 1, parsed and range-checked as integers before any floating-point conversion. Decimal/exponent scalars and larger integers are rejected; decimal scientific values can be represented as strings. This deliberately restricted subset prevents lossy YAML-to-JCS conversion. Custom tags, aliases, duplicate keys and values outside that subset are explicit unsupported-input errors, never silently coerced or dropped. Unknown supported fields participate in the digest and remain preserved. A hash of the body alone is insufficient. The codec implementation must include canonicalization test vectors for key ordering, Unicode, numbers, body line endings and unknown nested fields before enabling writes.

Finalize schema metadata, identity, timestamps, provenance and all other writer-populated values before presenting the payload for review. Saving must persist that exact approved payload, then add its review envelope without changing digest-covered fields. Reparse prepared bytes and verify the digest before replacement; any preparation change requires renewed review. Source bytes changing before persistence also invalidate the pending acceptance.

Editing a reviewed payload makes the review inapplicable to the new revision. The UI must distinguish a draft, a currently reviewed revision, an edited revision needing review and reviewed content whose sources have changed. Source health must not overwrite the historical reviewer record. Metadata-only filesystem renames do not invalidate a record whose payload is unchanged.

### Save conflicts and recovery

Loading returns the record and a token computed from the exact on-disk bytes. Saving requires that loaded token, re-reads the file and computes the current byte digest; it must not trust a hash stored inside editable frontmatter. Creation requires absence rather than an overwrite. Any mismatch reports a conflict and preserves the user's proposed revision for resolution. Reloading and reviewing the actual merged content is required before saving a merge.

A Swift actor serializes only cooperating calls in the application. Atomic file replacement prevents partially written files but is not cross-process compare-and-swap. External programs may modify a file after the pre-save check. V1 must explicitly disclose this limitation, retain recovery copies of the observed pre-save bytes and proposed bytes, and detect post-write mismatches when possible. It cannot claim to prevent every uncooperative writer from losing an intermediate edit. A strict cross-process no-lost-update guarantee would require a separately reviewed coordinated write protocol.

Recovery copies must be durable before replacing the primary record. Store them under the proposed `.sci-station/knowledge/recovery/<operation-uuid>/` location, with the intended target, expected byte digest and prepared old/new bytes. The pending operation is a recovery aid, not a primary record or permission grant. Failed preparation leaves the original untouched; failed replacement exposes an actionable error and retains recovery copies. Interrupted saves are reconciled explicitly on reopening, with no automatic overwrite or deletion. A prepared recovery file alone does not authorize replay of an approval. Multi-file operations are not described as atomic.

V1 retains recovery copies without automatic expiration. Cleanup is an explicit user operation that previews affected revisions and disk usage, refuses unresolved operations, and requires normal write approval. Insufficient disk space fails before primary replacement. This favors recoverability over bounded disk use; later automatic retention would need a reviewed compatibility and recovery policy.

### Accepted revision history

Accepted history is distinct from disposable recovery files. Proposed immutable records live under `knowledge/history/<record-uuid>/<revision-uuid>.yaml`, for both atoms and relations. Each stores its revision UUID, parent revision UUID (absent for first acceptance), record kind/UUID, exact accepted primary bytes encoded losslessly, their byte digest, the reviewed payload digest and reviewer envelope. Finalize the revision and parent IDs as digest-covered primary metadata before review. Parent links are by revision UUID, independent of titles, paths or archive locations.

Save prepares and durably stores the immutable accepted revision before replacing the primary record. A failed primary replacement leaves the revision available to recovery, but does not make it current or graph-visible. The current primary record names its accepted revision UUID; a mismatched history entry is an explicit integrity error. Reopening reconciles unresolved operations without silently advancing that pointer. Concurrent divergent proposals are preserved as branches for explicit resolution rather than rewriting a revision chain.

Recovery cleanup never deletes accepted history. V1 provides no permanent history deletion; archive and rename preserve access by record UUID. Historical records are read-only provenance, not a source of current graph nodes or fresh evidence. Tests must establish history durability when preparation succeeds but primary replacement fails, and after recovery cleanup, archive, rename and restore.

### Relations, duplicates and resolution

Each relation has a UUID, source/target atom UUIDs, the exact reviewed payload digest of each endpoint, a reviewed relation type, provenance and a review digest. Its digest is SHA-256 over RFC 8785 canonical JSON of the complete YAML mapping except the top-level `review` envelope, using the same scalar restrictions as atoms. Both endpoint digests and unknown supported fields participate. If either current endpoint payload digest changes, the relation becomes review-inapplicable until explicitly reviewed against the new endpoint pair; accepting a revised atom does not automatically reactivate an old semantic relation. Start with a general explicit `related` link and reviewed `supports` links. Contradiction, equivalence and derivation types are deferred; graph proximity cannot establish them. Relations do not imply acceptance of either endpoint and cannot upgrade stale evidence to fresh evidence.

Repeat extraction can surface duplicate candidates using normalized text and source identity, but never merges automatically. Users may discard a duplicate draft or retain a separate claim with different conditions. V1 performs no destructive atom merge and stores no implicit redirect chain. A future merge workflow must define redirect/cycle handling and recoverable relation rewrites in a separate accepted change. Alias collisions remain candidate lists throughout.

### Archive and graph projection

Archiving changes the source record's location while retaining identity and history. Incident relations remain recoverable records and become inactive when either endpoint is archived or missing; do not attempt an implicit multi-file cascading delete. Restore revalidates identity conflicts and endpoint availability before reactivating projection. Permanent deletion is outside this initial workflow.

Graph/index data is rebuildable derived state. Project only active records whose review matches their payload, and active reviewed relations between those records. Source-health warnings travel with projected atoms and query responses; stale support is never represented as fresh evidence. Unreviewed or edited records remain available in review UI but not as accepted knowledge. A corrupt record is surfaced as an indexing error; a partially successful scan must not replace a known complete graph and report success.

Agent query surfaces return record identity, review revision, source references, source health and unresolved ambiguities. They use the existing authorization boundary, do not silently repair records, and do not present model-inferred relations as reviewed facts. Graph rebuild does not rewrite atoms, sources or relations.

### Compatibility and rollout

Existing paper/Wiki/project notes retain their formats and behavior. There is no automatic conversion, schema bump or new directory creation on workspace open. Explicit import into an atom copies selected content into a reviewable draft, records its origin and preserves the original. It does not interpret every old Wiki page as an accepted claim.

After acceptance, separately scoped implementation increments should cover the codec/repository and recovery behavior, review use cases and state ownership, then graph and authorized Agent queries. Extend existing domain stores and approval mechanisms where appropriate; AppViewModel should coordinate them. No user-facing rollout precedes repository compatibility and failure-path validation.

## Alternatives

SQLite-only primary records simplify coordinated transactions but reduce portable editing; derived indexes remain suitable for SQLite. Keeping atoms solely inside graph payloads couples evidence to disposable projection state. Automatic acceptance, automatic deduplication and last-write-wins saves do not meet the review and conflict requirements. A broad taxonomy and semantic relation inference would expand beyond the validated initial workflow.

## Consequences

Readable records provide portable evidence and recovery, but require explicit validation, conflict handling and ambiguous-identity reporting. Review and source-health state remain independently visible. V1 intentionally provides bounded application-level conflict detection rather than a cross-process transaction guarantee. Recovery copies consume disk space until explicit cleanup. The canonicalization subset deliberately rejects unsupported YAML constructs rather than silently weakening review integrity.

## Validation and acceptance gate

Before this draft becomes an accepted decision, review the locator subset, relation subset, lack of destructive merge, external-writer limitation, canonical digest encoding and recovery retention policy. These are proposed choices awaiting maintainer review, not accepted contracts. Record actual approval and decision-PR references; do not infer acceptance from implementation work.

Required implementation tests include:

- UUID stability across rename; duplicate UUIDs and ambiguous aliases; repeated extraction without automatic merge.
- Old supported input, unknown nested YAML fields, unsupported versions, malformed records and missing versus unreadable directories.
- Page/line boundary validation, missing and changed sources, representation changes and path/symlink containment.
- Review digests for changes to wording, conditions, title, provenance and locators; reject/no-write and changed-payload re-review.
- Save conflicts computed from actual bytes despite forged stored hashes; create collisions; concurrent app saves; injected external edits before and after the pre-save check.
- Recovery-copy failure, replacement failure, interruption/reopen and retention of user proposals; no claim of multi-file atomicity.
- Archive/restore with incident relations, missing endpoints, duplicate IDs on restore and rebuild without source changes.
- Workspace-switch cancellation; partial/corrupt graph scans; authorization and stale-evidence signaling in Agent queries.

These are required future tests, not results from executed validation. The existing Knowledge repository test migration under TEST-001 does not validate this proposed format.

Draft validation on 2026-10-19: `python3 Tools/scripts/check-docs-hygiene.py`, `python3 Tools/scripts/check-version-consistency.py`, `python3 -m unittest discover -s Tools/tests -v` (15 tests), `Tools/scripts/check-repository-hygiene.sh` and `git diff --check` passed. An independent textual review identified five specification gaps; the revised digest, endpoint-revision, history and evidence-admission contracts resolve them. This review is not maintainer acceptance. No new-format persistence, application build, UI exercise or runtime test was performed for this documentation-only draft.

## References

- [RFC-0001](../rfcs/RFC-0001-knowledge-architecture.md)
- [KNOW-001](../BACKLOG.md#know-001--knowledge-architecture-v1)
- [Versioning policy](../VERSIONING.md)
- [ADR-0002](ADR-0002-application-state-and-testing.md)
- [ADR-0003](ADR-0003-paper-project-membership.md)
