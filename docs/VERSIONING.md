# Versioning policy

Release identifiers, workspace formats and extension contracts advance independently.

| Component | Authoritative source / contract | Change rule |
| --- | --- | --- |
| App marketing version | Root [VERSION](../VERSION) supplies the macOS bundle version. The Chinese and English README headers mirror it. | Numeric `MAJOR.MINOR.PATCH`. A release tag is exactly `v` plus this value. |
| App build number | Root [BUILD_NUMBER](../BUILD_NUMBER) supplies the bundle build number. | Positive integer, strictly increasing across tagged releases. A local or CI build can use `SCI_STATION_BUILD_NUMBER` for an isolated install fixture. Published builds use the committed value. |
| Workspace format | `.sci-station-desktop` version 1 identifies an explicitly opened desktop research root. | The host rejects unmarked nonempty directories and unsupported markers before opening records. Commit format changes with supported-input and independent recovery tests. |
| Navigation | `workspace-navigation.json` version 1 records the latest route and selectors. | A missing, unsupported or corrupt record opens Home or the nearest valid route. Preserve research data outside navigation state. |
| Research tasks | `tasks.json` version 1 stores unassigned tasks and optional `tagDefinitions` and `tagRevision` fields for the workspace task tag catalog. Project-owned tasks stay in their original project record. | Preserve task IDs, Apple Reminders links, string tag assignments, and unknown fields. Restore a verified copy if malformed or unsupported input prevents loading. |
| Apple Reminders | Optional `appleReminderId` and `reminderRevision` fields link a task. Workspace `interface.json` version 1 stores optional `syncNewAppleReminders`. | Existing tasks open without a link and auto-publishing starts disabled. Preserve original task and eligible revision identity. |
| Knowledge architecture | Existing notes and graph sources keep their formats. KnowledgeAtom is [proposed](rfcs/RFC-0001-knowledge-architecture.md). | A schema version requires the accepted decision and compatibility tests. |
| Plugins, research skills and templates | Use each component's declared format. | Advance only the affected component and document supported versions. |

## AI Lab session metadata and unsent drafts

A single-seat session may include optional `lab_thread` presentation metadata with a title, archive timestamp and compare-and-swap revision. Missing metadata means the conversation is active and uses its original display title. Renaming preserves its topic, session ID, turns and evidence. Archiving preserves the scheduler and report state. Restore an archived conversation before starting a new round.

Rounds can include optional version 1 `lab_run` metadata. It records a SHA-256 fingerprint of the model guidance assembled for the round and the prior round number when a user retries a failed or cancelled attempt. An older round can still show its recorded events, model and source references. Its missing settings and fingerprints remain unknown. A retry appends a separate round with current authorized settings and the saved input. The redacted diagnostics include retry round numbers and event kinds. The local history keeps the detailed records.

Unsent input lives in version 1 files under the workspace meeting store's `lab-drafts/` directory. Each file is scoped to a project or the explicit global scope, and to a session or a new conversation. It stores only editor text and its revision. Credential-like inputs are rejected. The meeting engine does not load drafts into prompts or diagnostics. Malformed records, unsupported versions and records with unknown fields are retained and cannot be overwritten by an editor save. To recover drafts, close Sci-Station and restore them with the matching meeting store and research root from a verified copy.

## Workstation prompts and tool budgets

The research root's `settings.json` may contain a version 1 `prompt_library` with its own revision and an optional `tool_budget`. Older settings open with an empty prompt library and the standard budget. Saving a reviewed proposal atomically updates the library. Each template keeps a stable ID and adds a revision and SHA-256 fingerprint for edited content. Each new discussion round stores the prompt selected for that round and its effective budget. The active agenda draft stores its selected prompt. A rejected preview is transient, and a read decision applies to one running session request. Committed discussion history records the decision without granting permission to read again.

Restore the built-in prompt for a workflow from Settings. Existing round records retain the instructions and budgets used at the time. Keep `settings.json` and the meeting store together when making a workspace backup. A copy created before this update is the rollback source for older app versions. The Swift workspace profile is preserved separately under the workstation migration policy.

See [workspaces and recovery](workspaces.md) for existing roots, the prototype backup manifest, collections, reading position, and direct-provider profiles.

## Paper sources and reviewed writes

