import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace
    @State private var workspaceName = ""
    @State private var defaultFolderPath = ""
    @State private var isShowingLegacyMigrationConfirmation = false

    var body: some View {
        HStack(spacing: 0) {
            SettingsCategorySidebar(selection: $appModel.selectedSettingsCategory)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(appModel.selectedSettingsCategory.title)
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                    Text(appModel.selectedSettingsCategory.summary)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                if appModel.selectedSettingsCategory == .workspace {
                GroupBox(appModel.localized("基本设置", "Basic Settings")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker(appModel.localized("界面语言", "Interface Language"), selection: Binding(
                            get: { appModel.workspacePreferences.appLanguage },
                            set: appModel.updateAppLanguagePreference
                        )) {
                            ForEach(AppLanguagePreference.allCases) { option in
                                Text(appModel.appLanguageLabel(for: option)).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 360)
                        Text(appModel.localized("语言设置会逐步统一新界面文案。", "The language setting is used for newly unified interface text."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Research Root") {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Workspace name", text: $workspaceName)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(renameWorkspace)
                            .help(Text(verbatim: "Rename the current research root folder"))

                        HStack(spacing: 10) {
                            Button {
                                appModel.createWorkspace()
                            } label: {
                                Label("Create Root", systemImage: "plus")
                            }
                            .help(Text(verbatim: "Create a new research root"))

                            Button {
                                appModel.openWorkspace()
                            } label: {
                                Label("Open Root", systemImage: "folder.badge.plus")
                            }
                            .help(Text(verbatim: "Open an existing research root"))

                            Button {
                                appModel.revealCurrentWorkspaceInFinder()
                            } label: {
                                Label("Reveal in Finder", systemImage: "arrow.up.right.square")
                            }
                            .help(Text(verbatim: "Reveal this research root in Finder"))

                            Button("Rename", action: renameWorkspace)
                                .buttonStyle(.borderedProminent)
                                .help(Text(verbatim: "Apply the workspace name change"))
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
                }

                if appModel.selectedSettingsCategory == .projects {
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
                            .help(Text(verbatim: "Create a new project"))
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
                                .help(Text(verbatim: "Edit this project"))
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                }

                if appModel.selectedSettingsCategory == .library {
                GroupBox("Library") {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Default folder for new imports", text: $defaultFolderPath, prompt: Text("Uncategorized"))
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(saveLibraryDefaults)
                            .help(Text(verbatim: "Set the default Library folder for imported papers"))

                        HStack(spacing: 12) {
                            Button("Save Library Defaults", action: saveLibraryDefaults)
                                .buttonStyle(.borderedProminent)
                                .help(Text(verbatim: "Save the default folder"))
                            Button("Reset Library Columns", action: appModel.resetLibraryVisibleColumns)
                                .buttonStyle(.bordered)
                                .help(Text(verbatim: "Restore default Library table columns"))
                            Button("Clear Recent Workspace", action: appModel.clearRecentWorkspaceBookmark)
                                .buttonStyle(.bordered)
                                .help(Text(verbatim: "Clear the auto-open bookmark for this workspace"))
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
                                .help(Text(verbatim: "Refresh the legacy paper scan"))

                                Button {
                                    isShowingLegacyMigrationConfirmation = true
                                } label: {
                                    Label("Copy Ready", systemImage: "doc.on.doc")
                                }
                                .controlSize(.small)
                                .disabled(appModel.legacyPaperMigrationPlan.readyCount == 0 || appModel.isRunningLegacyPaperMigration)
                                .help(Text(verbatim: "Copy ready legacy papers to library/papers and write a migration report"))
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

                GroupBox("MinerU PDF -> Markdown") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("PDF 转 Markdown 会优先调用 MinerU API；token 保存在 Keychain，不写入工作区文件。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        SecureField("粘贴 MinerU API Token", text: $appModel.minerUAPIToken)
                            .textFieldStyle(.roundedBorder)

                        TextField("MinerU API Base URL", text: Binding(
                            get: { appModel.workspacePreferences.minerUAPIBaseURLString },
                            set: { appModel.updateMinerUAPIBaseURL($0) }
                        ))
                        .textFieldStyle(.roundedBorder)

                        TextField("MinerU language", text: Binding(
                            get: { appModel.workspacePreferences.minerUAPILanguage },
                            set: { appModel.updateMinerUAPILanguage($0) }
                        ))
                        .textFieldStyle(.roundedBorder)

                        Toggle("默认允许覆盖已有 paper.md（已转换论文会先确认）", isOn: Binding(
                            get: { appModel.workspacePreferences.minerUOverwriteExistingMarkdown },
                            set: { appModel.setMinerUOverwriteExistingMarkdown($0) }
                        ))
                        .toggleStyle(.checkbox)

                        Button("保存 MinerU API 设置", action: appModel.saveMinerUMarkdownConversionSettings)
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                }

                if appModel.selectedSettingsCategory == .tasks {
                GroupBox("Tasks And Apple Reminders") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Sync new todos to Apple Reminders", isOn: Binding(
                            get: { appModel.addTodosToAppleReminders },
                            set: appModel.updateAddTodosToAppleReminders
                        ))
                        .toggleStyle(.checkbox)
                        .help(Text(verbatim: "Create an Apple Reminder when adding a new todo"))

                        HStack(spacing: 12) {
                            Button {
                                appModel.requestSystemCalendarAccess()
                            } label: {
                                Label(appModel.systemCalendarAccessState.label, systemImage: "calendar.badge.plus")
                            }
                            .help(Text(verbatim: "Grant Sci-Station access to Apple Calendar and Reminders"))
                            .disabled(appModel.systemCalendarAccessState == .authorized)

                            Button {
                                appModel.refreshSystemSchedule(around: appModel.selectedDashboardDate)
                            } label: {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                            .help(Text(verbatim: "Refresh Apple Calendar and Reminders"))
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
                }

                if appModel.selectedSettingsCategory == .aiLab {
                GroupBox("AI Lab Runtime") {
                    VStack(alignment: .leading, spacing: 10) {
                        WorkspacePathRow(label: "Mode", value: appModel.agentInteractionMode.title)
                        WorkspacePathRow(label: "Knowledge Papers", value: "\(appModel.agentKnowledgePaperSelectedCount) / \(appModel.agentKnowledgePaperTotalCount)")
                        WorkspacePathRow(label: "Agent Platform", value: appModel.agentPlatformSummary)
                        WorkspacePathRow(label: "Preset", value: appModel.agentPresetSummary)
                        WorkspacePathRow(label: "Permissions", value: appModel.agentPermissionSummary)
                        WorkspacePathRow(label: "Hooks", value: appModel.agentHookSummary)
                        WorkspacePathRow(label: "MCP", value: appModel.agentMCPStatusSummary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox(appModel.localized("AI Lab 显示", "AI Lab Display")) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Text(appModel.localized("对话字体", "Chat Font"))
                                .frame(width: 86, alignment: .leading)
                            Slider(
                                value: Binding(
                                    get: { appModel.workspacePreferences.agentChatFontSize },
                                    set: { appModel.updateAgentChatFontSize($0) }
                                ),
                                in: 11...22,
                                step: 1
                            )
                            .frame(maxWidth: 260)
                            Text("\(Int(appModel.workspacePreferences.agentChatFontSize.rounded())) pt")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 48, alignment: .trailing)
                        }

                        Text(appModel.localized("调整 AI Lab 对话消息与输入框的默认显示字号。", "Adjusts the default display size for AI Lab chat messages and the composer."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("AI Lab Tools") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Tool availability is filtered by the current mode. Conversation mode still cannot call tools even when tools are enabled here.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if appModel.agentToolDefinitions.isEmpty {
                            Text("No tools loaded for the current workspace.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(appModel.agentToolDefinitions, id: \.identifier) { tool in
                                Toggle(isOn: Binding(
                                    get: { appModel.agentEnabledToolNames.contains(tool.name) },
                                    set: { appModel.setAgentTool(tool.name, isEnabled: $0) }
                                )) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 8) {
                                            Text(tool.name)
                                                .fontWeight(.medium)
                                            Text(tool.requiresConfirmation ? "Requires approval" : "Read-only / auto")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Text(tool.summary)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .toggleStyle(.checkbox)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Hook Activity") {
                    AgentHookActivityView()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("MCP Servers") {
                    AgentMCPServerStatusView()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("LLM") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Label("OpenAI-compatible provider. Bring your own key; Sci-Station stores it in Keychain.", systemImage: "sparkles")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            Picker("DeepSeek Model", selection: Binding(
                                get: { appModel.llmConfiguration.model },
                                set: { newValue in
                                    appModel.useDeepSeekDefaults(model: newValue)
                                }
                            )) {
                                ForEach(DeepSeekModelOption.presets) { option in
                                    Text(option.title).tag(option.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 210)
                            .help(Text(verbatim: DeepSeekModelOption.option(for: appModel.llmConfiguration.model)?.detail ?? "Choose a DeepSeek-compatible model"))
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

                        Text("API Key is never written to settings.yaml or the research root. Base URL and model settings are saved as non-sensitive workspace preferences.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 12) {
                            Button("Save Settings", action: appModel.saveLLMSettings)
                                .buttonStyle(.borderedProminent)
                                .help(Text(verbatim: "Save LLM provider settings"))
                            Button("Test Connection", action: appModel.testLLMConnection)
                                .buttonStyle(.bordered)
                                .help(Text(verbatim: "Send a small test request to the configured provider"))
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

                }

                if appModel.selectedSettingsCategory == .developer {
                GroupBox("Settings Files") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Workspace paths and generated agent files are centralized here instead of taking space in working views.")
                            .foregroundStyle(.secondary)
                        WorkspacePathRow(label: "LLM Settings", value: workspace.fileURL(for: "settings.yaml").path)
                        WorkspacePathRow(label: "Workspace Preferences", value: workspace.workspacePreferencesURL.path)
                        WorkspacePathRow(label: "Schema", value: "v\(appModel.workspacePreferences.schemaVersion)")
                        WorkspacePathRow(label: "Markdown Snippets", value: workspace.markdownSnippetsURL.path)
                        WorkspacePathRow(label: "Agent Run Log", value: workspace.fileURL(for: ".sci-station/agent/runs.jsonl").path)
                        WorkspacePathRow(label: "Agent Threads", value: AgentThreadRepository.defaultThreadsFileURL.path)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                }

                if let message = appModel.workspaceSettingsStatusMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

enum SettingsCategory: String, CaseIterable, Identifiable {
    case workspace
    case projects
    case library
    case tasks
    case aiLab
    case developer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workspace:
            return "Workspace"
        case .projects:
            return "Projects"
        case .library:
            return "Library"
        case .tasks:
            return "Tasks"
        case .aiLab:
            return "AI Lab"
        case .developer:
            return "Developer"
        }
    }

    var summary: String {
        switch self {
        case .workspace:
            return "Manage the research root and workspace identity."
        case .projects:
            return "Edit project names, descriptions, icons, and colors."
        case .library:
            return "Control paper import defaults, MinerU conversion, migration, and library table behavior."
        case .tasks:
            return "Configure todo sync with Apple Reminders."
        case .aiLab:
            return "Configure API provider, runtime, hooks, MCP, and knowledge context."
        case .developer:
            return "Inspect settings files and generated agent paths."
        }
    }

    var systemImage: String {
        switch self {
        case .workspace:
            return "externaldrive"
        case .projects:
            return "folder"
        case .library:
            return "books.vertical"
        case .tasks:
            return "checklist"
        case .aiLab:
            return "sparkles"
        case .developer:
            return "terminal"
        }
    }
}

private struct SettingsCategorySidebar: View {
    @Binding var selection: SettingsCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Settings")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 16)

            ForEach(SettingsCategory.allCases) { category in
                Button {
                    selection = category
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: category.systemImage)
                            .frame(width: 16)
                            .foregroundStyle(.secondary)
                        Text(category.title)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 10)
                    .background(selection == category ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(width: 190)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
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