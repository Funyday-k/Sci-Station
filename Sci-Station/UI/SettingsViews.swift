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
                                appModel.beginWorkspaceCreation()
                            } label: {
                                Label("Create Root", systemImage: "plus")
                            }
                            .help(Text(verbatim: "Open the workspace creation wizard"))

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

                GroupBox("Workspace Modules") {
                    let availableModuleIDs = Set(WorkspaceModuleRegistry.availableModules(in: appModel.workspaceModuleConfiguration).map(\.id))
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

                if appModel.selectedSettingsCategory == .modules {
                    ModuleSettingsView(workspace: workspace)
                        .environmentObject(appModel)
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
        .frame(minWidth: 840, idealWidth: 920, minHeight: 700, idealHeight: 760)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "folder.badge.plus")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text("Workspace Creation Wizard")
                    .font(.title2.weight(.semibold))
                Text("Choose a template, inspect what will be created, then open the Research Root.")
                    .foregroundStyle(.secondary)
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