A shared paper may carry a version 1 `markdown_source` with its body revision, byte count, SHA-256, origin and blob ID. The original UTF-8 file lives under `library/markdown/`. PDFKit and fingerprint-bound MinerU conversions also record the source PDF hash. Older records without this field have no adopted Markdown body. An unknown body version cannot be read or replaced. The service stages a new blob before the revision-checked record update. Failed or stale updates preserve the published body. A new MinerU source may also have an optional `assets_sha256` for the checked image manifest in the matching Markdown blob's `.assets/` directory. The original Markdown SHA-256 and relative references stay intact. With the manifest, citation and image lookup fingerprints bind both the Markdown and its attachments. Existing records without a manifest keep their previous text fingerprint. Preserve the paper records, Markdown blobs and matching image directories when backing up or restoring a research root.

The AI Lab's optional local retrieval cache lives under `lab-retrieval/` in the active workstation research store. Each project file records the cache format version, ranking model, source fingerprints and deterministic term vectors. Queries, source text and provider credentials are absent from the cache. The service reads current authorized source text before reusing a vector, replaces mismatched or invalid cache formats on the next authorized hybrid request, and falls back to lexical search if it cannot save the cache. The cache is derived and can be rebuilt without changing research records.

A project record can contain a `reviews` object keyed by the operation ID. A version 1 entry stores the destination and its revision, the proposed text, published meeting output, PDF locators and the decision. Older project records open with an empty queue. An unknown review version remains readable for inspection and cannot be accepted or rejected by this version. The application records the accepted result ID and the resulting note or task in the same atomic replacement. A retry of a completed decision returns that receipt, including when a researcher subsequently changes the result.

Use a separate destination and a verified copy of the full research root and meeting store before moving between workstation versions. To roll back, reopen the last known-good copy with the version that created it. This preserves the new root's review history, historical passage locations and decision receipts for reopening with its matching version. An older workstation must not edit a root containing review records it cannot preserve.

## Preparing a release

1. Update `VERSION`, the Chinese and English README version headers and the `CHANGELOG.md` release entry together. Commit a positive `BUILD_NUMBER` greater than the latest lower release's build number.
2. Run `python3 Tools/scripts/check-version-consistency.py` and all required CI checks. For a prepared release, also run `python3 Tools/scripts/check-version-consistency.py --tag vX.Y.Z`.
3. Merge the release preparation PR through protected `main`. Create a new immutable tag on the reviewed commit. [Public Release](../.github/workflows/release.yml) validates the tag, version, build number, artifacts and installation before publication.

`0.x` releases are Developer Previews. Describe breaking workflows, storage changes, verification and ways to recover even before `1.0.0`. Preserve unknown data where the affected format supports it, and fail explicitly on incompatible input. The [changelog](../CHANGELOG.md) records the status of previously published downloads.

## Workstation discovery records

The workstation stores search history and feedback in `discovery.json` (whole library) and `discovery.<project-id>.json` (one project) alongside settings in the active workspace. Schema 1 stores dated run snapshots, their original candidate metadata and ranking, and feedback keyed by bibliographic work. Archiving removes a run from the history view and preserves its snapshot on disk. The app loads the prototype's unversioned latest query and feedback in place on an explicitly opened workstation copy. It does not scan old Swift Research Roots or another workspace for discovery records.

A successful mutation atomically replaces the scoped file. Reads reject malformed JSON and unsupported schema versions and leave the file intact. Unrecognized top-level fields are preserved. For recovery, close the app and restore the affected file from the last verified copy of that workspace. Library and task records are stored separately. An interrupted candidate selection can be retried with its original scope, run ID and candidate key.

Schema 1 also accepts optional per-scope recommendation defaults and an append-only record of feedback changes. A daily JSON or JSONL feed is opened explicitly from the discovery screen. The snapshot records the supplied filename and SHA-256 of the imported UTF-8 payload and keeps the ranked metadata for later offline review. It does not copy the entire file or follow its embedded links during discovery. Importing a daily-feed candidate into the library registers its metadata and source link for offline use. Recent library records and core-paper relationships can also be ranked offline. Online arXiv searches record each successful query and the query that returned the retained version of each candidate. The AI Lab link opens the current scope and asks the researcher to confirm an online search before submitting it.


The research root's version 1 `interface.json` can include an optional `shellLayout` object for panel mode and width, tree expansion, pinning and navigation order. The optional `panelPinned` flag keeps a deliberately pinned inspector or AI panel open across views and restarts. Older layouts retain their width and navigation preferences. A saved AI mode without a pin flag keeps that explicit choice pinned. Other older layouts use the contextual inspector. Language and layout writes preserve each other's fields and unknown settings. The shell keeps unsent messages in the active window’s session storage. Its root-specific browser origin remembers the last single-seat conversation ID for each project. The meeting service owns completed turns and their project binding.
