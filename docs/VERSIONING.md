# Versioning policy

App releases and persisted/protocol formats serve different compatibility contracts. Equal-looking version strings do not imply that components must advance together.

| Component | Authoritative source / contract | Change rule |
| --- | --- | --- |
| App marketing version | Root [VERSION](../VERSION). Xcode `MARKETING_VERSION` and README version headers mirror it. The workstation candidate build reads it directly. | `MAJOR.MINOR.PATCH`. The release tag is exactly `v` plus this value. |
| App build number | Xcode `CURRENT_PROJECT_VERSION` supplies both builds during the host transition. Release builds may use a validated override. | Positive integer, greater than the previous stable-format release tag's build number |
| Python AgentRuntime package | `AgentRuntime/pyproject.toml`; `sci_station_agent.__version__` mirrors it | Independent semantic version; CI checks these two agree without forcing agreement with the app |
| Sidecar transport | `AgentInitializeParams` in `SidecarProcessSupervisor.swift` and Python server protocol/schema constants | Independent compatibility contract; both peers must agree and handshake tests must cover rejection |
| Workspace preferences | `WorkspacePreferences.currentSchemaVersion` (currently 5) | Independent integer; update migration/defaulting and old-input tests with a format change |
| Workstation tasks | The workspace research store's `tasks.json` has version 1. Project-owned tasks stay in their original project record. | Preserve task IDs, original reminder identity, and unknown fields. Back up the research store as a whole. Restore a known-good copy if a malformed file or unsupported version blocks opening the store. |
| Graph persisted schema | `graphSchemaVersion` in `GraphSchema.swift` (currently 2) | Independent integer; document rebuild/migration and preserve source files |
| Knowledge architecture | Existing knowledge records retain their own formats; the proposed KnowledgeAtom format is not yet assigned a version | Assign only after [RFC-0001](rfcs/RFC-0001-knowledge-architecture.md) is accepted; do not imply the proposal is implemented |
| Plugin / Skill / Prompt / workspace template | Each manifest or template's own version | Advance when that component changes; record changed behavior and compatibility, independent of app releases |

## Roundtable workstation reviewed writes

A project record can contain a `reviews` object keyed by the operation ID. A version 1 entry stores the destination and its revision, the proposed text, published meeting output, PDF locators and the decision. Older project records open with an empty queue. An unknown review version remains readable for inspection and cannot be accepted or rejected by this version. The application records the accepted result ID and the resulting note or task in the same atomic replacement. A retry of a completed decision returns that receipt, including when a researcher subsequently changes the result.

Use a separate destination and a verified copy of the full research root and meeting store before moving between workstation versions. To roll back, reopen the last known-good copy with the version that created it. This preserves the new root's review history, historical passage locations and decision receipts for reopening with its matching version. An older workstation must not edit a root containing review records it cannot preserve.

## Preparing a release

1. Update `VERSION`, both Xcode marketing-version settings, and Chinese/English README version headers. These are checked mirrors, not competing sources of truth.
2. Set an increasing Xcode build number and update `CHANGELOG.md` with the released changes, PR/Issue links where available, limitations and migration notes.
3. If the runtime package changes, update its two version fields together. Do not bulk-replace strings in fixtures, protocol schemas or plugin manifests.
4. Run `python3 Tools/scripts/check-version-consistency.py` and all required CI checks. For the tag, run `python3 Tools/scripts/check-version-consistency.py --tag vX.Y.Z`.
5. Merge the release preparation PR into `main`, then create a new immutable tag on that reviewed commit. A tag alone must not bypass tests or signing gates.

`0.x` releases are Developer Previews. Document breaking user workflows and data changes even before `1.0.0`; do not assume preview users can discard their Research Roots. Preserve unknown fields where supported, make backups/recovery explicit, reject incompatible input clearly, and test supported older data. The older `0.1.0` download is not retroactively signed or notarized by adding a release workflow.

## Workstation discovery records

The workstation stores search history and feedback in `discovery.json` (whole library) and `discovery.<project-id>.json` (one project) alongside settings in the active workspace. Schema 1 stores dated run snapshots, their original candidate metadata and ranking, and feedback keyed by bibliographic work. Archiving removes a run from the history view and preserves its snapshot on disk. The app loads the prototype's unversioned latest query and feedback in place on an explicitly opened workstation copy. It does not scan old Swift Research Roots or another workspace for discovery records.

A successful mutation atomically replaces the scoped file. Reads reject malformed JSON and unsupported schema versions and leave the file intact. Unrecognized top-level fields are preserved. For recovery, close the app and restore the affected file from the last verified copy of that workspace. Library and task records are stored separately. An interrupted candidate selection can be retried with its original scope, run ID and candidate key.
