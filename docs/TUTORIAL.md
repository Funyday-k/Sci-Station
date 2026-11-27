# Sci-Station tutorial

[中文教程](TUTORIAL.zh-CN.md)

## Create your first project

On an Apple Silicon Mac with macOS 15 or later, install Go 1.26 and Xcode Command Line Tools. Run `make run` from the repository root. Choose **Projects → New Project** to create your first project. A fresh installation stores shared data and papers in your user Application Support directory. Existing installations reopen their saved data location. Open data storage in Settings to see the path or choose another library.

When moving from a previously published app or the Go prototype, keep your original data and make a verified copy where applicable. The [workspace and recovery guide](workspaces.md) describes how each source is handled.

## Navigation and appearance

The sidebar holds Home, Projects, Library, Calendar and AI. Use the arrow beside a project to expand or collapse its modules. Right-click a project and choose **Edit project info** to edit that project. Keyboard users can focus its row and press Shift+F10. In compact windows the sidebar button opens the navigator.

Selecting papers prepares bulk actions without opening a panel. Use an item's **View details** icon when you need its properties, or **Annotations and notes** in the reader. The top-bar chat icon opens AI. Closing a panel returns focus to its entry point; pinning keeps it open across views and restarts. Icons have accessible names and hover labels.

Use **Settings → Appearance** to choose light or dark mode, text size and an accent. Backgrounds, navigation and ordinary buttons use neutral colors, while primary actions and selected controls use the accent. Cards on Home and project overviews align to a common grid. Use **Edit layout** to change their order, size and visibility.

## Import and cite a paper

1. Open **Library → Import papers** and paste a publication link, DOI or arXiv ID, or drop or choose a local PDF. You can add collection, tags and metadata under details. An ordinary article link keeps its source URL even if publication metadata is unavailable.
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

1. Open **AI** and choose **Chat** for a single research conversation with its source material, or **Roundtable** for a discussion with multiple seats. You can start without a project or open AI from a project. In a new chat, choose a project, files or plugins beside the composer. Choose a model and use the slider for its available reasoning levels. Open the conversation sidebar to create, find or reopen chats.
2. Use the mode switch to bring a question, recent messages or selected attachments to the other mode. Review the proposed context, then add it to the destination draft. The original conversation stays available. Sending the draft starts the next run. See the [discussion methods](discussion-methods.md) for discussion and evidence options.
3. Review a proposed note or task and confirm to save it. Reopen the project record after restarting and follow the citation to its original passage.
4. For direct edits to a granted project's files, explicitly start a supported local CLI editing session. Read the request and available changes in Roundtable before approving or refusing. The originating CLI receives the one-time decision and reports the outcome.

In single chat, open **Plugins** to browse tools. Each detail view includes a way back to the list. You can import a project Markdown skill. Preview, enable and trust its specific version before adding it to a run. In the desktop AI Lab, you can register a trusted HTTPS or local stdio research connector for a project. Bearer credentials go in the macOS Keychain. A local program runs with your account permissions. Review the selected program and script before trusting them. You can select an excerpt yourself, or review an external read proposed by a model. Check the project, connection, operation and exact arguments before approving. Your decision applies to this request only. The [Roundtable plugin guide](plugins.md) covers discussion guidance and local report tools.

## Back up your research

Quit the app before copying an entire workspace. Preserve its research records, paper files, Markdown sources and meeting history together, and copy any externally granted folders independently. Keep a protected copy and test reopening a separate copy. See [workspaces, backup and recovery](workspaces.md) for format markers, folder grants, prototype recovery and restoring from a backup.
