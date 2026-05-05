# Sci-Station

**Sci-Station is a local-first research workstation for macOS.** It gives researchers a single place to collect papers, organize project knowledge, inspect PDFs, manage materials and tasks, and optionally run auditable AI-assisted research workflows while keeping the research root on the local file system.

> Prefer Chinese? Read [README.zh-CN.md](README.zh-CN.md). The hands-on tutorial is available in [English](TUTORIAL.md) and [Chinese](TUTORIAL.zh-CN.md).

## Product Idea

Most research projects begin as scattered PDFs, notes, code folders, todo lists, browser links, and half-written proposals. Sci-Station treats that mess as a product problem: it creates a visible Research Root, then turns the local folder into an organized workspace for literature review, project planning, evidence tracking, and day-to-day research work.

Sci-Station is built around three principles:

- **Local-first ownership**: papers, notes, project files, task lists, AI run logs, and generated artifacts live in a folder you choose.
- **Research-native structure**: the app starts from papers, projects, wiki pages, materials, figures, outputs, tasks, and citations instead of generic file management.
- **Auditable AI assistance**: optional LLM and agent workflows are designed around explicit settings, Keychain-backed secrets, permission review, evidence references, and reproducible run logs.

## What Makes It Different

- **One Research Root instead of another silo**: the workspace is a normal directory tree that can be inspected in Finder, opened in VS Code, backed up, or versioned selectively.
- **Paper library plus project context**: imported PDFs receive metadata, notes, citation data, wiki pages, and project links so a library can become a living research plan.
- **Markdown as the knowledge layer**: project briefs, paper notes, concepts, methods, gaps, and shared research context remain editable Markdown files.
- **Materials for real working files**: data, code, figures, scripts, prompts, and outputs can be previewed from the app and opened in VS Code or external tools.
- **PDF reading tied to research actions**: the built-in reader connects metadata, notes, tasks, citations, links, abstract, and files around the current paper.
- **Optional AI Lab with boundaries**: AI settings are user-provided, sensitive values are stored in Keychain, write actions stay behind the permission layer, and run artifacts are logged for review.

## Current Capabilities

Sci-Station currently includes:

- macOS SwiftUI app with a three-column workspace interface.
- Local Research Root creation, opening, repair, and security-scoped bookmark restore.
- Paper import from PDF drag/drop, file picker, DOI, arXiv, PDF URL, and general links.
- Paper metadata editing with `meta.yaml`, BibTeX support, tags, reading status, priority, rating, abstract, identifiers, and publication fields.
- Library table with search, sorting, configurable columns, multi-selection, batch metadata operations, citation copying, and PDF preview/opening.
- Project overview with project brief, core papers, project documents, research workflow links, and task summary.
- Markdown wiki editor with Source, Preview, Split modes, YAML frontmatter, `[[wikilink]]`, backlinks, snippets, GFM tables, code blocks, images, and KaTeX rendering.
- Materials browser for Markdown, Python, text, image, PDF, data, code, figure, output, script, and prompt files.
- VS Code / VSCodium bridge for opening workspace files and preparing Python run tasks.
- Local todo and calendar views with optional Apple Calendar / Reminders integration.
- PDF Reader with search, navigation, zoom, notes, linked tasks, citations, links, abstract, and file panel.
- AI Lab V1 with project-scoped conversations, plan review, permission dock, run/thread history, hook activity, MCP preset display, runtime selector foundation, and audit logs.
- SwiftPM core validation runner plus Python sidecar test suite for agent runtime contracts.

The app is still a trial/development build, not a notarized public release.

## Quick Start

Requirements:

- macOS 14 or later
- Xcode 15 or later

Run the app from source:

```bash
open Sci-Station.xcodeproj
```

In Xcode, choose the `Sci-Station` scheme, select `My Mac`, then press `Command + R`.

First launch:

1. Click `Create Workspace`.
2. Choose an empty folder as the Research Root. Do not choose the source repository itself.
3. Open Library and import a PDF, drag in a PDF, or use `Add by Identifier` for a DOI, arXiv ID, PDF URL, or web link.
4. Create a project, open its Project Overview, and start writing the project brief or core paper notes.
5. Use Materials for data, code, figures, scripts, prompts, and outputs.
6. Configure AI only when needed from `Settings -> AI Lab` with your own OpenAI-compatible provider.

For a fuller walkthrough, read [TUTORIAL.md](TUTORIAL.md).

## Workspace Layout

A Research Root is intentionally readable:

```text
ResearchRoot/
├── .sci-station/
│   ├── project_registry.yaml
│   └── agent/
├── library/
│   ├── papers/
│   │   └── {paper-id}/
│   │       ├── paper.pdf
│   │       ├── paper.md
│   │       ├── meta.yaml
│   │       ├── annotations.md
│   │       └── figures/
│   ├── refs/
│   ├── paper_index.yaml
│   └── project_paper_links.yaml
├── projects/
│   └── {project-id}/
│       ├── project.yaml
│       ├── shared_research.md
│       ├── wiki/
│       ├── tasks/
│       ├── data/
│       ├── code/
│       ├── figures/
│       └── outputs/
├── inbox/
├── raw/
├── wiki/
├── refs/
├── settings/
├── tasks/
├── imports/
├── data/
├── prompts/
├── scripts/
├── code/
├── figures/
├── outputs/
├── shared_research.md
└── researchflow.sqlite
```

