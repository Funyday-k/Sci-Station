import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace
    @State private var workspaceName = ""
    @State private var defaultFolderPath = ""
    @State private var isShowingLegacyMigrationConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Settings")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                    Text("Manage the research root, project defaults, library organization, task sync, and LLM provider.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                GroupBox("Research Root") {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Workspace name", text: $workspaceName)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(renameWorkspace)
                            .help("Rename the current research root folder")

                        HStack(spacing: 10) {
                            Button {
                                appModel.createWorkspace()
                            } label: {
                                Label("Create Root", systemImage: "plus")
                            }
                            .help("Create a new research root")

                            Button {
                                appModel.openWorkspace()
                            } label: {
                                Label("Open Root", systemImage: "folder.badge.plus")
                            }
                            .help("Open an existing research root")

                            Button {
                                appModel.revealCurrentWorkspaceInFinder()
                            } label: {
                                Label("Reveal in Finder", systemImage: "arrow.up.right.square")
                            }
                            .help("Reveal this research root in Finder")

                            Button("Rename", action: renameWorkspace)
                                .buttonStyle(.borderedProminent)
                                .help("Apply the workspace name change")
                        }

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], alignment: .leading, spacing: 12) {
                            WorkspacePathRow(label: "Root", value: workspace.rootURL.path)
                            WorkspacePathRow(label: "Projects", value: "\(appModel.activeResearchProjects.count)")
                            WorkspacePathRow(label: "Papers", value: "\(appModel.papers.count)")
                            WorkspacePathRow(label: "Folders", value: "\(appModel.collections.count)")
                            WorkspacePathRow(label: "Tags", value: "\(appModel.availableTagDefinitions.count)")
                            WorkspacePathRow(label: "Open Todos", value: "\(appModel.todos.filter { $0.status != .done && $0.status != .cancelled }.count)")
                        }

                        if let message = appModel.rootCompatibilityMessage {
                            Label(message, systemImage: "arrow.triangle.branch")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Projects") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Edit project names, descriptions, icons, and colors.")
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            Button {
                                appModel.beginCreatingResearchProject()
                            } label: {
                                Label("New Project", systemImage: "plus")
                            }
                            .help("Create a new project")
                        }

                        ForEach(appModel.activeResearchProjects) { project in
                            HStack(spacing: 10) {
                                Image(systemName: project.iconName.isEmpty ? "folder" : project.iconName)
                                    .frame(width: 20)
                                    .foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(project.name)
                                        .fontWeight(.medium)
                                    Text(project.description.isEmpty ? project.relativePath : project.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                Text("\(appModel.papers(for: project.id).count) papers")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Button("Edit") {
                                    appModel.beginEditingResearchProject(project.id)
                                }
                                .buttonStyle(.link)
                                .help("Edit this project")
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Library") {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Default folder for new imports", text: $defaultFolderPath, prompt: Text("Uncategorized"))
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(saveLibraryDefaults)
                            .help("Set the default Library folder for imported papers")

                        HStack(spacing: 12) {
                            Button("Save Library Defaults", action: saveLibraryDefaults)
                                .buttonStyle(.borderedProminent)
                                .help("Save the default folder")
                            Button("Reset Library Columns", action: appModel.resetLibraryVisibleColumns)
                                .buttonStyle(.bordered)
                                .help("Restore default Library table columns")
                            Button("Clear Recent Workspace", action: appModel.clearRecentWorkspaceBookmark)
                                .buttonStyle(.bordered)
                                .help("Clear the auto-open bookmark for this workspace")
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Label("Legacy raw/papers", systemImage: appModel.legacyPaperMigrationPlan.hasLegacyPapers ? "externaldrive.badge.exclamationmark" : "checkmark.circle")
                                    .fontWeight(.medium)
                                Spacer(minLength: 0)
                                if appModel.isLoadingLegacyPaperMigrationPlan {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Button {
                                    appModel.refreshLegacyPaperMigrationPlan()
                                } label: {
                                    Label("Refresh", systemImage: "arrow.clockwise")
                                }
                                .controlSize(.small)
                                .help("Refresh the legacy paper scan")

                                Button {
                                    isShowingLegacyMigrationConfirmation = true
                                } label: {
                                    Label("Copy Ready", systemImage: "doc.on.doc")
                                }
                                .controlSize(.small)
                                .disabled(appModel.legacyPaperMigrationPlan.readyCount == 0 || appModel.isRunningLegacyPaperMigration)
                                .help("Copy ready legacy papers to library/papers and write a migration report")
                            }

                            if appModel.isRunningLegacyPaperMigration {
                                ProgressView("Copying legacy papers…")
                                    .controlSize(.small)
                            }

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], alignment: .leading, spacing: 12) {
                                WorkspacePathRow(label: "Legacy Papers", value: "\(appModel.legacyPaperMigrationPlan.legacyPaperCount)")
                                WorkspacePathRow(label: "Ready", value: "\(appModel.legacyPaperMigrationPlan.readyCount)")
                                WorkspacePathRow(label: "Conflicts", value: "\(appModel.legacyPaperMigrationPlan.conflictCount)")
                                WorkspacePathRow(label: "Target", value: Paper.globalLibraryRootRelativePath)
                            }

                            if appModel.legacyPaperMigrationPlan.items.isEmpty {
                                Label("No legacy raw/papers items detected.", systemImage: "checkmark.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(Array(appModel.legacyPaperMigrationPlan.items.prefix(5))) { item in
                                        LegacyMigrationPlanRow(item: item)
                                    }

                                    if appModel.legacyPaperMigrationPlan.items.count > 5 {
                                        Text("+\(appModel.legacyPaperMigrationPlan.items.count - 5) more")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }

                            if let report = appModel.legacyPaperMigrationReport {
                                Label("Last report: copied \(report.copiedCount), skipped \(report.skippedCount), failed \(report.failedCount). \(report.reportRelativePath ?? "")", systemImage: "doc.text")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        WorkspacePathRow(label: "Visible Columns", value: appModel.workspacePreferences.libraryVisibleColumns.joined(separator: ", "))
                        WorkspacePathRow(label: "Library Sort", value: librarySortDescription)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Tasks And Apple Reminders") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Sync new todos to Apple Reminders", isOn: Binding(
                            get: { appModel.addTodosToAppleReminders },
                            set: appModel.updateAddTodosToAppleReminders
                        ))
                        .toggleStyle(.checkbox)
                        .help("Create an Apple Reminder when adding a new todo")

                        HStack(spacing: 12) {
                            Button {
                                appModel.requestSystemCalendarAccess()
                            } label: {
                                Label(appModel.systemCalendarAccessState.label, systemImage: "calendar.badge.plus")
                            }
                            .help("Grant Sci-Station access to Apple Calendar and Reminders")
                            .disabled(appModel.systemCalendarAccessState == .authorized)

                            Button {
                                appModel.refreshSystemSchedule(around: appModel.selectedDashboardDate)
                            } label: {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                            .help("Refresh Apple Calendar and Reminders")
                            .disabled(!appModel.systemCalendarAccessState.canReadSchedule)

                            if appModel.isLoadingSystemSchedule {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                        .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("LLM") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Label("DeepSeek is the default OpenAI-compatible provider.", systemImage: "sparkles")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            Button("DeepSeek Flash") {
                                appModel.useDeepSeekDefaults(model: "deepseek-v4-flash")
                            }
                            .help("Use https://api.deepseek.com with deepseek-v4-flash")
                            Button("DeepSeek Pro") {
                                appModel.useDeepSeekDefaults(model: "deepseek-v4-pro")
                            }
                            .help("Use https://api.deepseek.com with deepseek-v4-pro")
                        }

                        TextField(
                            "Base URL",
                            text: llmBinding(
                                get: { $0.baseURLString },
                                set: { configuration, newValue in
                                    configuration.baseURLString = newValue
                                }
                            )
                        )
                            .textFieldStyle(.roundedBorder)

                        TextField(
                            "Model",
                            text: llmBinding(
                                get: { $0.model },
                                set: { configuration, newValue in
                                    configuration.model = newValue
                                }
                            )
                        )
                            .textFieldStyle(.roundedBorder)

                        HStack(spacing: 12) {
                            TextField(
                                "Temperature",
                                value: llmBinding(
                                    get: { $0.temperature },
                                    set: { configuration, newValue in
                                        configuration.temperature = newValue
                                    }
                                ),
                                format: .number
                            )
                                .textFieldStyle(.roundedBorder)
                            TextField("Max Tokens", value: Binding(
                                get: { appModel.llmConfiguration.maxTokens ?? 0 },
                                set: { newValue in
                                    appModel.updateLLMConfiguration { configuration in
                                        configuration.maxTokens = newValue == 0 ? nil : newValue
                                    }
                                }
                            ), format: .number)
                            .textFieldStyle(.roundedBorder)
                        }

                        SecureField("API Key", text: $appModel.llmAPIKey)
                            .textFieldStyle(.roundedBorder)

                        HStack(spacing: 12) {
                            Button("Save Settings", action: appModel.saveLLMSettings)
                                .buttonStyle(.borderedProminent)
                                .help("Save LLM provider settings")
                            Button("Test Connection", action: appModel.testLLMConnection)
                                .buttonStyle(.bordered)
                                .help("Send a small test request to the configured provider")
                        }

                        if appModel.isTestingLLMConnection {
                            ProgressView("Testing connection…")
                        }

                        if let message = appModel.llmConnectionStatusMessage {
                            Text(message)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Settings Files") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Workspace paths and generated agent files are centralized here instead of taking space in working views.")
                            .foregroundStyle(.secondary)
                        WorkspacePathRow(label: "LLM Settings", value: workspace.fileURL(for: "settings.yaml").path)
                        WorkspacePathRow(label: "Workspace Preferences", value: workspace.workspacePreferencesURL.path)
                        WorkspacePathRow(label: "Schema", value: "v\(appModel.workspacePreferences.schemaVersion)")
                        WorkspacePathRow(label: "Markdown Snippets", value: workspace.markdownSnippetsURL.path)
                        WorkspacePathRow(label: "Agent Run Log", value: workspace.fileURL(for: ".sci-station/agent/runs.jsonl").path)
                        WorkspacePathRow(label: "Agent Threads", value: workspace.fileURL(for: ".sci-station/agent/threads.jsonl").path)
                        WorkspacePathRow(label: "Copilot Bridge", value: workspace.directoryURL(for: ".sci-station/agent/copilot-bridge").path)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let message = appModel.workspaceSettingsStatusMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
        .onAppear(perform: syncDrafts)
        .onChange(of: workspace.rootURL) { _, _ in
            syncDrafts()
        }
        .confirmationDialog(
            "Copy ready legacy papers to library/papers?",
            isPresented: $isShowingLegacyMigrationConfirmation,
            titleVisibility: .visible
        ) {
            Button("Copy Ready Papers") {
                appModel.copyReadyLegacyPapers()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Sci-Station will copy ready raw/papers items into library/papers, skip conflicts, keep the original raw/papers files in place, and write a JSON migration report.")
        }
    }

    private func syncDrafts() {
        workspaceName = workspace.displayName
        defaultFolderPath = appModel.workspacePreferences.defaultCollectionPath ?? ""
    }

    private func renameWorkspace() {
        appModel.renameCurrentWorkspace(to: workspaceName)
    }

    private func saveLibraryDefaults() {
        appModel.updateDefaultCollectionPath(defaultFolderPath)
    }

    private var librarySortDescription: String {
        guard let field = appModel.workspacePreferences.librarySortState.field else {
            return "Original order"
        }

        return "\(field.label) \(appModel.workspacePreferences.librarySortState.isAscending ? "ascending" : "descending")"
    }

    private func llmBinding<Value>(
        get: @escaping (LLMConfiguration) -> Value,
        set: @escaping (inout LLMConfiguration, Value) -> Void
    ) -> Binding<Value> {
        Binding(
            get: { get(appModel.llmConfiguration) },
            set: { newValue in
                appModel.updateLLMConfiguration { configuration in
                    set(&configuration, newValue)
                }
            }
        )
    }
}

private struct LegacyMigrationPlanRow: View {
    let item: LegacyPaperMigrationItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.hasConflicts ? "exclamationmark.triangle.fill" : "doc.on.doc")
                .foregroundStyle(item.hasConflicts ? Color.orange : Color.accentColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(item.title)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text(item.status.label)
                        .font(.caption2)
                        .foregroundStyle(item.hasConflicts ? Color.orange : Color.secondary)
                }
                Text("\(item.sourceRelativePath) -> \(item.targetRelativePath)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if !item.conflicts.isEmpty {
                    Text(item.conflicts.map(\.label).joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct SettingsSceneView: View {
    @EnvironmentObject private var appModel: AppViewModel

    var body: some View {
        if let workspace = appModel.currentWorkspace {
            SettingsView(workspace: workspace)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Open or create a research root before editing workspace settings.")
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button("Create Root", action: appModel.createWorkspace)
                        .buttonStyle(.borderedProminent)
                    Button("Open Root", action: appModel.openWorkspace)
                        .buttonStyle(.bordered)
                }
            }
            .padding(24)
            .frame(width: 520, alignment: .topLeading)
        }
    }
}

struct LLMSummaryPreviewView: View {
    @EnvironmentObject private var appModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("LLM Summary Preview")
                .font(.title2)
                .fontWeight(.semibold)

            TextEditor(text: Binding(
                get: { appModel.summaryPreviewText ?? "" },
                set: appModel.updateSummaryPreviewText
            ))
            .font(.system(.body, design: .monospaced))

            HStack(spacing: 12) {
                Button("Replace Wiki") {
                    appModel.applySummaryPreview(mode: .replace)
                }
                .buttonStyle(.borderedProminent)

                Button("Append") {
                    appModel.applySummaryPreview(mode: .append)
                }
                .buttonStyle(.bordered)

                Button("Save Draft") {
                    appModel.applySummaryPreview(mode: .saveDraft)
                }
                .buttonStyle(.bordered)

                Button("Close") {
                    dismiss()
                }
            }
        }
        .padding(20)
        .frame(minWidth: 860, minHeight: 560)
    }
}