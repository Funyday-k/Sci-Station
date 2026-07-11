import SwiftUI

private struct AgentSkillToggleReview: Identifiable, Hashable {
    enum Action: Hashable {
        case setEnabled(Bool)
        case setTrusted(Bool)

        var title: String {
            switch self {
            case let .setEnabled(isEnabled):
                return isEnabled ? "Enable skill?" : "Disable skill?"
            case let .setTrusted(isTrusted):
                return isTrusted ? "Trust workspace skill?" : "Remove skill trust?"
            }
        }

        var buttonTitle: String {
            switch self {
            case let .setEnabled(isEnabled):
                return isEnabled ? "Enable Skill" : "Disable Skill"
            case let .setTrusted(isTrusted):
                return isTrusted ? "Trust Skill" : "Remove Trust"
            }
        }
    }

    var id = UUID()
    var entry: AgentSkillCatalogEntry
    var action: Action
}

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace
    var fixedCategory: SettingsCategory? = nil
    @State private var workspaceName = ""
    @State private var defaultFolderPath = ""
    @State private var isShowingLegacyMigrationConfirmation = false
    @State private var promptDrafts: [String: AgentPromptTemplateOverride] = [:]
    @State private var promptProposalStates: [String: AgentPromptPatchDecision] = [:]
    @State private var pendingPromptPatchReview: AgentPromptPatchReview?
    @State private var skillCatalogEntries: [AgentSkillCatalogEntry] = []
    @State private var skillCatalogSearchText = ""
    @State private var skillCatalogStatusMessage: String?
    @State private var skillCatalogRefreshID = UUID()
    @State private var pendingSkillToggleReview: AgentSkillToggleReview?
    private let promptLibraryResolver = AgentPromptLibraryResolver()
    private let skillLoader = AgentSkillLoader()

    private var activeCategory: SettingsCategory {
        fixedCategory ?? appModel.selectedSettingsCategory
    }

    var body: some View {
        HStack(spacing: 0) {
            if fixedCategory == nil {
                SettingsCategorySidebar(selection: $appModel.selectedSettingsCategory)

                Divider()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                if activeCategory != .aiLab {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(activeCategory.title(appModel: appModel))
                            .font(.system(size: fixedCategory == nil ? 42 : 28, weight: .bold, design: .rounded))
                        Text(activeCategory.summary(appModel: appModel))
                            .font(fixedCategory == nil ? .title3 : .callout)
                            .foregroundStyle(.secondary)
                    }
                }

                if activeCategory == .workspace {
                GroupBox(appModel.t(.settingsBasicSettings)) {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker(appModel.t(.settingsInterfaceLanguage), selection: Binding(
                            get: { appModel.workspacePreferences.appLanguage },
                            set: appModel.updateAppLanguagePreference
                        )) {
                            ForEach(AppLanguagePreference.allCases) { option in
                                Text(appModel.appLanguageLabel(for: option)).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 360)
                        Text(appModel.t(.settingsLanguageHelp))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox(appModel.localized("液态玻璃", "Liquid Glass")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker(appModel.localized("色调", "Tint"), selection: Binding(
                            get: { appModel.workspacePreferences.liquidGlassTint },
                            set: appModel.updateLiquidGlassTintPreference
                        )) {
                            ForEach(LiquidGlassTintPreference.allCases) { option in
                                Text(appModel.liquidGlassTintLabel(for: option)).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 260)

                        HStack(spacing: 8) {
                            ForEach(LiquidGlassTintPreference.allCases) { option in
                                Button {
                                    appModel.updateLiquidGlassTintPreference(option)
                                } label: {
                                    Circle()
                                        .fill(AppViewModel.color(for: option).opacity(option == .system ? 0.72 : 0.88))
                                        .frame(width: 18, height: 18)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(
                                                    appModel.workspacePreferences.liquidGlassTint == option ? Color.primary.opacity(0.65) : Color.primary.opacity(0.12),
                                                    lineWidth: appModel.workspacePreferences.liquidGlassTint == option ? 2 : 0.8
                                                )
                                        )
                                }
                                .buttonStyle(.plain)
                                .help(appModel.liquidGlassTintLabel(for: option))
                            }
                        }

                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox(appModel.t(.settingsResearchRoot)) {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField(appModel.t(.settingsWorkspaceName), text: $workspaceName)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(renameWorkspace)
                            .help(Text(verbatim: "Rename the current research root folder"))

                        HStack(spacing: 10) {
                            Button {
                                appModel.beginWorkspaceCreation()
                            } label: {
                                Label(appModel.t(.settingsCreateRoot), systemImage: "plus")
                            }
                            .help(Text(verbatim: "Open the workspace creation wizard"))

                            Button {
                                appModel.openWorkspace()
                            } label: {
                                Label(appModel.t(.settingsOpenRoot), systemImage: "folder.badge.plus")
                            }
                            .help(Text(verbatim: "Open an existing research root"))

                            Button {
                                appModel.revealCurrentWorkspaceInFinder()
                            } label: {
                                Label(appModel.t(.settingsRevealRoot), systemImage: "arrow.up.right.square")
                            }
                            .help(Text(verbatim: "Reveal this research root in Finder"))

                            Button(appModel.t(.settingsRename), action: renameWorkspace)
                                .buttonStyle(.borderedProminent)
                                .help(Text(verbatim: "Apply the workspace name change"))
                        }

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], alignment: .leading, spacing: 12) {
                            WorkspacePathRow(label: "Root", value: workspace.rootURL.path)
                            WorkspacePathRow(label: appModel.t(.routeProjects), value: "\(appModel.activeResearchProjects.count)")
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

                GroupBox(appModel.t(.settingsWorkspaceModules)) {
                    let availableModuleIDs = Set(appModel.workspaceContributionCatalog(for: nil).availableModules().map(\.id))
                    VStack(alignment: .leading, spacing: 12) {
                        WorkspacePathRow(label: "Registry", value: appModel.workspaceModuleStatusSummary)
                        WorkspacePathRow(label: "Config", value: WorkspaceTemplateRepository.modulesRelativePath)
                        WorkspacePathRow(label: "Workflows", value: appModel.enabledAgentWorkflowIDs.isEmpty ? "none" : appModel.enabledAgentWorkflowIDs.sorted().joined(separator: ", "))

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10)], alignment: .leading, spacing: 8) {
                            ForEach(appModel.workspaceModuleConfiguration.modules) { module in
                                HStack(spacing: 8) {
                                    Image(systemName: module.enabled ? (availableModuleIDs.contains(module.id) ? "checkmark.circle" : "exclamationmark.triangle") : "circle")
                                        .foregroundStyle(module.enabled ? (availableModuleIDs.contains(module.id) ? Color.green : Color.orange) : Color.secondary)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(module.title)
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .lineLimit(1)
                                        Text(module.enabled ? (availableModuleIDs.contains(module.id) ? "enabled" : "dependency hidden") : "disabled")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }

                        if !appModel.workspaceModuleWarnings.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Warnings")
                                    .font(.caption.weight(.semibold))
                                ForEach(appModel.workspaceModuleWarnings.prefix(6)) { warning in
                                    Label(warning.message, systemImage: warning.severity == .error ? "xmark.octagon" : "exclamationmark.triangle")
                                        .font(.caption)
                                        .foregroundStyle(warning.severity == .error ? .red : .orange)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }

                        if !appModel.workspaceModuleDirectoryStatuses.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Module Paths")
                                    .font(.caption.weight(.semibold))
                                ForEach(Array(appModel.workspaceModuleDirectoryStatuses.prefix(8))) { status in
                                    HStack(spacing: 8) {
                                        Image(systemName: status.exists ? "folder" : (status.required ? "folder.badge.questionmark" : "folder"))
                                            .foregroundStyle(status.exists || !status.required ? Color.secondary : Color.orange)
                                        Text("\(status.moduleTitle): \(status.path)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                }

                if activeCategory == .modules {
                    ModuleSettingsView(workspace: workspace)
                        .environmentObject(appModel)
                }

                if activeCategory == .projects {
                GroupBox(appModel.t(.settingsProjects)) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(appModel.t(.settingsProjectsHelp))
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            Button {
                                appModel.beginCreatingResearchProject()
                            } label: {
                                Label(appModel.t(.toolbarNewProject), systemImage: "plus")
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
                                Button(appModel.t(.settingsEdit)) {
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

                if activeCategory == .library {
                GroupBox(appModel.t(.settingsLibrary)) {
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
                                Label(appModel.localized("Legacy raw/papers 迁移", "Legacy raw/papers"), systemImage: appModel.legacyPaperMigrationPlan.hasLegacyPapers ? "externaldrive.badge.exclamationmark" : "checkmark.circle")
                                    .fontWeight(.medium)
                                Spacer(minLength: 0)
                                if appModel.isLoadingLegacyPaperMigrationPlan {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Button {
                                    appModel.refreshLegacyPaperMigrationPlan()
                                } label: {
                                    Label(appModel.localized("刷新", "Refresh"), systemImage: "arrow.clockwise")
                                }
                                .controlSize(.small)
                                .help(Text(verbatim: appModel.localized("刷新 legacy 论文扫描", "Refresh the legacy paper scan")))

                                Button {
                                    isShowingLegacyMigrationConfirmation = true
                                } label: {
                                    Label(appModel.localized("复制可迁移项", "Copy Ready"), systemImage: "doc.on.doc")
                                }
                                .controlSize(.small)
                                .disabled(appModel.legacyPaperMigrationPlan.readyCount == 0 || appModel.isRunningLegacyPaperMigration)
                                .help(Text(verbatim: appModel.localized("把可迁移 legacy 论文复制到 library/papers，并写入迁移报告", "Copy ready legacy papers to library/papers and write a migration report")))
                            }

                            if appModel.isRunningLegacyPaperMigration {
                                ProgressView(appModel.localized("正在复制 legacy 论文...", "Copying legacy papers..."))
                                    .controlSize(.small)
                            }

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], alignment: .leading, spacing: 12) {
                                WorkspacePathRow(label: appModel.localized("Legacy 论文", "Legacy Papers"), value: "\(appModel.legacyPaperMigrationPlan.legacyPaperCount)")
                                WorkspacePathRow(label: appModel.localized("可复制", "Ready"), value: "\(appModel.legacyPaperMigrationPlan.readyCount)")
                                WorkspacePathRow(label: appModel.localized("冲突", "Conflicts"), value: "\(appModel.legacyPaperMigrationPlan.conflictCount)")
                                WorkspacePathRow(label: appModel.localized("目标", "Target"), value: Paper.globalLibraryRootRelativePath)
                            }

                            if appModel.legacyPaperMigrationPlan.items.isEmpty {
                                Label(appModel.localized("未检测到 legacy raw/papers 项。", "No legacy raw/papers items detected."), systemImage: "checkmark.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(Array(appModel.legacyPaperMigrationPlan.items.prefix(5))) { item in
                                        LegacyMigrationPlanRow(item: item)
                                    }

                                    if appModel.legacyPaperMigrationPlan.items.count > 5 {
                                        Text(appModel.localized("+\(appModel.legacyPaperMigrationPlan.items.count - 5) 项更多", "+\(appModel.legacyPaperMigrationPlan.items.count - 5) more"))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }

                            if let report = appModel.legacyPaperMigrationReport {
                                Label(appModel.localized("上次报告：复制 \(report.copiedCount)，跳过 \(report.skippedCount)，失败 \(report.failedCount)。\(report.reportRelativePath ?? "")", "Last report: copied \(report.copiedCount), skipped \(report.skippedCount), failed \(report.failedCount). \(report.reportRelativePath ?? "")"), systemImage: "doc.text")
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

                if activeCategory == .tasks {
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

                if activeCategory == .aiLab {
                    AIManagementDashboard(workspace: workspace, mode: .embedded)
                        .environmentObject(appModel)
                }

                if false && activeCategory == .aiLab {
                GroupBox("AI Lab Runtime") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Runtime", selection: Binding(
                            get: { appModel.workspacePreferences.agentRuntimeSelection },
                            set: { appModel.updateAgentRuntimeSelection($0) }
                        )) {
                            ForEach(AgentRuntimeSelection.allCases) { selection in
                                Text(selection.label).tag(selection)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 420)
                        Text("Swift Loop is the stable default. Sidecar and Auto are experimental runtime paths and fall back to Swift Loop when unavailable.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        WorkspacePathRow(label: "Mode", value: appModel.agentInteractionMode.title)
                        WorkspacePathRow(label: "Knowledge Papers", value: "\(appModel.agentKnowledgePaperSelectedCount) / \(appModel.agentKnowledgePaperTotalCount)")
                        WorkspacePathRow(label: "Effective Runtime", value: appModel.agentRuntimeEffectiveSummary)
                        WorkspacePathRow(label: "Health", value: appModel.agentSidecarHealthSummary)
                        WorkspacePathRow(label: "Fallback", value: appModel.agentRuntimeFallbackSummary)
                        WorkspacePathRow(label: "Agent Platform", value: appModel.agentPlatformSummary)
                        WorkspacePathRow(label: "Preset", value: appModel.agentPresetSummary)
                        WorkspacePathRow(label: "Permissions", value: appModel.agentPermissionSummary)
                        WorkspacePathRow(label: "Hooks", value: appModel.agentHookSummary)
                        WorkspacePathRow(label: "MCP", value: appModel.agentMCPStatusSummary)
                        WorkspacePathRow(label: "Debug Logging", value: appModel.agentDebugLoggingSummary)

                        Toggle("Debug mode", isOn: Binding(
                            get: { appModel.workspacePreferences.agentDebugLoggingEnabled },
                            set: { appModel.setAgentDebugLoggingEnabled($0) }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)

                        HStack(spacing: 8) {
                            Button {
                                appModel.restartAgentSidecar()
                            } label: {
                                Label("Restart", systemImage: "arrow.clockwise")
                            }
                            Button {
                                appModel.openAgentRunDirectory()
                            } label: {
                                Label("Runs", systemImage: "folder")
                            }
                            Button {
                                appModel.exportAgentDebugBundle()
                            } label: {
                                Label("Debug", systemImage: "shippingbox")
                            }
                            Button {
                                appModel.openAgentDebugLogDirectory()
                            } label: {
                                Label("Logs", systemImage: "doc.text.magnifyingglass")
                            }
                            Button {
                                appModel.exportDiagnosticsReport()
                            } label: {
                                Label(appModel.localized("诊断包", "Diagnostics"), systemImage: "stethoscope")
                            }
                            .help(appModel.localized(
                                "导出脱敏诊断包（不含绝对路径与密钥），便于反馈问题。",
                                "Export a scrubbed diagnostics file (no absolute paths or secrets) for bug reports."
                            ))
                            Button(role: .destructive) {
                                appModel.disableSidecarForWorkspace()
                            } label: {
                                Label("Disable", systemImage: "power")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Prompt Library") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Workspace overrides are stored in .sci-station/agent/profile.json and applied to planner, tool loop, and paper summary prompts.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Button {
                                appModel.createAgentPromptTemplate()
                            } label: {
                                Label("New", systemImage: "plus")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(appModel.agentPromptResolutionSummaries, id: \.self) { summary in
                                Text(summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }

                        if appModel.agentWorkspaceProfile.promptTemplates.isEmpty {
                            Text("No prompt templates configured.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(appModel.agentWorkspaceProfile.promptTemplates) { template in
                                let draft = promptDraft(for: template)
                                let review = promptReview(for: draft)
                                let proposalState = promptProposalStates[template.id] ?? .preview
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            TextField("Title", text: Binding(
                                                get: { draft.title },
                                                set: { newValue in
                                                    updatePromptDraft(template.id) { $0.title = newValue }
                                                }
                                            ))
                                            .textFieldStyle(.roundedBorder)

                                            Text("\(draft.surface.rawValue) · \(draft.id) · v\(draft.version)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 0)
                                        Toggle(isOn: Binding(
                                            get: { template.isEnabled },
                                            set: { appModel.setAgentPromptTemplateEnabled(id: template.id, isEnabled: $0) }
                                        )) {
                                            EmptyView()
                                        }
                                        .labelsHidden()
                                        .toggleStyle(.switch)

                                        Button {
                                            appModel.setActiveAgentPromptTemplate(id: template.id)
                                        } label: {
                                            Label("Use", systemImage: "checkmark.circle")
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)

                                        Button {
                                            appModel.restoreDefaultAgentPromptTemplate(id: template.id)
                                            promptDrafts.removeValue(forKey: template.id)
                                            promptProposalStates.removeValue(forKey: template.id)
                                        } label: {
                                            Label("Restore Default", systemImage: "arrow.counterclockwise")
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)

                                        Button {
                                            appModel.copyAgentPromptTemplateBody(id: template.id)
                                        } label: {
                                            Label("Copy Body", systemImage: "doc.on.doc")
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }

                                    TextField("Description", text: Binding(
                                        get: { draft.description },
                                        set: { newValue in
                                            updatePromptDraft(template.id) { $0.description = newValue }
                                        }
                                    ))
                                    .textFieldStyle(.roundedBorder)

                                    TextEditor(text: Binding(
                                        get: { draft.promptTemplate },
                                        set: { newValue in
                                            updatePromptDraft(template.id) { $0.promptTemplate = newValue }
                                        }
                                    ))
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(minHeight: 120)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.secondary.opacity(0.16))
                                    )

                                    if !review.diffPreview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack(spacing: 8) {
                                            Text("Patch Proposal · \(proposalState.rawValue.capitalized)")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                            if !review.canAccept {
                                                Label("Needs review", systemImage: "exclamationmark.triangle")
                                                        .font(.caption2)
                                                    .foregroundStyle(.orange)
                                            }
                                        }

                                            VStack(alignment: .leading, spacing: 3) {
                                                Label(review.rationale, systemImage: "sparkles")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                    .fixedSize(horizontal: false, vertical: true)
                                                if let sourceSummary = review.sourceSummary {
                                                    Label(sourceSummary, systemImage: "info.circle")
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                        .fixedSize(horizontal: false, vertical: true)
                                                }
                                            }

                                            ScrollView {
                                                Text(review.diffPreview)
                                                    .font(.system(.caption, design: .monospaced))
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                    .textSelection(.enabled)
                                            }
                                            .frame(maxHeight: 160)
                                            .padding(8)
                                            .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))

                                            if !review.impactScope.isEmpty {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text("Impact Scope")
                                                        .font(.caption.weight(.semibold))
                                                        .foregroundStyle(.secondary)
                                                    ForEach(review.impactScope, id: \.self) { item in
                                                        Label(item, systemImage: "scope")
                                                            .font(.caption2)
                                                            .foregroundStyle(.secondary)
                                                    }
                                                }
                                            }

                                            if let rollbackHint = review.rollbackHint {
                                                Label(rollbackHint.summary, systemImage: "arrow.uturn.backward.circle")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }

                                            if let validationMessage = review.validationMessage {
                                                Label(validationMessage, systemImage: "xmark.octagon")
                                                    .font(.caption)
                                                    .foregroundStyle(.red)
                                            }
                                            if let activeSurfaceMismatch = review.activeSurfaceMismatch {
                                                Label(activeSurfaceMismatch, systemImage: "rectangle.2.swap")
                                                    .font(.caption)
                                                    .foregroundStyle(.orange)
                                            }
                                        }
                                    }

                                    HStack(spacing: 8) {
                                        Button {
                                            promptProposalStates[template.id] = .preview
                                        } label: {
                                            Label("Preview", systemImage: "doc.text.magnifyingglass")
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)

                                        Button {
                                            let proposalReview = aiPromptPatchReview(for: draft)
                                            promptDrafts[template.id] = proposalReview.proposal.draft(isEnabled: draft.isEnabled)
                                            promptProposalStates[template.id] = .preview
                                        } label: {
                                            Label("AI Suggest", systemImage: "sparkles")
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)

                                        Button {
                                            pendingPromptPatchReview = review
                                        } label: {
                                            Label("Accept", systemImage: "checkmark.circle")
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.small)
                                        .disabled(!review.canAccept || !promptDraftHasChanges(template))

                                        Button {
                                            promptProposalStates[template.id] = .rejected
                                        } label: {
                                            Label("Reject", systemImage: "xmark.circle")
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                        .disabled(!promptDraftHasChanges(template))

                                        Button {
                                            promptDrafts[template.id] = template
                                            promptProposalStates[template.id] = .discarded
                                        } label: {
                                            Label("Discard", systemImage: "arrow.uturn.backward")
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                        .disabled(!promptDraftHasChanges(template))

                                        Button(role: .destructive) {
                                            appModel.removeAgentPromptTemplate(id: template.id)
                                            promptDrafts.removeValue(forKey: template.id)
                                            promptProposalStates.removeValue(forKey: template.id)
                                        } label: {
                                            Label("Remove", systemImage: "trash")
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }
                                }
                                .padding(10)
                                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Skill Manager") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Enable skills from the resolved catalog. Workspace skills remain blocked until explicitly trusted; runtime gating still decides whether matching skills load for a prompt.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Button {
                                appModel.chooseAgentSkillMarkdownForImport()
                            } label: {
                                Label("Import", systemImage: "square.and.arrow.down")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            Button {
                                refreshSkillCatalog()
                            } label: {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        TextField("Search skills, sources, capabilities…", text: $skillCatalogSearchText)
                            .textFieldStyle(.roundedBorder)

                        if let skillCatalogStatusMessage {
                            Text(skillCatalogStatusMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if filteredSkillCatalogEntries.isEmpty {
                            Text(skillCatalogEntries.isEmpty ? "No skills found in configured search roots." : "No skills match the current search.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(filteredSkillCatalogEntries) { entry in
                                AgentSkillCatalogEntryRow(
                                    entry: entry,
                                    setEnabled: { pendingSkillToggleReview = AgentSkillToggleReview(entry: entry, action: .setEnabled($0)) },
                                    setTrusted: { pendingSkillToggleReview = AgentSkillToggleReview(entry: entry, action: .setTrusted($0)) }
                                )
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onAppear {
                        refreshSkillCatalog()
                    }
                }

                .confirmationDialog(
                    "Import skill into workspace-managed root?",
                    isPresented: $appModel.isShowingSkillImport,
                    titleVisibility: .visible
                ) {
                    if appModel.pendingSkillImportPlan != nil {
                        Button("Import Skill", role: .destructive) {
                            appModel.confirmAgentSkillImport()
                        }
                        Button("Cancel", role: .cancel) {
                            appModel.isShowingSkillImport = false
                        }
                    }
                } message: {
                    if let plan = appModel.pendingSkillImportPlan {
                        Text("This will copy \(plan.sourceSkillURL.lastPathComponent) into \(plan.destinationRootRelativePath) and record the skill toggle in \(AgentWorkspaceProfileRepository.relativePath). Workspace skills remain untrusted until you explicitly trust them.")
                    }
                }
                .confirmationDialog(
                    pendingSkillToggleReview?.action.title ?? "Update skill?",
                    isPresented: Binding(
                        get: { pendingSkillToggleReview != nil },
                        set: { if !$0 { pendingSkillToggleReview = nil } }
                    ),
                    titleVisibility: .visible
                ) {
                    if let review = pendingSkillToggleReview {
                        Button(review.action.buttonTitle, role: .destructive) {
                            applySkillToggleReview(review)
                            pendingSkillToggleReview = nil
                        }
                        Button("Cancel", role: .cancel) {
                            pendingSkillToggleReview = nil
                        }
                    }
                } message: {
                    if let review = pendingSkillToggleReview {
                        Text(skillToggleConfirmationMessage(review))
                    }
                }

                GroupBox("AI Lab Tool Budget") {
                    VStack(alignment: .leading, spacing: 10) {
                        Grid(horizontalSpacing: 12, verticalSpacing: 8) {
                            GridRow {
                                Text("Max Steps").frame(width: 170, alignment: .leading)
                                TextField("Max Steps", value: agentLoopBudgetBinding(
                                    get: { $0.maxSteps },
                                    set: { budget, value in budget.maxSteps = max(1, value) }
                                ), format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)

                                Text("Max Tool Calls").frame(width: 170, alignment: .leading)
                                TextField("Max Tool Calls", value: agentLoopBudgetBinding(
                                    get: { $0.maxToolCalls },
                                    set: { budget, value in budget.maxToolCalls = max(1, value) }
                                ), format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                            }

                            GridRow {
                                Text("Context Characters").frame(width: 170, alignment: .leading)
                                TextField("Context Characters", value: agentLoopBudgetBinding(
                                    get: { $0.maxContextCharacters },
                                    set: { budget, value in budget.maxContextCharacters = max(1_000, value) }
                                ), format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)

                                Text("Accumulated Tool Text").frame(width: 170, alignment: .leading)
                                TextField("Accumulated Tool Text", value: agentLoopBudgetBinding(
                                    get: { $0.maxAccumulatedToolResultCharacters },
                                    set: { budget, value in budget.maxAccumulatedToolResultCharacters = max(1_000, value) }
                                ), format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                            }

                            GridRow {
                                Text("Per Tool Output").frame(width: 170, alignment: .leading)
                                TextField("Per Tool Output", value: agentLoopBudgetBinding(
                                    get: { $0.maxToolResultCharactersPerCall },
                                    set: { budget, value in budget.maxToolResultCharactersPerCall = max(1_000, value) }
                                ), format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)

                                Toggle("Native Tools", isOn: agentLoopBudgetBoolBinding(
                                    get: { $0.allowProviderNativeTools },
                                    set: { budget, value in budget.allowProviderNativeTools = value }
                                ))
                                .toggleStyle(.switch)
                                .controlSize(.small)
                            }
                        }

                        HStack(spacing: 8) {
                            Toggle("Auto-approve read-only tools", isOn: agentLoopBudgetBoolBinding(
                                get: { $0.autoApproveReadOnly },
                                set: { budget, value in budget.autoApproveReadOnly = value }
                            ))
                            .toggleStyle(.switch)
                            .controlSize(.small)

                            Button {
                                appModel.resetAgentLoopBudget()
                            } label: {
                                Label("Reset", systemImage: "arrow.counterclockwise")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox(appModel.localized("检索索引", "Retrieval Index")) {
                    VStack(alignment: .leading, spacing: 10) {
                        WorkspacePathRow(label: appModel.localized("状态", "Status"), value: appModel.agentRetrievalIndexSummary)
                        WorkspacePathRow(label: appModel.localized("存储", "Store"), value: appModel.agentRetrievalStoreSummary)
                        WorkspacePathRow(label: appModel.localized("模型", "Model"), value: appModel.agentRetrievalModelSummary)
                        WorkspacePathRow(label: appModel.localized("索引", "Index"), value: appModel.agentRetrievalIndexStatus.indexRelativePath)

                        if let hint = appModel.agentRetrievalZeroChunkHint {
                            Text(hint)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        WorkspacePathRow(label: appModel.localized("paper.md 检查", "paper.md Check"), value: appModel.paperMarkdownQualitySummary)
                        ForEach(appModel.paperMarkdownQualityIssueLines.prefix(4), id: \.self) { line in
                            Text(line)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        HStack(spacing: 8) {
                            Button {
                                appModel.rebuildAgentRetrievalSelectedSource()
                            } label: {
                                Label(appModel.localized("重建来源", "Rebuild Source"), systemImage: "doc.badge.gearshape")
                            }
                            Button {
                                appModel.rebuildAgentRetrievalCurrentProject()
                            } label: {
                                Label(appModel.localized("重建项目", "Rebuild Project"), systemImage: "arrow.triangle.2.circlepath")
                            }
                            Button {
                                appModel.checkSelectedPaperMarkdownQuality()
                            } label: {
                                Label(appModel.localized("检查 paper.md", "Check paper.md"), systemImage: "checklist")
                            }
                            Button {
                                appModel.openAgentRetrievalIndexDirectory()
                            } label: {
                                Label(appModel.localized("打开索引", "Open Index"), systemImage: "folder")
                            }
                            Button {
                                appModel.copyAgentRetrievalDiagnostic()
                            } label: {
                                Label(appModel.localized("复制诊断", "Copy Diagnostic"), systemImage: "doc.on.doc")
                            }
                            if appModel.agentRetrievalIndexStatus.status == .indexing || appModel.isCheckingPaperMarkdownQuality {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
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
                        Text("Tool availability is filtered by the current mode and this allowlist. Read-only tools may run automatically in Conversation and Assistant modes; writes, network actions, and side effects still pause for approval.")
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

                if activeCategory == .developer {
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
        .onAppear {
            syncDrafts()
            refreshSkillCatalog()
        }
        .onChange(of: workspace.rootURL) { _, _ in
            syncDrafts()
            refreshSkillCatalog()
        }
        .onChange(of: appModel.agentWorkspaceProfile) { _, _ in
            promptDrafts = promptDraftMap(from: appModel.agentWorkspaceProfile.promptTemplates)
            promptProposalStates = [:]
            refreshSkillCatalog()
        }
        .confirmationDialog(
            appModel.localized("复制可迁移 legacy 论文到 library/papers？", "Copy ready legacy papers to library/papers?"),
            isPresented: $isShowingLegacyMigrationConfirmation,
            titleVisibility: .visible
        ) {
            Button(appModel.localized("复制可迁移论文", "Copy Ready Papers")) {
                appModel.copyReadyLegacyPapers()
            }
            Button(appModel.localized("取消", "Cancel"), role: .cancel) {}
        } message: {
            Text(appModel.localized("Sci-Station 会把可迁移 raw/papers 项复制到 library/papers，跳过冲突，保留原始 raw/papers 文件，并写入 JSON 迁移报告。", "Sci-Station will copy ready raw/papers items into library/papers, skip conflicts, keep the original raw/papers files in place, and write a JSON migration report."))
        }
        .confirmationDialog(
            "Apply AI prompt patch?",
            isPresented: Binding(
                get: { pendingPromptPatchReview != nil },
                set: { if !$0 { pendingPromptPatchReview = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let review = pendingPromptPatchReview {
                Button("Apply Patch", role: .destructive) {
                    promptProposalStates[review.proposal.templateID] = .accepted
                    promptDrafts.removeValue(forKey: review.proposal.templateID)
                    appModel.acceptAgentPromptPatchProposal(review.proposal)
                    pendingPromptPatchReview = nil
                }
                Button("Reject Patch") {
                    promptProposalStates[review.proposal.templateID] = .rejected
                    pendingPromptPatchReview = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingPromptPatchReview = nil
            }
        } message: {
            if let review = pendingPromptPatchReview {
                Text(promptPatchConfirmationMessage(review))
            }
        }
    }

    private func syncDrafts() {
        workspaceName = workspace.displayName
        defaultFolderPath = appModel.workspacePreferences.defaultCollectionPath ?? ""
        promptDrafts = promptDraftMap(from: appModel.agentWorkspaceProfile.promptTemplates)
        promptProposalStates = [:]
    }

    private func promptDraftMap(
        from templates: [AgentPromptTemplateOverride]
    ) -> [String: AgentPromptTemplateOverride] {
        var drafts: [String: AgentPromptTemplateOverride] = [:]
        for template in templates {
            drafts[template.id] = template
        }
        return drafts
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

    private func promptDraft(for template: AgentPromptTemplateOverride) -> AgentPromptTemplateOverride {
        promptDrafts[template.id] ?? template
    }

    private func updatePromptDraft(_ id: String, mutate: (inout AgentPromptTemplateOverride) -> Void) {
        guard var draft = promptDrafts[id] ?? appModel.agentWorkspaceProfile.promptTemplate(id: id) else {
            return
        }
        mutate(&draft)
        promptDrafts[id] = draft
        promptProposalStates[id] = .preview
    }

    private func promptDraftHasChanges(_ template: AgentPromptTemplateOverride) -> Bool {
        promptDraft(for: template) != template
    }

    private func promptReview(for draft: AgentPromptTemplateOverride) -> AgentPromptPatchReview {
        let proposal = AgentPromptPatchProposal(
            templateID: draft.id,
            title: draft.title,
            version: draft.version,
            description: draft.description,
            surface: draft.surface,
            systemPrompt: draft.systemPrompt,
            promptTemplate: draft.promptTemplate,
            proposedBy: "settings",
            rationale: "Settings editor draft converted into an explicit patch proposal.",
            sourceSummary: "User-edited Settings draft; diff preview is read-only until confirmed."
        )
        return promptLibraryResolver.reviewPatchProposal(proposal, profile: appModel.agentWorkspaceProfile)
    }

    private func aiPromptPatchReview(for draft: AgentPromptTemplateOverride) -> AgentPromptPatchReview {
        let proposedBody = aiSuggestedPromptBody(from: draft)
        let proposal = AgentPromptPatchProposal(
            templateID: draft.id,
            title: nonEmpty(draft.title) ?? "AI Suggested Prompt",
            version: nextPatchVersion(from: draft.version),
            description: nonEmpty(draft.description) ?? "AI-suggested patch for auditable agent behavior.",
            surface: draft.surface,
            systemPrompt: draft.systemPrompt,
            promptTemplate: proposedBody,
            proposedBy: "assistant",
            rationale: "Adds explicit evidence, approval, and writeback constraints so future \(draft.surface.rawValue) runs are easier to audit and roll back.",
            sourceSummary: "Generated from the current workspace prompt draft; no workspace file is written until Apply Patch is confirmed."
        )
        return promptLibraryResolver.reviewPatchProposal(proposal, profile: appModel.agentWorkspaceProfile)
    }

    private func promptPatchConfirmationMessage(_ review: AgentPromptPatchReview) -> String {
        let scope = review.impactScope.isEmpty ? "" : "\n\nImpact:\n- " + review.impactScope.joined(separator: "\n- ")
        let rollback = review.rollbackHint.map { "\n\nRollback: \($0.summary)" } ?? ""
        let rationale = "\n\nRationale: \(review.rationale)"
        let source = review.sourceSummary.map { "\nSource: \($0)" } ?? ""
        return "This will write the proposed prompt patch to \(AgentWorkspaceProfileRepository.relativePath). Diff preview is read-only until you apply this confirmation.\(rationale)\(source)\(scope)\(rollback)"
    }

    private func aiSuggestedPromptBody(from draft: AgentPromptTemplateOverride) -> String {
        var lines = draft.promptTemplate
            .nilIfEmptyAfterTrimming
            .map { $0.components(separatedBy: .newlines) } ?? []
        let additions = [
            "Before using evidence in an answer, distinguish workspace evidence from synthetic/test fixtures.",
            "For writeback actions, state the target path, risk, and approval requirement before requesting execution.",
            "If runtime fallback occurs, explain the requested runtime, effective runtime, and fallback reason in the user-visible summary."
        ]
        for addition in additions where !lines.contains(where: { $0.localizedCaseInsensitiveContains(addition) }) {
            lines.append(addition)
        }
        return lines.joined(separator: "\n")
    }

    private func nonEmpty(_ text: String) -> String? {
        text.nilIfEmptyAfterTrimming
    }

    private func nextPatchVersion(from version: String) -> String {
        var components = version.split(separator: ".").compactMap { Int($0) }
        guard !components.isEmpty else {
            return "0.1.0"
        }
        while components.count < 3 {
            components.append(0)
        }
        components[2] += 1
        return components.prefix(3).map(String.init).joined(separator: ".")
    }

    private var filteredSkillCatalogEntries: [AgentSkillCatalogEntry] {
        skillLoader.filterCatalog(skillCatalogEntries, query: skillCatalogSearchText)
    }

    private func refreshSkillCatalog() {
        let refreshID = UUID()
        skillCatalogRefreshID = refreshID
        Task {
            do {
                let entries = try await skillLoader.catalog(
                    profile: appModel.agentWorkspaceProfile,
                    workspaceRoot: workspace.rootURL,
                    prompt: appModel.agentGoal
                )
                await MainActor.run {
                    guard skillCatalogRefreshID == refreshID else { return }
                    skillCatalogEntries = entries
                    skillCatalogStatusMessage = entries.isEmpty ? "No skills discovered in configured search roots." : "\(entries.count) skills discovered."
                }
            } catch {
                await MainActor.run {
                    guard skillCatalogRefreshID == refreshID else { return }
                    skillCatalogEntries = []
                    skillCatalogStatusMessage = "Skill catalog unavailable: \(error.localizedDescription)"
                }
            }
        }
    }

    private func setSkill(_ entry: AgentSkillCatalogEntry, isEnabled: Bool) {
        appModel.updateAgentWorkspaceProfile { profile in
            let toggle = AgentSkillToggle(
                skillID: entry.id,
                displayName: entry.metadata.name,
                isEnabled: isEnabled,
                trustLevel: entry.toggle?.trustLevel ?? (entry.metadata.trustLevel == .trusted ? .trusted : .untrusted),
                allowedToolIDs: entry.toggle?.allowedToolIDs ?? []
            )
            if let index = profile.skillToggles.firstIndex(where: { $0.skillID == entry.id }) {
                profile.skillToggles[index] = toggle
            } else {
                profile.skillToggles.append(toggle)
            }
        }
        refreshSkillCatalog()
    }

    private func setSkill(_ entry: AgentSkillCatalogEntry, isTrusted: Bool) {
        appModel.updateAgentWorkspaceProfile { profile in
            let toggle = AgentSkillToggle(
                skillID: entry.id,
                displayName: entry.metadata.name,
                isEnabled: entry.isEnabled,
                trustLevel: isTrusted ? .trusted : .untrusted,
                allowedToolIDs: entry.toggle?.allowedToolIDs ?? []
            )
            if let index = profile.skillToggles.firstIndex(where: { $0.skillID == entry.id }) {
                profile.skillToggles[index] = toggle
            } else {
                profile.skillToggles.append(toggle)
            }
        }
        refreshSkillCatalog()
    }

    private func applySkillToggleReview(_ review: AgentSkillToggleReview) {
        switch review.action {
        case let .setEnabled(isEnabled):
            setSkill(review.entry, isEnabled: isEnabled)
        case let .setTrusted(isTrusted):
            setSkill(review.entry, isTrusted: isTrusted)
        }
    }

    private func skillToggleConfirmationMessage(_ review: AgentSkillToggleReview) -> String {
        let entry = review.entry
        let tools = entry.effectiveAllowedTools.isEmpty ? "none declared" : entry.effectiveAllowedTools.joined(separator: ", ")
        let base = [
            "Skill: \(entry.metadata.name)",
            "Source: \(entry.metadata.source.rawValue)",
            "Risk: \(entry.metadata.risk.rawValue)",
            "Allowed tools: \(tools)",
            "Profile write: \(AgentWorkspaceProfileRepository.relativePath)"
        ].joined(separator: "\n")

        switch review.action {
        case let .setEnabled(isEnabled):
            if isEnabled, entry.metadata.trustLevel == .untrusted, entry.toggle?.trustLevel != .trusted {
                return "\(base)\n\nThis enables the skill toggle, but runtime loading remains blocked until you explicitly trust the workspace skill."
            }
            return "\(base)\n\nThis updates the enabled state. Runtime gating and tool allowlists still apply."
        case let .setTrusted(isTrusted):
            return isTrusted
                ? "\(base)\n\nTrusting a workspace/user skill allows it to contribute prompt instructions when enabled and matched. It does not bypass tool permissions."
                : "\(base)\n\nRemoving trust keeps the skill visible but blocks runtime loading until trust is restored."
        }
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

    private func agentLoopBudgetBinding(
        get: @escaping (AgentLoopOptions) -> Int,
        set: @escaping (inout AgentLoopOptions, Int) -> Void
    ) -> Binding<Int> {
        Binding(
            get: { get(appModel.workspacePreferences.agentLoopBudget) },
            set: { newValue in
                appModel.updateAgentLoopBudget { budget in
                    set(&budget, newValue)
                }
            }
        )
    }

    private func agentLoopBudgetBoolBinding(
        get: @escaping (AgentLoopOptions) -> Bool,
        set: @escaping (inout AgentLoopOptions, Bool) -> Void
    ) -> Binding<Bool> {
        Binding(
            get: { get(appModel.workspacePreferences.agentLoopBudget) },
            set: { newValue in
                appModel.updateAgentLoopBudget { budget in
                    set(&budget, newValue)
                }
            }
        )
    }

}

private struct AgentSkillCatalogEntryRow: View {
    let entry: AgentSkillCatalogEntry
    let setEnabled: (Bool) -> Void
    let setTrusted: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Toggle(isOn: Binding(
                    get: { entry.isEnabled },
                    set: setEnabled
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(entry.metadata.name)
                                .fontWeight(.medium)
                            Text(entry.metadata.source.rawValue)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(entry.metadata.risk.rawValue)
                                .font(.caption2)
                                .foregroundStyle(entry.metadata.risk == .readOnly ? Color.secondary : Color.orange)
                        }
                        Text(entry.metadata.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.checkbox)

                Spacer(minLength: 0)

                if entry.metadata.trustLevel == .untrusted {
                    Toggle("Trusted", isOn: Binding(
                        get: { entry.toggle?.trustLevel == .trusted },
                        set: setTrusted
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help(Text(verbatim: "Workspace/user-authored skills require explicit trust before runtime loading."))
                } else {
                    Label("Trusted source", systemImage: "checkmark.seal")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], alignment: .leading, spacing: 6) {
                WorkspacePathRow(label: "Status", value: entry.statusLabel)
                WorkspacePathRow(label: "Version", value: entry.metadata.version)
                WorkspacePathRow(label: "Author", value: entry.metadata.author)
                WorkspacePathRow(label: "Allowed Tools", value: entry.effectiveAllowedTools.isEmpty ? "none declared" : entry.effectiveAllowedTools.joined(separator: ", "))
            }

            if !entry.metadata.capabilities.isEmpty {
                Text("Capabilities: \(entry.metadata.capabilities.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let blockedReason = entry.blockedReason {
                Label(blockedReason, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(entry.metadata.skillFileURL.path)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}

enum SettingsCategory: String, CaseIterable, Identifiable {
    case workspace
    case modules
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
        case .modules:
            return "Modules"
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
        case .modules:
            return "Enable, pin, repair, and override built-in workspace modules."
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

    func title(appModel: AppViewModel) -> String {
        switch self {
        case .workspace:
            return appModel.t(.toolbarWorkspace)
        case .modules:
            return appModel.t(.settingsModules)
        case .projects:
            return appModel.t(.settingsProjects)
        case .library:
            return appModel.t(.settingsLibrary)
        case .tasks:
            return appModel.t(.settingsTasks)
        case .aiLab:
            return appModel.t(.settingsAILab)
        case .developer:
            return appModel.t(.settingsDeveloper)
        }
    }

    func summary(appModel: AppViewModel) -> String {
        switch self {
        case .workspace:
            return appModel.t(.settingsWorkspaceSummary)
        case .modules:
            return appModel.t(.settingsModulesSummary)
        case .projects:
            return appModel.t(.settingsProjectsHelp)
        case .library:
            return appModel.t(.settingsLibrarySummary)
        case .tasks:
            return appModel.t(.settingsTasksSummary)
        case .aiLab:
            return appModel.t(.settingsAILabSummary)
        case .developer:
            return appModel.t(.settingsDeveloperSummary)
        }
    }

    var systemImage: String {
        switch self {
        case .workspace:
            return "externaldrive"
        case .modules:
            return "switch.2"
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
    @EnvironmentObject private var appModel: AppViewModel

    @Binding var selection: SettingsCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(appModel.t(.routeSettings))
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
                        Text(category.title(appModel: appModel))
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
    @EnvironmentObject private var appModel: AppViewModel
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
                    Text(statusLabel)
                        .font(.caption2)
                        .foregroundStyle(item.hasConflicts ? Color.orange : Color.secondary)
                }
                Text("\(item.sourceRelativePath) -> \(item.targetRelativePath)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if !item.conflicts.isEmpty {
                    Text(item.conflicts.map(conflictLabel).joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var statusLabel: String {
        switch item.status {
        case .readyToCopy:
            return appModel.localized("可复制", "Ready to copy")
        case .conflict:
            return appModel.localized("冲突", "Conflict")
        }
    }

    private func conflictLabel(_ conflict: LegacyPaperMigrationConflict) -> String {
        switch conflict {
        case .targetDirectoryExists:
            return appModel.localized("目标已存在", "Target exists")
        case .duplicatePaperIDInGlobalLibrary:
            return appModel.localized("全局库重复", "Global duplicate")
        case .duplicatePaperIDInLegacyLibrary:
            return appModel.localized("Legacy 库重复", "Legacy duplicate")
        }
    }
}

struct SettingsSceneView: View {
    @EnvironmentObject private var appModel: AppViewModel

    var body: some View {
        Group {
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
        .sheet(isPresented: $appModel.isShowingWorkspaceCreationWizard) {
            WorkspaceCreationWizardView()
                .environmentObject(appModel)
        }
    }
}

struct AIManagementPanelView: View {
    @EnvironmentObject private var appModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    let workspace: ResearchWorkspace?

    var body: some View {
        Group {
            if let workspace {
                AIManagementDashboard(workspace: workspace, mode: .sheet(dismiss))
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    Label(appModel.localized("需要先打开研究根目录", "Open a research root first"), systemImage: "externaldrive.badge.plus")
                        .font(.title3.weight(.semibold))
                    Text(appModel.localized("AI 管理项绑定到当前工作区。打开或创建一个研究根目录后即可配置模型、运行时、工具、MCP 和检索索引。", "AI management is workspace-scoped. Open or create a research root to configure models, runtime, tools, MCP, and retrieval indexing."))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 12) {
                        Button(appModel.t(.settingsCreateRoot), action: appModel.createWorkspace)
                            .buttonStyle(.borderedProminent)
                        Button(appModel.t(.settingsOpenRoot), action: appModel.openWorkspace)
                            .buttonStyle(.bordered)
                        Button(appModel.localized("关闭", "Close")) {
                            dismiss()
                        }
                            .buttonStyle(.bordered)
                    }
                }
                .padding(24)
                .frame(width: 520, alignment: .topLeading)
            }
        }
        .frame(minWidth: 760, minHeight: 560)
    }
}

struct AIManagementDashboard: View {
    @EnvironmentObject private var appModel: AppViewModel

    enum Mode {
        case sheet(DismissAction)
        case embedded

        var isSheet: Bool {
            if case .sheet = self {
                return true
            }
            return false
        }
    }

    let workspace: ResearchWorkspace
    let mode: Mode
    @State private var availableWidth: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            if mode.isSheet {
                header
                Divider()
            }

            if mode.isSheet {
                ScrollView {
                    dashboardContent(width: availableWidth)
                        .padding(22)
                }
            } else {
                dashboardContent(width: availableWidth)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            availableWidth = width
        }
    }

    private func dashboardContent(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            statusStrip

            LazyVGrid(columns: dashboardColumns(for: width), alignment: .leading, spacing: 16) {
                providerSection.frame(minHeight: 220, alignment: .top)
                runtimeSection.frame(minHeight: 220, alignment: .top)
                sessionSection.frame(minHeight: 190, alignment: .top)
                knowledgeSection.frame(minHeight: 180, alignment: .top)
                toolsSection.frame(minHeight: 310, alignment: .top)
                promptSection.frame(minHeight: 310, alignment: .top)
                skillSection.frame(minHeight: 310, alignment: .top)
                mcpSection.frame(minHeight: 310, alignment: .top)
                retrievalSection.frame(minHeight: 180, alignment: .top)
                advancedSection.frame(minHeight: 128, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func dashboardColumns(for width: CGFloat) -> [GridItem] {
        if width < 900 {
            return [GridItem(.flexible(minimum: 0), spacing: 16)]
        }
        return [
            GridItem(.flexible(minimum: 0), spacing: 16),
            GridItem(.flexible(minimum: 0), spacing: 16)
        ]
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(appModel.localized("AI 管理", "AI Management"))
                    .font(.title2.weight(.semibold))
                Text(workspace.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button {
                appModel.showAgentKnowledgeLibrary()
            } label: {
                Label(appModel.localized("知识库", "Knowledge"), systemImage: "books.vertical")
            }
            .help(appModel.localized("管理 AI 可读取的论文", "Manage papers available to AI"))

            if case let .sheet(dismiss) = mode {
                Button {
                    dismiss()
                } label: {
                    Label(appModel.localized("完成", "Done"), systemImage: "checkmark")
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private var statusStrip: some View {
        HStack(spacing: 10) {
            AIManagementStatusChip(
                systemImage: runtimeIcon,
                title: appModel.agentRuntimeEffectiveSummary,
                tint: appModel.agentRuntimeEffectiveSummary == "Swift Loop" ? .secondary : .green,
                help: appModel.agentRuntimeFallbackSummary
            )
            AIManagementStatusChip(
                systemImage: "cpu",
                title: appModel.llmConfiguration.model,
                tint: .blue,
                help: appModel.llmConfiguration.baseURLString
            )
            AIManagementStatusChip(
                systemImage: "books.vertical",
                title: "\(appModel.agentKnowledgePaperSelectedCount)/\(appModel.agentKnowledgePaperTotalCount)",
                tint: .purple,
                help: appModel.localized("知识库论文", "Knowledge papers")
            )
            AIManagementStatusChip(
                systemImage: "wrench.and.screwdriver",
                title: "\(appModel.agentEnabledToolNames.count)/\(appModel.agentToolDefinitions.count)",
                tint: appModel.agentEnabledToolNames.isEmpty && !appModel.agentToolDefinitions.isEmpty ? .orange : .secondary,
                help: appModel.localized("启用工具 / 全部工具", "Enabled tools / all tools")
            )
            AIManagementStatusChip(
                systemImage: "point.3.connected.trianglepath.dotted",
                title: "\(appModel.agentRetrievalIndexStatus.chunkCount)",
                tint: appModel.agentRetrievalIndexStatus.status == .ready ? .green : .orange,
                help: appModel.agentRetrievalIndexSummary
            )

            Spacer(minLength: 0)
        }
    }

    private var providerSection: some View {
        AIManagementSection(title: appModel.localized("模型", "Model"), systemImage: "cpu") {
            HStack(spacing: 10) {
                Picker("DeepSeek", selection: Binding(
                    get: { appModel.llmConfiguration.model },
                    set: { appModel.useDeepSeekDefaults(model: $0) }
                )) {
                    ForEach(DeepSeekModelOption.presets) { option in
                        Text(option.title).tag(option.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 230)

                Button {
                    appModel.useDeepSeekDefaults()
                } label: {
                    Label("DeepSeek", systemImage: "wand.and.sparkles")
                        .labelStyle(.iconOnly)
                }
                .help("Apply DeepSeek defaults")

                Spacer(minLength: 0)

                Image(systemName: appModel.llmConnectionStatusMessage?.localizedCaseInsensitiveContains("OK") == true ? "checkmark.circle.fill" : "key.horizontal")
                    .foregroundStyle(appModel.llmConnectionStatusMessage?.localizedCaseInsensitiveContains("OK") == true ? Color.green : Color.secondary)
                    .help(appModel.llmConnectionStatusMessage ?? "Provider credentials")
            }

            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Label("URL", systemImage: "link")
                        .frame(width: 78, alignment: .leading)
                    TextField("Base URL", text: llmBinding(
                        get: { $0.baseURLString },
                        set: { $0.baseURLString = $1 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }

                GridRow {
                    Label("ID", systemImage: "number")
                        .frame(width: 78, alignment: .leading)
                    TextField("Model", text: llmBinding(
                        get: { $0.model },
                        set: { $0.model = $1 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }

                GridRow {
                    Label("Key", systemImage: "key")
                        .frame(width: 78, alignment: .leading)
                    SecureField(appModel.localized("留空保留已保存 Key", "Leave blank to keep saved key"), text: $appModel.llmAPIKey)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack(spacing: 10) {
                Label("Temp", systemImage: "thermometer.medium")
                    .frame(width: 78, alignment: .leading)
                Slider(value: llmBinding(
                    get: { $0.temperature },
                    set: { $0.temperature = $1 }
                ), in: 0...2, step: 0.1)
                Text(appModel.llmConfiguration.temperature.formatted(.number.precision(.fractionLength(1))))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
            }

            HStack(spacing: 8) {
                Button {
                    appModel.saveLLMSettings()
                } label: {
                    Label(appModel.localized("保存", "Save"), systemImage: "tray.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .help(appModel.localized("保存模型设置；Key 留空时不会读取或覆盖钥匙串。", "Save model settings; a blank key is not read from or written to Keychain."))

                Button {
                    appModel.testLLMConnection()
                } label: {
                    Label(appModel.isTestingLLMConnection ? appModel.localized("测试中", "Testing") : appModel.localized("测试", "Test"), systemImage: "bolt.horizontal")
                }
                .disabled(appModel.isTestingLLMConnection)

                if appModel.isTestingLLMConnection {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer(minLength: 0)

                if let message = appModel.llmConnectionStatusMessage {
                    Label(message, systemImage: message.localizedCaseInsensitiveContains("OK") ? "checkmark.circle" : "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(message)
                }
            }
        }
    }

    private var runtimeSection: some View {
        AIManagementSection(title: appModel.localized("运行时", "Runtime"), systemImage: "switch.2") {
            Picker("Runtime", selection: Binding(
                get: { appModel.workspacePreferences.agentRuntimeSelection },
                set: { appModel.updateAgentRuntimeSelection($0) }
            )) {
                ForEach(AgentRuntimeSelection.allCases) { selection in
                    Text(selection.label).tag(selection)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 10) {
                AIManagementIconToggle(
                    systemImage: "ladybug",
                    title: "Debug",
                    isOn: Binding(
                        get: { appModel.workspacePreferences.agentDebugLoggingEnabled },
                        set: { appModel.setAgentDebugLoggingEnabled($0) }
                    )
                )

                Button { appModel.restartAgentSidecar() } label: {
                    Label("Restart", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
                .help("Restart sidecar")

                Button { appModel.openAgentRunDirectory() } label: {
                    Label("Runs", systemImage: "folder")
                        .labelStyle(.iconOnly)
                }
                .help("Open runs")

                Button { appModel.openAgentDebugLogDirectory() } label: {
                    Label("Logs", systemImage: "doc.text.magnifyingglass")
                        .labelStyle(.iconOnly)
                }
                .help("Open logs")

                Button { appModel.exportDiagnosticsReport() } label: {
                    Label("Diagnostics", systemImage: "stethoscope")
                        .labelStyle(.iconOnly)
                }
                .help("Export diagnostics")

                Spacer(minLength: 0)

                Image(systemName: appModel.agentSidecarHealthSummary.localizedCaseInsensitiveContains("ready") ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(appModel.agentSidecarHealthSummary.localizedCaseInsensitiveContains("ready") ? Color.green : Color.orange)
                    .help(appModel.agentSidecarHealthSummary)
            }
            .buttonStyle(.bordered)
        }
    }

    private var sessionSection: some View {
        let summary = appModel.agentCollaborationSummary
        return AIManagementSection(title: appModel.localized("会话态势", "Session State"), systemImage: "chart.line.uptrend.xyaxis") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 138), spacing: 10)], alignment: .leading, spacing: 10) {
                AIManagementStateTile(
                    systemImage: "doc.text.magnifyingglass",
                    title: appModel.localized("证据", "Evidence"),
                    value: collaborationShortValue(summary.evidenceSummary),
                    tint: tint(from: summary.evidenceTint),
                    help: summary.evidenceSummary
                )
                AIManagementStateTile(
                    systemImage: "square.and.pencil",
                    title: appModel.localized("写回", "Writeback"),
                    value: collaborationShortValue(summary.writebackSummary),
                    tint: tint(from: summary.writebackTint),
                    help: summary.writebackSummary
                )
                AIManagementStateTile(
                    systemImage: "text.quote",
                    title: appModel.localized("提示词", "Prompt"),
                    value: promptShortValue(summary.promptSummary),
                    tint: .purple,
                    help: summary.promptSummary
                )
                AIManagementStateTile(
                    systemImage: "point.3.connected.trianglepath.dotted",
                    title: "MCP",
                    value: mcpShortValue,
                    tint: .orange,
                    help: summary.mcpSummary
                )
            }

            if !summary.writebackTargets.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(summary.writebackTargets.prefix(3)) { target in
                        HStack(spacing: 7) {
                            Image(systemName: writebackIcon(for: target.kind))
                                .foregroundStyle(target.risk == .readOnly ? Color.secondary : Color.orange)
                                .frame(width: 16)
                            Text(target.kind.label)
                                .font(.caption.weight(.medium))
                            Text(target.targetPath)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 0)
                        }
                        .help(target.summary)
                    }
                }
            }

            if summary.syntheticEvidenceWarning {
                Label(appModel.localized("检测到测试证据", "Synthetic evidence"), systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var toolsSection: some View {
        AIManagementSection(title: appModel.localized("工具", "Tools"), systemImage: "wrench.and.screwdriver") {
            HStack(spacing: 8) {
                Button {
                    appModel.setAllAgentTools(isEnabled: true)
                } label: {
                    Label(appModel.localized("全选", "All"), systemImage: "checkmark.circle")
                }
                Button {
                    appModel.setAllAgentTools(isEnabled: false)
                } label: {
                    Label(appModel.localized("清空", "Clear"), systemImage: "circle")
                }
                Spacer(minLength: 0)
                Text("\(appModel.agentEnabledToolNames.count)/\(appModel.agentToolDefinitions.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.bordered)

            if appModel.agentToolDefinitions.isEmpty {
                ContentUnavailableView(appModel.localized("未加载工具", "No Tools"), systemImage: "wrench.adjustable")
                    .frame(minHeight: 120)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(AIToolGroup.groups(for: appModel.agentToolDefinitions)) { group in
                        AIManagementToolGroupView(group: group)
                    }
                }
            }
        }
    }

    private var promptSection: some View {
        AIManagementSection(title: appModel.localized("提示词", "Prompts"), systemImage: "text.quote") {
            HStack(spacing: 8) {
                Button {
                    appModel.createAgentPromptTemplate()
                } label: {
                    Label(appModel.localized("新建", "New"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)

                Spacer(minLength: 0)

                Text("\(appModel.agentWorkspaceProfile.promptTemplates.filter(\.isEnabled).count)/\(appModel.agentWorkspaceProfile.promptTemplates.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if appModel.agentWorkspaceProfile.promptTemplates.isEmpty {
                ContentUnavailableView(appModel.localized("未配置提示词", "No Prompts"), systemImage: "text.quote")
                    .frame(minHeight: 120)
            } else {
                ForEach(appModel.agentWorkspaceProfile.promptTemplates) { template in
                    AIManagementPromptEditorRow(template: template)
                }
            }
        }
    }

    private var skillSection: some View {
        AIManagementSection(title: appModel.localized("Skills", "Skills"), systemImage: "graduationcap") {
            HStack(spacing: 8) {
                Button {
                    appModel.chooseAgentSkillMarkdownForImport()
                } label: {
                    Label(appModel.localized("导入", "Import"), systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)

                Spacer(minLength: 0)

                Text("\(appModel.agentWorkspaceProfile.skillToggles.filter(\.isEnabled).count)/\(appModel.agentWorkspaceProfile.skillToggles.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if appModel.agentWorkspaceProfile.skillToggles.isEmpty {
                ContentUnavailableView(appModel.localized("未配置 Skill", "No Skills"), systemImage: "graduationcap")
                    .frame(minHeight: 120)
            } else {
                ForEach(appModel.agentWorkspaceProfile.skillToggles) { toggle in
                    AIManagementSkillToggleRow(toggle: toggle)
                }
            }
        }
    }

    private var mcpSection: some View {
        AIManagementSection(title: "MCP", systemImage: "point.3.connected.trianglepath.dotted") {
            HStack(spacing: 8) {
                Button {
                    appModel.createAgentMCPServer()
                } label: {
                    Label(appModel.localized("新增", "Add"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)

                Spacer(minLength: 0)

                Text("\(appModel.agentWorkspaceProfile.mcpServers.filter(\.isEnabled).count)/\(appModel.agentWorkspaceProfile.mcpServers.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if appModel.agentWorkspaceProfile.mcpServers.isEmpty {
                ContentUnavailableView(appModel.localized("未配置 MCP", "No MCP Servers"), systemImage: "point.3.connected.trianglepath.dotted")
                    .frame(minHeight: 120)
            } else {
                ForEach(appModel.agentWorkspaceProfile.mcpServers) { server in
                    AIManagementMCPServerEditorRow(server: server)
                }
            }
        }
    }

    private var knowledgeSection: some View {
        AIManagementSection(title: appModel.localized("知识库", "Knowledge"), systemImage: "books.vertical") {
            HStack(spacing: 12) {
                AIManagementMetric(systemImage: "checklist", value: "\(appModel.agentKnowledgePaperSelectedCount)", label: appModel.localized("已选", "Selected"))
                AIManagementMetric(systemImage: "doc", value: "\(appModel.agentKnowledgePaperTotalCount)", label: appModel.localized("全部", "Total"))
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button { appModel.showAgentKnowledgeLibrary() } label: {
                    Label(appModel.localized("管理", "Manage"), systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.borderedProminent)

                Button { appModel.selectAllAgentKnowledgePapers() } label: {
                    Label(appModel.localized("全选", "All"), systemImage: "checkmark.circle")
                }
                Button { appModel.clearAgentKnowledgePapers() } label: {
                    Label(appModel.localized("清空", "Clear"), systemImage: "circle")
                }
                Button { appModel.convertSelectedAgentKnowledgePapersToMarkdown() } label: {
                    Label(appModel.isConvertingAgentKnowledgeMarkdown ? "MD..." : "PDF -> MD", systemImage: "doc.richtext")
                }
                .disabled(appModel.isConvertingAgentKnowledgeMarkdown || appModel.agentKnowledgePaperSelectedCount == 0)
            }
            .buttonStyle(.bordered)
        }
    }

    private var retrievalSection: some View {
        AIManagementSection(title: appModel.localized("检索", "Retrieval"), systemImage: "point.3.connected.trianglepath.dotted") {
            HStack(spacing: 12) {
                AIManagementMetric(systemImage: "square.stack.3d.up", value: "\(appModel.agentRetrievalIndexStatus.chunkCount)", label: "Chunks")
                AIManagementMetric(systemImage: "clock.badge.exclamationmark", value: "\(appModel.agentRetrievalIndexStatus.staleCount)", label: "Stale")
                Spacer(minLength: 0)
                Image(systemName: appModel.agentRetrievalIndexStatus.status == .ready ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(appModel.agentRetrievalIndexStatus.status == .ready ? Color.green : Color.orange)
                    .help(appModel.agentRetrievalStoreSummary)
            }

            HStack(spacing: 8) {
                Button { appModel.rebuildAgentRetrievalSelectedSource() } label: {
                    Label(appModel.localized("当前来源", "Source"), systemImage: "doc.badge.gearshape")
                }
                Button { appModel.rebuildAgentRetrievalCurrentProject() } label: {
                    Label(appModel.localized("项目", "Project"), systemImage: "arrow.triangle.2.circlepath")
                }
                Button { appModel.openAgentRetrievalIndexDirectory() } label: {
                    Label(appModel.localized("打开", "Open"), systemImage: "folder")
                }
                Button { appModel.copyAgentRetrievalDiagnostic() } label: {
                    Label(appModel.localized("复制", "Copy"), systemImage: "doc.on.doc")
                        .labelStyle(.iconOnly)
                }
                .help(appModel.redactedAgentRetrievalDiagnosticSummary)
            }
            .buttonStyle(.bordered)
        }
    }

    private var advancedSection: some View {
        AIManagementSection(title: appModel.localized("高级", "Advanced"), systemImage: "ellipsis.circle") {
            HStack(spacing: 8) {
                Button { appModel.exportAgentDebugBundle() } label: {
                    Label("Debug", systemImage: "shippingbox")
                }
                Button(role: .destructive) { appModel.disableSidecarForWorkspace() } label: {
                    Label("Sidecar", systemImage: "power")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var runtimeIcon: String {
        switch appModel.workspacePreferences.agentRuntimeSelection {
        case .swiftLoop:
            return "swift"
        case .langGraphSidecar:
            return "server.rack"
        case .autoFallback:
            return "arrow.triangle.2.circlepath"
        }
    }

    private var mcpShortValue: String {
        let total = appModel.agentProductMCPServerStatuses.count
            + appModel.agentWorkspaceProfileMCPServerStatuses.count
            + appModel.agentLocalMCPServerStatuses.count
        return "\(total)"
    }

    private func collaborationShortValue(_ value: String) -> String {
        if value.localizedCaseInsensitiveContains("no active run") {
            return appModel.localized("空闲", "Idle")
        }
        if value.localizedCaseInsensitiveContains("waiting") || value.localizedCaseInsensitiveContains("approval") {
            return appModel.localized("待处理", "Pending")
        }
        if value.localizedCaseInsensitiveContains("failed") || value.localizedCaseInsensitiveContains("denied") {
            return appModel.localized("失败", "Issue")
        }
        return value.components(separatedBy: " ").first ?? value
    }

    private func promptShortValue(_ value: String) -> String {
        if value.localizedCaseInsensitiveContains("bundled") {
            return appModel.localized("默认", "Default")
        }
        return value.components(separatedBy: " · ").first ?? value
    }

    private func tint(from value: String) -> Color {
        switch value {
        case "green":
            return .green
        case "orange":
            return .orange
        case "red":
            return .red
        case "blue":
            return .blue
        case "purple":
            return .purple
        default:
            return .secondary
        }
    }

    private func writebackIcon(for kind: AgentWritebackTargetKind) -> String {
        switch kind {
        case .projectBrief:
            return "doc.text"
        case .wikiNote:
            return "note.text"
        case .wikiPaper:
            return "doc.richtext"
        case .todo:
            return "checklist"
        case .workspaceDraft:
            return "square.and.pencil"
        }
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

private struct AIManagementSection<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                content
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.vertical, 2)
        }
        .groupBoxStyle(AIManagementRectGroupBoxStyle())
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct AIManagementRectGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.content
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct AIManagementStatusChip: View {
    let systemImage: String
    let title: String
    let tint: Color
    let help: String

    var body: some View {
        Label {
            Text(title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .help(help)
    }
}

private struct AIManagementMetric: View {
    let systemImage: String
    let value: String
    let label: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.headline.monospacedDigit())
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(Color.accentColor)
        }
    }
}

private struct AIManagementStateTile: View {
    let systemImage: String
    let title: String
    let value: String
    let tint: Color
    let help: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .help(help)
    }
}

private struct AIManagementIconToggle: View {
    let systemImage: String
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Image(systemName: systemImage)
                .help(title)
        }
        .toggleStyle(.button)
        .labelsHidden()
    }
}

struct AIToolGroup: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let tools: [AgentToolDefinition]

    static func groups(for tools: [AgentToolDefinition]) -> [AIToolGroup] {
        Dictionary(grouping: tools, by: groupKey(for:))
            .map { key, values in
                let metadata = metadata(for: key)
                return AIToolGroup(
                    id: key,
                    title: metadata.title,
                    systemImage: metadata.systemImage,
                    tools: values.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
                )
            }
            .sorted { lhs, rhs in lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending }
    }

    private static func groupKey(for tool: AgentToolDefinition) -> String {
        if tool.source.hasPrefix("mcp:") {
            return "mcp"
        }
        if tool.risk == .network {
            return "network"
        }
        if tool.risk == .writesWorkspace || tool.risk == .modifiesMetadata {
            return "write"
        }
        if tool.risk == .runsCode {
            return "code"
        }
        if tool.name.localizedCaseInsensitiveContains("paper") {
            return "paper"
        }
        if tool.name.localizedCaseInsensitiveContains("wiki") {
            return "wiki"
        }
        if tool.name.localizedCaseInsensitiveContains("task") || tool.name.localizedCaseInsensitiveContains("todo") {
            return "task"
        }
        return "read"
    }

    private static func metadata(for key: String) -> (title: String, systemImage: String) {
        switch key {
        case "mcp":
            return ("MCP", "point.3.connected.trianglepath.dotted")
        case "network":
            return ("联网", "network")
        case "write":
            return ("写入", "square.and.pencil")
        case "code":
            return ("代码", "terminal")
        case "paper":
            return ("论文", "doc.text.magnifyingglass")
        case "wiki":
            return ("Wiki", "book.pages")
        case "task":
            return ("任务", "checklist")
        default:
            return ("读取", "folder")
        }
    }
}

private struct AIManagementToolGroupView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let group: AIToolGroup
    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(group.tools, id: \.identifier) { tool in
                    AIManagementToolToggle(tool: tool)
                }
            }
            .padding(.top, 6)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: group.systemImage)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 16)
                Text(group.title)
                    .font(.caption.weight(.semibold))
                Text("\(enabledCount)/\(group.tools.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(9)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private var enabledCount: Int {
        group.tools.filter { appModel.agentEnabledToolNames.contains($0.name) }.count
    }
}

private struct AIManagementToolToggle: View {
    @EnvironmentObject private var appModel: AppViewModel

    let tool: AgentToolDefinition

    var body: some View {
        Toggle(isOn: Binding(
            get: { appModel.agentEnabledToolNames.contains(tool.name) },
            set: { appModel.setAgentTool(tool.name, isEnabled: $0) }
        )) {
            HStack(spacing: 7) {
                Image(systemName: iconName)
                    .foregroundStyle(tint)
                    .frame(width: 16)
                Text(tool.displayName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .help("\(tool.summary)\n\(tool.risk.rawValue)")
        }
        .toggleStyle(.checkbox)
    }

    private var iconName: String {
        switch tool.risk {
        case .readOnly:
            return "eye"
        case .network:
            return "network"
        case .writesWorkspace, .modifiesMetadata:
            return "square.and.pencil"
        case .runsCode:
            return "terminal"
        case .destructive:
            return "exclamationmark.triangle"
        case .externalSideEffect:
            return "arrow.up.right.square"
        case .credentialAccess:
            return "key"
        }
    }

    private var tint: Color {
        tool.risk == .readOnly ? .secondary : .orange
    }
}

private struct AIManagementPromptEditorRow: View {
    @EnvironmentObject private var appModel: AppViewModel

    let template: AgentPromptTemplateOverride
    @State private var draft: AgentPromptTemplateOverride

    init(template: AgentPromptTemplateOverride) {
        self.template = template
        _draft = State(initialValue: template)
    }

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                TextField("标题", text: $draft.title)
                    .textFieldStyle(.roundedBorder)
                Picker("用途", selection: $draft.surface) {
                    ForEach(AgentPromptSurface.allCases, id: \.rawValue) { surface in
                        Text(surface.rawValue).tag(surface)
                    }
                }
                .pickerStyle(.menu)
                TextEditor(text: $draft.promptTemplate)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 120)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.16)))
                HStack(spacing: 8) {
                    Toggle("启用", isOn: Binding(
                        get: { draft.isEnabled },
                        set: { draft.isEnabled = $0 }
                    ))
                    .toggleStyle(.switch)
                    Spacer(minLength: 0)
                    Button {
                        appModel.saveAgentPromptTemplate(
                            id: draft.id,
                            title: draft.title,
                            version: draft.version,
                            description: draft.description,
                            surface: draft.surface,
                            systemPrompt: draft.systemPrompt,
                            promptTemplate: draft.promptTemplate,
                            isEnabled: draft.isEnabled
                        )
                    } label: {
                        Label("保存", systemImage: "tray.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    Button(role: .destructive) {
                        appModel.removeAgentPromptTemplate(id: template.id)
                    } label: {
                        Label("删除", systemImage: "trash")
                            .labelStyle(.iconOnly)
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            AIManagementEditableRowLabel(
                systemImage: "text.quote",
                title: template.title,
                subtitle: "\(template.surface.rawValue) · \(template.version)",
                isEnabled: template.isEnabled
            )
        }
        .padding(9)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .onChange(of: template) { _, newValue in
            draft = newValue
        }
    }
}

private struct AIManagementSkillToggleRow: View {
    @EnvironmentObject private var appModel: AppViewModel

    let toggle: AgentSkillToggle

    var body: some View {
        HStack(spacing: 8) {
            AIManagementEditableRowLabel(
                systemImage: "graduationcap",
                title: toggle.displayName ?? toggle.skillID,
                subtitle: trustLabel,
                isEnabled: toggle.isEnabled
            )
            Spacer(minLength: 0)
            Toggle("", isOn: Binding(
                get: { toggle.isEnabled },
                set: { isEnabled in
                    appModel.updateAgentWorkspaceProfile { profile in
                        guard let index = profile.skillToggles.firstIndex(where: { $0.skillID == toggle.skillID }) else {
                            return
                        }
                        profile.skillToggles[index].isEnabled = isEnabled
                    }
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .padding(9)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private var trustLabel: String {
        switch toggle.trustLevel {
        case .untrusted:
            return "未信任"
        case .trusted:
            return "已信任"
        }
    }
}

private struct AIManagementMCPServerEditorRow: View {
    @EnvironmentObject private var appModel: AppViewModel

    let server: MCPServerConfiguration
    @State private var draft: MCPServerConfiguration
    @State private var argumentsText: String
    @State private var allowedToolsText: String

    init(server: MCPServerConfiguration) {
        self.server = server
        _draft = State(initialValue: server)
        _argumentsText = State(initialValue: server.arguments.joined(separator: " "))
        _allowedToolsText = State(initialValue: server.allowedTools.joined(separator: ", "))
    }

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    TextField("名称", text: $draft.displayName)
                        .textFieldStyle(.roundedBorder)
                    Toggle("启用", isOn: $draft.isEnabled)
                        .toggleStyle(.switch)
                }
                Picker("传输", selection: $draft.transport) {
                    Text("本地命令").tag(MCPServerTransport.localCommand)
                    Text("HTTP").tag(MCPServerTransport.remoteHTTP)
                    Text("SSE").tag(MCPServerTransport.remoteSSE)
                }
                .pickerStyle(.segmented)

                if draft.transport == .localCommand {
                    TextField("命令", text: Binding(
                        get: { draft.command ?? "" },
                        set: { draft.command = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    TextField("参数", text: $argumentsText)
                        .textFieldStyle(.roundedBorder)
                } else {
                    TextField("URL", text: Binding(
                        get: { draft.urlString ?? "" },
                        set: { draft.urlString = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: 8) {
                    TextField("允许工具", text: $allowedToolsText)
                        .textFieldStyle(.roundedBorder)
                    Stepper("\(Int(draft.timeoutSeconds))s", value: $draft.timeoutSeconds, in: 5...300, step: 5)
                        .frame(width: 110)
                }

                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Button {
                        var updated = draft
                        updated.arguments = shellWords(argumentsText)
                        updated.allowedTools = commaSeparatedValues(allowedToolsText)
                        appModel.saveAgentMCPServer(updated)
                    } label: {
                        Label("保存", systemImage: "tray.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)

                    Button(role: .destructive) {
                        appModel.removeAgentMCPServer(id: server.id)
                    } label: {
                        Label("删除", systemImage: "trash")
                            .labelStyle(.iconOnly)
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            AIManagementEditableRowLabel(
                systemImage: "point.3.connected.trianglepath.dotted",
                title: server.displayName,
                subtitle: server.transport.rawValue,
                isEnabled: server.isEnabled
            )
        }
        .padding(9)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .onChange(of: server) { _, newValue in
            draft = newValue
            argumentsText = newValue.arguments.joined(separator: " ")
            allowedToolsText = newValue.allowedTools.joined(separator: ", ")
        }
    }

    private func shellWords(_ text: String) -> [String] {
        text.split(separator: " ").map(String.init)
    }

    private func commaSeparatedValues(_ text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private struct AIManagementEditableRowLabel: View {
    let systemImage: String
    let title: String
    let subtitle: String
    let isEnabled: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(isEnabled ? Color.accentColor : Color.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title.isEmpty ? "Untitled" : title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

struct WorkspaceCreationWizardView: View {
    @EnvironmentObject private var appModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    private let previewColumns = [GridItem(.adaptive(minimum: 170), spacing: 10)]

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    destinationSection
                    templateSection
                    previewSection
                    privacySection
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
            footer
        }
        .frame(minWidth: 640, idealWidth: 920, minHeight: 560, idealHeight: 760)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "folder.badge.plus")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(appModel.localized("工作区创建向导", "Workspace Creation Wizard"))
                    .font(.title2.weight(.semibold))
                Text(appModel.localized(
                    "选择模板并检查将创建的内容，然后打开研究根目录。",
                    "Choose a template, inspect what will be created, then open the Research Root."
                ))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private var destinationSection: some View {
        let validation = appModel.workspaceCreationTargetValidation

        return GroupBox("Destination") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    TextField(
                        "Workspace name",
                        text: Binding(
                            get: { appModel.workspaceCreationDraft.workspaceName },
                            set: appModel.updateWorkspaceCreationName
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)

                    Button {
                        appModel.chooseWorkspaceCreationDestination()
                    } label: {
                        Label("Choose Folder", systemImage: "folder")
                    }

                    Spacer(minLength: 0)
                }

                WorkspacePathRow(
                    label: "Target",
                    value: appModel.workspaceCreationDraft.targetURL?.path ?? "No destination selected"
                )

                Label(validation.message, systemImage: validation.canCreate ? "checkmark.circle" : "exclamationmark.triangle")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(validation.canCreate ? Color.green : Color.orange)

                if !validation.detail.isEmpty {
                    Text(validation.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private var templateSection: some View {
        GroupBox("Template") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(appModel.workspaceCreationTemplateOptions) { option in
                    Button {
                        appModel.updateWorkspaceCreationTemplate(option.id)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: templateIcon(for: option))
                                .frame(width: 18)
                                .foregroundStyle(templateColor(for: option))
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 8) {
                                    Text(option.title)
                                        .fontWeight(appModel.workspaceCreationDraft.templateID == option.id ? .semibold : .regular)
                                    Text(templateStatusText(for: option))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(option.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            if appModel.workspaceCreationDraft.templateID == option.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(.vertical, 5)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .disabled(!option.isSelectable)
                    .opacity(option.isSelectable ? 1.0 : 0.58)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private var previewSection: some View {
        let preview = appModel.workspaceCreationPreview

        return GroupBox("Preview") {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: previewColumns, alignment: .leading, spacing: 10) {
                    WorkspaceCreationMetricView(title: "Modules", value: "\(preview.enabledModules.count) enabled")
                    WorkspaceCreationMetricView(title: "Directories", value: "\(preview.directoryItems.filter(\.willCreate).count) created")
                    WorkspaceCreationMetricView(title: "Routes", value: "\(preview.routes.count)")
                    WorkspaceCreationMetricView(title: "Workflows", value: "\(preview.workflows.count)")
                }

                WorkspaceCreationPreviewList(
                    title: "Enabled Modules",
                    systemImage: "checkmark.circle",
                    items: preview.enabledModules.map(\.title)
                )

                WorkspaceCreationPreviewList(
                    title: "Future Modules",
                    systemImage: "circle.dotted",
                    items: preview.disabledModules.prefix(7).map { "\($0.title) disabled" }
                )

                VStack(alignment: .leading, spacing: 7) {
                    Text("Directories")
                        .font(.caption.weight(.semibold))
                    ForEach(preview.directoryItems.prefix(14)) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: directoryIcon(for: item))
                                .foregroundStyle(item.willCreate ? Color.accentColor : Color.secondary)
                                .frame(width: 16)
                            Text(item.path)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 8)
                            Text(directoryStatusText(for: item))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                WorkspaceCreationPreviewList(
                    title: "Settings Files",
                    systemImage: "doc.text",
                    items: preview.settingsFiles
                )

                WorkspaceCreationPreviewList(
                    title: "Routes / Tabs / Workflows",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    items: routeSummaryItems(for: preview)
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private var privacySection: some View {
        GroupBox("Privacy And AI Setup") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(WorkspaceCreationWizard.privacyNotes, id: \.self) { note in
                    Label(note, systemImage: "checkmark.shield")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle(
                    "I understand that AI Lab visibility does not configure provider credentials or start an AI run.",
                    isOn: Binding(
                        get: { appModel.workspaceCreationDraft.privacyAcknowledged },
                        set: appModel.setWorkspaceCreationPrivacyAcknowledged
                    )
                )
                .toggleStyle(.checkbox)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if appModel.isWorking {
                ProgressView()
                    .controlSize(.small)
                Text("Preparing workspace")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button {
                appModel.completeWorkspaceCreation()
            } label: {
                Label("Create And Open", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!appModel.canCompleteWorkspaceCreation)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private func templateIcon(for option: WorkspaceCreationTemplateOption) -> String {
        if !option.isSelectable { return "clock" }
        if option.id == WorkspaceTemplateRegistry.minimal.id { return "square.dashed" }
        return "books.vertical"
    }

    private func templateColor(for option: WorkspaceCreationTemplateOption) -> Color {
        option.isSelectable ? Color.accentColor : Color.secondary
    }

    private func templateStatusText(for option: WorkspaceCreationTemplateOption) -> String {
        option.isSelectable ? "available" : "coming later"
    }

    private func directoryIcon(for item: WorkspaceCreationDirectoryPreviewItem) -> String {
        if item.isWildcard { return "folder.badge.questionmark" }
        return item.willCreate ? "folder.badge.plus" : "folder"
    }

    private func directoryStatusText(for item: WorkspaceCreationDirectoryPreviewItem) -> String {
        if item.isWildcard { return "project instance preview" }
        if item.required { return item.repairable ? "required, repairable" : "required" }
        return item.willCreate ? "optional" : "preview only"
    }

    private func routeSummaryItems(for preview: WorkspaceCreationPreview) -> [String] {
        [
            "Routes: " + preview.routes.map(\.id).joined(separator: ", "),
            "Project tabs: " + preview.projectTabs.map(\.title).joined(separator: ", "),
            "Workflows: " + preview.workflows.joined(separator: ", ")
        ]
    }
}

private struct WorkspaceCreationMetricView: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WorkspaceCreationPreviewList: View {
    let title: String
    let systemImage: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
            if items.isEmpty {
                Text("none")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items.prefix(8), id: \.self) { item in
                    Label(item, systemImage: systemImage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LLMSummaryPreviewView: View {
    @EnvironmentObject private var appModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(appModel.localized("LLM 摘要预览", "LLM Summary Preview"))
                .font(.title2)
                .fontWeight(.semibold)

            TextEditor(text: Binding(
                get: { appModel.summaryPreviewText ?? "" },
                set: appModel.updateSummaryPreviewText
            ))
            .font(.system(.body, design: .monospaced))

            HStack(spacing: 12) {
                Button(appModel.localized("替换 Wiki", "Replace Wiki")) {
                    appModel.applySummaryPreview(mode: .replace)
                }
                .buttonStyle(.borderedProminent)

                Button(appModel.localized("追加", "Append")) {
                    appModel.applySummaryPreview(mode: .append)
                }
                .buttonStyle(.bordered)

                Button(appModel.localized("保存草稿", "Save Draft")) {
                    appModel.applySummaryPreview(mode: .saveDraft)
                }
                .buttonStyle(.bordered)

                Button(appModel.localized("关闭", "Close")) {
                    dismiss()
                }
            }
        }
        .padding(20)
        .frame(minWidth: 620, idealWidth: 860, minHeight: 480, idealHeight: 560)
    }
}

private extension String {
    var nilIfEmptyAfterTrimming: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
