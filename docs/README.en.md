# Sci-Station

> Current version: 0.2.0
> Platform: Apple Silicon Mac, macOS 15 or later
> Release stage: Developer Preview

Sci-Station is a local-first research workstation. One Go/Wails desktop app brings together a shared paper library, PDF reading and annotation, project Wiki and materials, tasks and calendars, AI Lab, and a multi-seat Roundtable. Papers, notes, tasks, and meeting history live in a research workspace you choose. You can grant individual projects access to their existing folders.

[中文](../README.md) · [English tutorial](TUTORIAL.md)

## Get started

Install Go 1.26 and Xcode Command Line Tools. From the repository root, build and open the app:

```sh
make run
```

Use **Workspace → Create Workspace** and select an empty folder. You can reopen it from the same menu. Create a project, import a PDF into the library, and add the paper to the project. Select a passage in the reader to save an annotation or send it to a project Roundtable. After review, save a proposed note or task and follow its citation back to the paper.

A source build contains the current Go/Wails development line. [GitHub Releases](https://github.com/Funyday-k/Sci-Station/releases) contains published previews. If you are switching from an older app, follow the [workspace and recovery guide](workspaces.md) to start a new workspace and preserve your original research and backups.

## What you can do

- Share a paper and its PDF across projects, with separate project membership, pins, order, and core-paper status. Organize the library with collections and tags, export citations, and reopen reading positions and source passages.
- Keep project notes, Wiki links, citation graphs and working files together. Grant and revoke access to external project folders from project settings.
- Link tasks to projects and papers, browse local calendars, and connect Apple Calendar or Reminders when needed. Run literature searches, review recorded candidates, or import a daily recommendation feed.
- Use either a single run in AI Lab or a multi-seat discussion in Roundtable with source excerpts. Review a proposed note or task before saving it. A supported local CLI can request file-edit approval through Roundtable and carries out the permitted edit itself.

Local papers, annotations, Wiki, tasks, materials, and local PDF text conversion work offline. Optional model connections use a local Magpie gateway or a configured direct provider. The desktop app can store direct-provider keys and the optional MinerU token in macOS Keychain. Network imports, arXiv discovery and external services connect when invoked. See the [tutorial](TUTORIAL.md) for the research workflow and configuration.

## Contribute

- [`cmd/sci-station`](../cmd/sci-station/) starts the app. [`internal/desktop`](../internal/desktop/) implements the desktop host and API, [`web/static`](../web/static/) contains the embedded frontend, and [`internal/research`](../internal/research/) owns research records.
- [Developer guide](DEVELOPER.md) for architecture, builds and tests.
- [Contributing](../CONTRIBUTING.md) and [repository governance](GOVERNANCE.md) for review and release policy.
- [Changelog](../CHANGELOG.md) for current changes and release history.
- [Security policy](../SECURITY.md) for private reporting.

Sci-Station uses the [MIT License](../LICENSE). See [brand assets](brand-assets.md) for third-party artwork provenance.
