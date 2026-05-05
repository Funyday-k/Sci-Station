# Sci-Station Tutorial

This tutorial walks through Sci-Station as a product: a local-first research workstation for macOS. It is intended for first-time testers running the app from source.

> Prefer Chinese? Read [TUTORIAL.zh-CN.md](TUTORIAL.zh-CN.md). For the product overview, see [README.md](README.md) or [README.zh-CN.md](README.zh-CN.md).

## 1. Prepare The Environment

You need:

- macOS 14 or later
- Xcode 15 or later
- An empty folder for your Research Root, for example `~/Documents/SciStationTrial`

The Research Root is where Sci-Station stores papers, Markdown notes, project files, tasks, settings, and agent logs. Do not use the source repository itself as the Research Root, and do not share a Research Root that contains private papers or unpublished data without reviewing it first.

## 2. Run The App

Open the Xcode project:

```bash
open Sci-Station.xcodeproj
```

In Xcode:

1. Select the `Sci-Station` scheme.
2. Select `My Mac` as the run destination.
3. Press `Command + R`.

To validate the core file-system and metadata logic without launching the app, run:

```bash
swift run SciStationCoreTestRunner
```

## 3. Create A Research Root

1. On the first screen, click `Create Workspace`.
2. Choose an empty folder.
3. Sci-Station creates the default workspace structure, including `library/`, `projects/`, `wiki/`, `tasks/`, `settings/`, and `.sci-station/`.
4. Restart the app once to confirm that macOS security-scoped bookmark restore opens the same Research Root automatically.

If the Research Root is moved or deleted, Sci-Station clears the stale bookmark and returns to the create/open workspace screen.

## 4. Import The First Paper

Open Library and start with one of these paths:

- Click `Import PDF`.
- Drag a PDF into Library.
- Click `Add by Identifier` and paste a DOI, arXiv ID, PDF URL, or normal web link.

A successful PDF import creates a paper folder under `library/papers/` with files such as:

```text
paper.pdf
paper.md
meta.yaml
annotations.md
figures/
```

Use the Inspector to review or edit title, authors, year, tags, reading status, priority, rating, DOI, arXiv ID, abstract, and BibTeX. Notes written in the PDF Reader are saved to `annotations.md`.

## 5. Turn The Library Into A Project

1. Click `New Project` from the sidebar or app commands.
2. Enter a name, description, icon, and color.
3. Open Project Overview.
4. Use the project brief as a living proposal.
5. Add or mark core papers so the project overview has an explicit reading spine.

Project Overview is meant to be the working surface for the research idea. It summarizes paper counts, core papers, project documents, and unfinished tasks, while linking into data, code, figures, outputs, wiki pages, and shared context.

## 6. Write In The Wiki

Open Wiki or a project document and try:

- `Source` mode for Markdown editing.
- `Preview` mode for rendered reading.
- `Split` mode for writing while previewing.
- `Cmd+S` to save.
- Snippets such as `;eq`, `;fig`, `;todo`, and `;paper`.
- YAML frontmatter and `[[wikilink]]` references.

The Markdown preview supports GFM tables, code blocks, images, and KaTeX formulas.

## 7. Use Materials For Real Work Files

Materials is the bridge between the research product and your working files. It scans user-facing paths such as:

```text
data/
code/
figures/
outputs/
scripts/
prompts/
shared_research.md
```

Markdown, Python, text, images, and PDFs can be previewed directly. Other files can be opened in Finder, the default app, VS Code, or VSCodium.

For Python files, Sci-Station can prepare a VS Code task and remember the selected Python environment. You can use system Python, a workspace `.venv`, or a manually selected virtual environment.

## 8. Read PDFs In Context

Open a paper from Library and use the built-in PDF Reader to:

- Search with `Cmd+F`.
- Move through matches with `Cmd+G` and `Shift+Cmd+G`.
- Zoom and navigate through pages.
- Edit paper notes in the Notes panel.
- Create a task linked to the current paper.
- Copy or export BibTeX from Citations.
- Open DOI, arXiv, INSPIRE, URL, or PDF URL links.

This keeps reading actions close to the metadata, notes, tasks, and citation surface.

## 9. Manage Tasks And Calendar Items

Sci-Station stores local todos in the Research Root. Calendar and Apple Reminders integration is optional:

- If you allow macOS permissions, the dashboard can show Calendar/Reminders titles and publish workspace todos to Apple Reminders.
- If you deny permissions, local todos still work.

Published todos write mapping fields such as `external_source`, `external_identifier`, `external_updated_at`, `completed_at`, and `due_time` to `tasks/todos.yaml`.

## 10. Configure Optional AI Features

AI is not required for the core app. When you want to test it, open `Settings -> AI Lab`:

1. Choose an OpenAI-compatible provider.
2. Enter Base URL, Model, Temperature, and Max Tokens.
3. Enter your API key in the secure field.
4. Click `Save Settings`.
5. Use `Test Connection` before running workflows.

Security boundaries:

- API keys are saved to macOS Keychain.
- Workspace settings do not store API keys in plain text.
- `.sci-ai/sci-station/` stores only versionable product presets and templates.
- `.sci-ai/workspace.local/`, `.claude/`, `.mcp.json`, and `.env*` are local-only and should not be committed or shared.
- Write actions from AI/agent workflows remain behind the permission layer.

MinerU PDF-to-Markdown also requires the tester's own API token. Without it, Sci-Station falls back to local PDFKit extraction.

## 11. Share Or Review A Trial Build Safely

Before sharing a checkout or Research Root, run:

```bash
git status --short
swift run SciStationCoreTestRunner
xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build
git grep -n -I -i -E '(api[_ -]?key|secret|token|password|bearer|private[_ -]?key|client[_ -]?secret|refresh[_ -]?token|oauth)' -- . ':!DOC/**'
```

Confirm that the shared package does not include real credentials, local research data, `.env*`, `.mcp.json`, `.claude/`, `.sci-ai/workspace.local/`, DerivedData, archives, `.app`, `.zip`, `.dSYM`, or `.xcresult` files.

## 12. Known Trial Boundaries

- Sci-Station is currently a local-first trial/development build, not a notarized public release.
- Network features depend on user configuration, user network access, and third-party services.
- High-quality PDF-to-Markdown conversion depends on MinerU.
- Apple Reminders support is currently focused on publishing and local mapping; full bidirectional sync is future work.
- MCP server execution is still guarded by templates, status display, and the permission model.
