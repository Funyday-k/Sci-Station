# Sci-Station tutorial

[中文教程](TUTORIAL.zh-CN.md)

## Open a workspace and create a project

On an Apple Silicon Mac with macOS 15 or later, install Go 1.26 and Xcode Command Line Tools. Run `make run` from the repository root. The app opens its macOS desktop window. Use **Workspace → Create Workspace**, select an empty folder, and give your first project a name under **Projects → New Project**. Open the same folder with **Workspace → Open Workspace** to continue on another launch.

When moving from a previously published app or the Go prototype, keep your original data and make a verified copy where applicable. The [workspace and recovery guide](workspaces.md) describes how each source is handled.

## Import and cite a paper

1. Open **Library → Import papers**. Choose a local PDF or enter a supported identifier such as a DOI or arXiv ID. Review the import and choose a collection if appropriate.
2. Open a paper and add it to the project. You can add the same paper to another project with its own pin, position and core-paper status.
3. Open the PDF reader and select a passage. Save an annotation or send the passage and its source location to Roundtable. Use **Citation** in the reader or library to copy BibTeX or another citation format.
4. To use a searchable version of the paper body in AI Lab, import its Markdown or adopt a reviewed PDFKit or MinerU conversion. Check the extracted equations, figure references and source locations against the PDF before relying on them.

Removing a paper from the current project keeps its PDF and its links to other projects. Deleting it from the shared library shows the affected projects, Wiki pages and task references before confirmation. A Wiki page keeps its source identifier and remains editable after the source is gone.

## Organize a research project

- Create linked pages in **Wiki**. Use **Graph** to follow source references and see which notes or papers connect to them. An online INSPIRE query shares the selected paper's public identifier and retains the resulting scoped cache.
- Open **Materials** to preview files managed by the project. To work with an existing research directory, select it explicitly in project settings. Reapprove a replaced directory before using actions that read from it or open it in an editor.
- Create a **Task** with the relevant projects, papers and due date. The calendar displays local tasks offline. Use the calendar controls to request Apple Calendar access or publish tasks to Reminders when desired.
- Use literature discovery to fetch candidates or read a daily JSON/JSONL recommendation feed. Previously recorded search results remain available for later review.

## Discuss evidence and review writeback

In settings, choose a direct model profile or register the Sci-Station agent with your local Magpie gateway and select its model in Magpie. A direct HTTPS provider takes an API Base URL, model ID and API key. A local loopback endpoint can also use HTTP. macOS Keychain stores persistent direct-provider keys and the optional MinerU token.

1. Select text in the PDF reader and send it to a project Roundtable. Add seats, assign models, and choose a discussion method. To examine a source with one seat, use AI Lab.
2. Ask a question about the chosen text; open cited passages and check the discussion or report against the original source. See the [discussion methods](discussion-methods.md) for evidence roles and the moderator's options.
3. Review a proposed note or task and confirm to save it. Reopen the project record after restarting and follow the citation to its original passage.
4. For direct edits to a granted project's files, explicitly start a supported local CLI editing session. Read the request and available changes in Roundtable before approving or refusing. The originating CLI receives the one-time decision and reports the outcome.

AI Lab can import a project Markdown skill. Preview, enable and trust its specific version before adding it to a run. In the desktop AI Lab, you can register a trusted HTTPS or local stdio research connector for a project. Bearer credentials go in the macOS Keychain. A local program runs with your account permissions. Review the selected program and script before trusting them. You can select an excerpt yourself, or review an external read proposed by a model. Check the project, connection, operation and exact arguments before approving. Your decision applies to this request only. The [Roundtable plugin guide](plugins.md) covers discussion guidance and local report tools.

## Back up your research

Quit the app before copying an entire workspace. Preserve its research records, paper files, Markdown sources and meeting history together, and copy any externally granted folders independently. Keep a protected copy and test reopening a separate copy. See [workspaces, backup and recovery](workspaces.md) for format markers, folder grants, prototype recovery and restoring from a backup.
