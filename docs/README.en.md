# Sci-Station

> Current version: 0.1.0
> Platform: macOS
> Status: Developer Preview

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
- Paper `meta.yaml` files are parsed and emitted with Yams; updates preserve unknown fields and nested structures semantically, while malformed YAML returns an explicit error and is never silently overwritten.
- PDF Reader with search, navigation, zoom, notes, linked tasks, citations, links, and file panel.
- Project overview with brief, core papers, project documents, workflows, and task summary.
- Markdown Wiki with source, preview, split mode, frontmatter, `[[wikilink]]`, backlinks, tables, code blocks, images, and KaTeX.
- Materials browser for data, code, figures, scripts, prompts, outputs, Markdown, text, images, PDFs, and Python files.
- Local todo and calendar views with optional Apple Calendar and Reminders integration.
- AI Lab V1 with project conversations, plan review, permission dock, run history, hooks, MCP preset display, and audit logs.
- Future public releases require Developer ID signing, notarization, stapling and installation verification; check each historical release's own distribution status.

## Version 0.1.0 Status

- The current preview is **0.1.0**. This historical release was not Developer ID signed or notarized.
- New public releases are required to pass Developer ID and Apple notarization verification before publication.
- The project remains actively maintained, and features, UI, and documentation will continue to improve.

## Roadmap

- Deeper AI Lab sidecar runtime integration, tool permissions, evidence references, artifacts, and debug bundles.
- Paper graph, recommendation workflows, and reading-todo improvements.
- Workspace templates, module settings, and clearer onboarding.
- Better DOI/arXiv/web import, PDF-to-Markdown conversion, and metadata enrichment.
- Broader manual regression coverage and bilingual documentation polish.

## Quick Start

Install a verified release package:

1. Check the release notes and select a DMG with signing/notarization verification and SHA-256 checksums. Historical 0.1.0 does not meet these distribution requirements; source builds are documented in the developer guide.
2. Open the DMG and drag `Sci-Station.app` into `/Applications`.
3. A public release should pass Gatekeeper normally. Stop and verify the download source and SHA-256 if macOS cannot verify the developer.
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

## Contributing

Read [CONTRIBUTING](../CONTRIBUTING.md), the [security policy](../SECURITY.md), the [versioned backlog](BACKLOG.md), the [ADR index](architecture/README.md), and the [versioning policy](VERSIONING.md).
