# Desktop research workspaces

On the first desktop launch, Sci-Station opens a shared data folder at `~/Library/Application Support/Sci-Station Workstation/Data`. Projects in that folder share one paper library under `research/library`. Existing installations reopen their remembered data folder. An explicit `-data-dir` takes precedence for the current launch.

Open **Settings → Data location** to see the current folder, paper library and default location. Choose an existing Sci-Station data folder to reopen its projects and papers, or select an empty folder to start with an empty library. **Use default location** opens the library at the default path. Switching folders leaves the previous files in place. Canceling the native chooser or encountering an error keeps the current selection. If a remembered folder is missing, reconnect its drive and select the original folder from the recovery window. A damaged recent-location record can be cleared there.

Each data folder has a separate loopback origin, meeting engine, settings store, research repository and process lock. The native Workspace menu also supports opening existing folders and creating named workspaces from templates. For browser-only use, start `sci-station serve -data-dir /path/to/workspace`. With no explicit directory the server requires a remembered desktop selection. The server prints its local address at startup.

## What the workstation stores

The file `.sci-station-desktop` identifies desktop workspace format 1. The workstation checks its exact version before opening records. Unmarked nonempty folders, Swift Research Roots, workspaces nested inside another workspace, and unsupported versions are rejected. Existing prototype data must be restored to an independent destination through the explicit recovery workflow. Starting the workstation does not create or select a copy of that data.

The user configuration directory contains a separate `Sci-Station Workstation` registry. It records the last selected workspace and reserves browser origins for roots. The registry files sit alongside the optional default `Data` folder and contain no research records. A headless invocation with an explicit data directory does not switch the desktop's remembered selection.

Project records in `research/records` keep a stable ID. The optional project fields `managedDirectory` and `directoryGrant` distinguish a workstation-owned folder from an external directory approved by the user. The latter stores the selected directory's device and inode. A changed or replaced external folder needs an explicit new approval in project settings. Revoking the grant leaves research records accessible and disables project-file access. Project settings can associate a new external directory with the same project ID. A project's optional `roundtableRules` array stores explicitly selected rule snapshots with its stable ID in the same research record. A new registration saves that record and its rules together. The older path-indexed `projects.json` remains a read-only archive. Its saved rules can be viewed in the Roundtable project import dialog. Select the desired current rules to apply them to a project. Legacy rows alone cannot authorize meetings, project files or CLI runs. Reapprove an unbound external folder in project settings.

Archiving removes a project from active views. Moving it to trash moves its managed directory from `research/workspaces/<id>` to `research/trash/<id>`, marks the record archived and trashed, and retains its notes and tasks. An external folder stays in its original location. Restore the project from the project trash to return it to active use. A recorded state and its managed directory are reconciled after an interrupted move. Shared paper bytes and project membership stay in the root's library throughout.

For a complete rollback, quit the workstation and restore the entire root from a verified copy, including its project records, `research/workspaces`, `research/trash`, library, and meeting data. Choose a new destination outside the source, existing workspaces and linked external project folders. Backup and restore accept the standard macOS temporary-directory aliases. Managed records and their directories must use regular filesystem entries. External folder contents have their own backup and restore policy.


## Back up and restore former workspaces

Start the current workstation in a new empty folder. Keep an existing Swift Research Root as a separate archive. Back up its original files and use the workstation's ordinary import controls for individual PDFs and other supported sources. Opening a legacy root does not convert its metadata, project associations, bookmarks or sidecar state.

For the earlier Go prototype, quit the prototype and pause work in its data directory. From the current repository root, choose new absolute destinations whose parent directories already exist. Substitute the actual former data directory if the prototype used a custom `-data-dir`.

```sh
prototype="$HOME/Library/Application Support/Sci-Station Desktop"
backup="/absolute/path/to/private-storage/prototype-backup"
restored="/absolute/path/to/private-storage/restored-workspace"
go run -tags nogui ./cmd/prototype-data backup -source "$prototype" -destination "$backup"
go run -tags nogui ./cmd/prototype-data verify -source "$backup"
go run -tags nogui ./cmd/prototype-data restore -source "$backup" -destination "$restored"
```

- Backup holds the prototype's process lock and copies files to `data/` with a version 1 `manifest.json` of file sizes and SHA-256 digests. It includes application records, PDFs, attachments, managed project files, installed plugins and settings. It excludes externally linked folders, credentials in Keychain, Magpie or CLI login state, and runtime lock files. Linked directories need their own backup. The tool refuses unsafe entries such as symlinks, hard links, mounts and external projects located inside the data directory.
- Verify checks the manifest, source bytes and supported paper, project, meeting, attachment and plugin references. Older notes and tasks may retain references to records deleted by the user. An unsupported manifest or registry format blocks automated restoration; the preserved bytes remain available for manual recovery.
- Restore verifies a staging copy before publishing to the new destination. It updates managed project paths, keeps unambiguous meeting/project associations, disables external grants, and clears local CLI path overrides. The original prototype root and backup remain available.
- Check the restored workspace independently. Open a paper, its annotation or linked citation, a project file and a meeting. Reauthorize each external directory you want to use. Reconfigure provider credentials for a new machine or data directory. If the check fails, preserve the original and backup, correct the cause, and retry with a new restoration destination.

## Records and recovery details

- **Navigation**. `workspace-navigation.json` version 1 records the last route and locator parameters. The desktop resumes through `/resume`; missing or inapplicable routes fall back to an available page. Damaged or unsupported navigation records stay on disk while the app opens Home. Restore this file only to recover navigation.
- **Library**. Under `research/library`, `organization.json` version 1 records collections, tag colors, and optional default import and display preferences. Older records use the default columns and unfiled imports. An import can choose a different destination. Renaming a collection keeps paper/PDF paths stable. The first import creates `refs/library.bib`; later imports append by citation key, preserving existing entries, comments and macros. Repair a damaged bibliography before retrying an import. Restore the full library together so records, PDFs, Markdown sources, and bibliography match.
- **Reading**. A shared paper's reading position includes the PDF fingerprint, page, zoom and scroll position, independently of its annotation revision. New text annotations and meeting excerpts can include PDFKit UTF-16 ranges and local OCR metadata. Older excerpts locate specific text only when the match is unique or the saved annotation resolves the ambiguity.
- **Tasks and reminders**. Shared tasks stay in the owning project record and can be edited through an associated project. The active workspace displays one row per task. Project-owned legacy records may be unversioned, and older tasks use their `projectId` / `paperId` as their initial associations. The old `doing` status is read as `inProgress`. Keeping the source task identity allows a later approval to update its existing Apple reminder. Local tasks continue to work when system permission is unavailable.
- **External sources**. An explicitly requested INSPIRE graph query sends public paper identifiers and stores a version 1 `inspire-graph-<identity-sha256>.json` cache in the research root. The graph can show up to six seeds and cache up to 25 references and 25 citing articles per seed. Offline views label cached results. Removing downloaded caches leaves the source papers, notes and meetings available.
- **Direct model profiles**. The application data directory's `provider-profiles.json` version 1 retains order, identity and non-sensitive settings. Restore that file in its original directory while the app is closed. Keychain lookup uses the original data directory, profile ID and endpoint. Unsupported or damaged profiles remain on disk and unavailable. Clear a saved key before changing its endpoint, then save the key intended for the new endpoint.
