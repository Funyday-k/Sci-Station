# Versioning policy

App releases and persisted/protocol formats serve different compatibility contracts. Equal-looking version strings do not imply that components must advance together.

| Component | Authoritative source / contract | Change rule |
| --- | --- | --- |
| App marketing version | Root [VERSION](../VERSION); Xcode `MARKETING_VERSION` and README version headers mirror it | `MAJOR.MINOR.PATCH`; release tag is exactly `v` plus this value |
| App build number | Xcode `CURRENT_PROJECT_VERSION`, or the validated release build override | Positive integer, greater than the previous stable-format release tag's build number |
| Python AgentRuntime package | `AgentRuntime/pyproject.toml`; `sci_station_agent.__version__` mirrors it | Independent semantic version; CI checks these two agree without forcing agreement with the app |
| Sidecar transport | `AgentInitializeParams` in `SidecarProcessSupervisor.swift` and Python server protocol/schema constants | Independent compatibility contract; both peers must agree and handshake tests must cover rejection |
| Workspace preferences | `WorkspacePreferences.currentSchemaVersion` (currently 5) | Independent integer; update migration/defaulting and old-input tests with a format change |
| Graph persisted schema | `graphSchemaVersion` in `GraphSchema.swift` (currently 2) | Independent integer; document rebuild/migration and preserve source files |
| Knowledge architecture | Existing knowledge records retain their own formats; the proposed KnowledgeAtom format is not yet assigned a version | Assign only after [RFC-0001](rfcs/RFC-0001-knowledge-architecture.md) is accepted; do not imply the proposal is implemented |
| Plugin / Skill / Prompt / workspace template | Each manifest or template's own version | Advance when that component changes; record changed behavior and compatibility, independent of app releases |

## Preparing a release

1. Update `VERSION`, both Xcode marketing-version settings, and Chinese/English README version headers. These are checked mirrors, not competing sources of truth.
2. Set an increasing Xcode build number and update `CHANGELOG.md` with the released changes, PR/Issue links where available, limitations and migration notes.
3. If the runtime package changes, update its two version fields together. Do not bulk-replace strings in fixtures, protocol schemas or plugin manifests.
4. Run `python3 Tools/scripts/check-version-consistency.py` and all required CI checks. For the tag, run `python3 Tools/scripts/check-version-consistency.py --tag vX.Y.Z`.
5. Merge the release preparation PR into `main`, then create a new immutable tag on that reviewed commit. A tag alone must not bypass tests or signing gates.

`0.x` releases are Developer Previews. Document breaking user workflows and data changes even before `1.0.0`; do not assume preview users can discard their Research Roots. Preserve unknown fields where supported, make backups/recovery explicit, reject incompatible input clearly, and test supported older data. The older `0.1.0` download is not retroactively signed or notarized by adding a release workflow.
