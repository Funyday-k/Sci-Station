# Sci-Station

> Current version: Beta 0.1.0
> Platform: macOS
> Status: in development. Test builds will be published through Releases.

Sci-Station is a local-first research workstation for macOS. It brings a paper library, project knowledge, PDF reading, working materials, tasks, calendar views, and optional AI Lab workflows into one app while keeping core data inside a user-selected local Research Root.

The primary project README is Chinese-first: [../README.md](../README.md). A hands-on Chinese tutorial is available at [TUTORIAL.zh-CN.md](TUTORIAL.zh-CN.md).

## Overview

Research projects often begin as scattered PDFs, notes, code folders, datasets, figures, tasks, links, and proposal drafts. Sci-Station turns that working mess into a visible, auditable, portable local workspace.

Core principles:

- **Local-first ownership**: papers, notes, project files, tasks, logs, and generated artifacts stay in the user's own folder.
- **Research-native structure**: the app is organized around papers, projects, citations, materials, figures, outputs, and research records.
- **Auditable AI assistance**: AI is optional; secrets are stored in macOS Keychain, write actions require permission, and runs leave reviewable logs.

## Current Features

- Research Root creation, opening, repair, and recent workspace restore.
- Paper import from PDF files, drag and drop, DOI, arXiv, PDF URL, and web links.
- Paper metadata, BibTeX, tags, reading status, priority, rating, abstract, and identifiers.
- PDF Reader with search, navigation, zoom, notes, linked tasks, citations, links, and file panel.
- Project overview with brief, core papers, project documents, workflows, and task summary.
- Markdown Wiki with source, preview, split mode, frontmatter, `[[wikilink]]`, backlinks, tables, code blocks, images, and KaTeX.
- Materials browser for data, code, figures, scripts, prompts, outputs, Markdown, text, images, PDFs, and Python files.
- Local todo and calendar views with optional Apple Calendar and Reminders integration.
- AI Lab V1 with project conversations, plan review, permission dock, run history, hooks, MCP preset display, and audit logs.
- Beta DMG packaging for tester handoff.

## Beta 0.1.0 Status

- The current version is **Beta 0.1.0**.
- Test builds will be published through Releases, like a normal macOS app download.
- The project is still in development, and features, UI, and documentation will continue to change.

## Roadmap

- Developer ID signing, notarization, and cleaner Gatekeeper-friendly distribution.
- Deeper AI Lab sidecar runtime integration, tool permissions, evidence references, artifacts, and debug bundles.
- Paper graph, recommendation workflows, research queue, and reading plan improvements.
- Workspace templates, module settings, and clearer onboarding.
- Better DOI/arXiv/web import, PDF-to-Markdown conversion, and metadata enrichment.
- Broader manual regression coverage and bilingual documentation polish.

## Quick Start

Use a beta DMG:

1. Download the Sci-Station DMG from the Release page.
2. Open the DMG and drag `Sci-Station.app` into `/Applications`.
3. If macOS cannot verify the developer, right-click the app and choose `Open`.
4. On first launch, choose `Create Workspace` and select an empty folder as the Research Root.
5. Import PDFs from Library, or add papers with DOI, arXiv, PDF URL, and web links.

Run from source:

```bash
open Sci-Station.xcodeproj
```

In Xcode, choose the `Sci-Station` scheme, select `My Mac`, then press `Command + R`.

## Related Documents

- [../README.md](../README.md): Chinese project overview.
- [TUTORIAL.md](TUTORIAL.md): English hands-on tutorial.
- [TUTORIAL.zh-CN.md](TUTORIAL.zh-CN.md): Chinese hands-on tutorial.
- [DEVELOPER.md](DEVELOPER.md): developer architecture and feature guide.
- [../.sci-ai/README.md](../.sci-ai/README.md): AI configuration boundary.
- [../.sci-ai/sci-station/README.md](../.sci-ai/sci-station/README.md): Built-in AI preset notes.
- [development/](development/): development proposals, task books, and manual testing notes.