Most files are plain Markdown, YAML, PDF, BibTeX, source code, images, or data files. This keeps the workspace useful outside the app.

## Privacy And Credentials

- The repository and build products must not include API keys, OAuth tokens, refresh tokens, client secrets, private keys, machine-local MCP configuration, or private research data.
- LLM API keys and MinerU API tokens are entered through secure fields and saved to macOS Keychain.
- `settings.yaml` stores non-sensitive provider settings such as base URL, model, temperature, and token limits.
- Papers, notes, tasks, agent logs, and generated files stay inside the user-selected Research Root.
- `.sci-ai/sci-station/` is for versionable product presets, schemas, skills, hooks, commands, MCP templates, and secret references only.
- `.sci-ai/workspace.local/`, `.claude/`, `.mcp.json`, `.env*`, packaged builds, and machine-local research data should remain outside Git.

## AI Configuration Layers

The repository separates product AI presets from machine-local bridge configuration:

- `.sci-ai/sci-station/`: versionable Sci-Station presets and templates.
- `.sci-ai/workspace.local/`: local checkout configuration that should not be committed.
- `.claude/` and `.mcp.json`: local bridge files for external agent tools that expect fixed paths.

AI features are optional. Core library, wiki, materials, PDF reading, and task workflows work without an LLM provider.

## Development Validation

Run the core validation runner:

```bash
swift run SciStationCoreTestRunner
```

Expected output:

```text
All SciStation core checks passed.
```

Build the macOS app:

```bash
xcodebuild -project Sci-Station.xcodeproj -scheme Sci-Station -destination 'platform=macOS' build
```

Run the Python sidecar tests when touching `AgentRuntime/`:

```bash
python -m pytest AgentRuntime/tests
```

## Manual Trial Checklist

- Create a fresh Research Root and restart the app to confirm bookmark restore.
- Import a PDF and inspect `paper.pdf`, `paper.md`, `meta.yaml`, and `annotations.md`.
- Add a DOI, arXiv ID, PDF URL, or multiple pasted identifiers through `Add by Identifier`.
- Create a project, edit its brief, and confirm Project Overview updates.
- Open Wiki in Source, Preview, and Split modes; test `Cmd+S` and snippets such as `;eq`.
- Browse Materials, preview Markdown/Python/images/PDFs, and open a file in VS Code.
- Use Library search, sorting, column configuration, multi-select, and citation copying.
- Open a PDF, search with `Cmd+F`, write notes, create a linked task, and export BibTeX.
- Configure AI Lab only with test credentials you are comfortable using, then verify that secrets are not written to workspace files.

## Roadmap Boundaries

Active development is focused on making Sci-Station a stronger local research operating system. Near-term work includes live sidecar runtime wiring, evidence navigation, debug bundles, workspace templates/modules, retrieval index health, richer graph/recommendation workflows, and deeper manual regression coverage.

Known trial limitations:

- The app is local-first and not yet notarized for public distribution.
- LLM, MinerU, Crossref, arXiv, INSPIRE, and other network features depend on user configuration and third-party availability.
- High-quality PDF-to-Markdown conversion depends on MinerU; without a token, local PDFKit extraction is used as a fallback.
- Apple Reminders support currently focuses on publishing and local mapping; full bidirectional sync is still future work.
- MCP server execution is still guarded by templates, status display, and the permission model.

## Repository Map

```text
Sci-Station/
├── App/                App state and view model
├── Agent/              Agent models, tools, runtime bridge, permissions, hooks, MCP schema
├── Calendar/           Local calendar event models and repositories
├── Collections/        Paper collection management
├── Import/             DOI/arXiv/INSPIRE/URL import services
├── Importer/           PDF import pipeline
├── Library/            Paper model, metadata, repository, search, annotations
├── LLM/                LLM configuration and provider abstractions
├── Markdown/           Markdown, frontmatter, wikilink, backlink support
├── MetadataProviders/  DOI, arXiv, and INSPIRE providers
├── PDF/                PDFKit reader support
├── Tags/               Tag models and repository
├── Tasks/              Todo models and repository
├── UI/                 SwiftUI views
├── Wiki/               Wiki page generation and editing
└── Workspace/          Workspace model, preferences, bookmarks, creation/repair
AgentRuntime/           Python sidecar runtime prototype and tests
Tools/                  SwiftPM validation tools
DOC/                    Iteration proposals and manual test protocol
```

## Related Documents

- [TUTORIAL.md](TUTORIAL.md): English hands-on tutorial.
- [TUTORIAL.zh-CN.md](TUTORIAL.zh-CN.md): Chinese hands-on tutorial.
- [README.zh-CN.md](README.zh-CN.md): Chinese product overview.
- [.sci-ai/README.md](.sci-ai/README.md): AI configuration boundary.
- [.sci-ai/sci-station/README.md](.sci-ai/sci-station/README.md): Built-in AI preset notes.
- `DOC/`: development proposals, task books, and manual testing notes for contributors.
