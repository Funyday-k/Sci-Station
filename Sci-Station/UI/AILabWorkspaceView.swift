import AppKit
import SwiftUI

struct AILabWorkspaceView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace

    var body: some View {
        VStack(spacing: 0) {
            AILabCompactHeaderView()
                .padding(.horizontal, 24)
                .padding(.vertical, 14)

            Divider()

            AgentPanelView(workspace: workspace)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $appModel.isShowingAgentKnowledgeLibrary) {
            AIKnowledgeLibrarySheet()
                .environmentObject(appModel)
        }
    }
}

private struct AILabCompactHeaderView: View {
    @EnvironmentObject private var appModel: AppViewModel

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("AI Lab")
                    .font(.headline)
                    .fontWeight(.semibold)
                Text(appModel.agentConversationTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 150, alignment: .leading)

            Spacer(minLength: 0)

            Picker("模式", selection: $appModel.agentInteractionMode) {
                ForEach(AgentInteractionMode.allCases) { mode in
                    Text(mode.shortTitle).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
            .help(Text(verbatim: appModel.agentModeStatusText))

            Button {
                appModel.showAgentKnowledgeLibrary()
            } label: {
                Label("\(appModel.agentKnowledgePaperSelectedCount)/\(appModel.agentKnowledgePaperTotalCount)", systemImage: "books.vertical")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("AI 知识库")

            Menu {
                if appModel.agentToolDefinitions.isEmpty {
                    Text("未加载工具")
                } else {
                    ForEach(appModel.agentToolDefinitions, id: \.identifier) { tool in
                        Toggle(isOn: Binding(
                            get: { appModel.agentEnabledToolNames.contains(tool.name) },
                            set: { appModel.setAgentTool(tool.name, isEnabled: $0) }
                        )) {
                            VStack(alignment: .leading) {
                                Text(tool.name)
                                Text(tool.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } label: {
                Label(appModel.agentEnabledToolSummary, systemImage: "wrench.and.screwdriver")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("选择当前模式边界内可用的 AI Lab 工具")

            HStack(spacing: 6) {
                Menu {
                    ForEach(DeepSeekModelOption.presets) { option in
                        Button {
                            appModel.useDeepSeekModel(option)
                        } label: {
                            Label(option.title, systemImage: appModel.llmConfiguration.model == option.id ? "checkmark" : "cpu")
                        }
                        .help(Text(verbatim: option.detail))
                    }
                    Divider()
                    Button {
                        appModel.openSettings(category: .aiLab)
                    } label: {
                        Label("全部模型设置", systemImage: "gearshape")
                    }
                } label: {
                    Label(appModel.llmConfiguration.model, systemImage: "cpu")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .menuStyle(.borderlessButton)
                Button {
                    appModel.openSettings(category: .aiLab)
                } label: {
                    Label("AI 设置", systemImage: "gearshape")
                        .labelStyle(.iconOnly)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct AIKnowledgeLibrarySheet: View {
    @EnvironmentObject private var appModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedFilter = AIKnowledgeFilter.all

    private var filteredPapers: [Paper] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filteredByCategory = appModel.papers.filter(matchesSelectedFilter)
        guard !query.isEmpty else {
            return filteredByCategory
        }

        return filteredByCategory.filter { paper in
            paper.displayTitle.lowercased().contains(query)
                || paper.authorsDisplay.lowercased().contains(query)
                || paper.tagsDisplay.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Knowledge Library")
                        .font(.headline)
                    Text("\(appModel.agentKnowledgePaperSelectedCount) of \(appModel.agentKnowledgePaperTotalCount) papers selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Button {
                    appModel.convertSelectedAgentKnowledgePapersToMarkdown()
                } label: {
                    Label(appModel.isConvertingAgentKnowledgeMarkdown ? "转换中" : "PDF -> MD", systemImage: "doc.richtext")
                }
                .disabled(appModel.isConvertingAgentKnowledgeMarkdown || appModel.agentKnowledgePaperSelectedCount == 0)
                .help("使用 MinerU API 将所选论文转换为 paper.md")

                Button("All") {
                    appModel.selectAllAgentKnowledgePapers()
                }
                Button("Clear") {
                    appModel.clearAgentKnowledgePapers()
                }
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }

            TextField("Search papers", text: $searchText)
                .textFieldStyle(.roundedBorder)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AIKnowledgeFilter.allCases) { filter in
                        Button {
                            selectedFilter = filter
                        } label: {
                            Label(filter.title, systemImage: filter.systemImage)
                        }
                        .buttonStyle(.bordered)
                        .tint(selectedFilter == filter ? Color.accentColor : Color.secondary)
                        .controlSize(.small)
                    }
                }
            }

            HStack(spacing: 8) {
                Text("Showing \(filteredPapers.count) papers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if appModel.isConvertingAgentKnowledgeMarkdown {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            List(filteredPapers) { paper in
                Toggle(isOn: Binding(
                    get: { appModel.selectedAgentKnowledgePaperIDs.contains(paper.id) },
                    set: { appModel.setAgentKnowledgePaper(paper.id, isSelected: $0) }
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(paper.displayTitle)
                            .font(.subheadline)
                            .lineLimit(2)
                        Text([paper.authorsDisplay, paper.publicationDisplay, paper.year.map(String.init)].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        HStack(spacing: 8) {
                            if appModel.agentKnowledgePaperHasPDF(paper) {
                                Label("PDF", systemImage: "doc")
                            }
                            PaperMarkdownConversionBadge(
                                state: appModel.paperMarkdownConversionState(for: paper),
                                message: appModel.paperMarkdownConversionMessage(for: paper)
                            )
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                }
                .toggleStyle(.checkbox)
            }
            .frame(minHeight: 360)
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 500)
        .alert(appModel.markdownOverwriteConfirmationTitle, isPresented: $appModel.isShowingMarkdownOverwriteConfirmation) {
            Button(appModel.localized("覆盖并转换", "Overwrite and Convert"), role: .destructive, action: appModel.confirmMarkdownOverwriteConversion)
            Button(appModel.localized("取消", "Cancel"), role: .cancel, action: appModel.cancelMarkdownOverwriteConversion)
        } message: {
            Text(appModel.markdownOverwriteConfirmationMessage)
        }
    }

    private func matchesSelectedFilter(_ paper: Paper) -> Bool {
        switch selectedFilter {
        case .all:
            return true
        case .project:
            guard let projectID = appModel.agentConversationProjectID else {
                return false
            }
            return paper.projectIDs.contains(projectID)
        case .core:
            guard let projectID = appModel.agentConversationProjectID else {
                return false
            }
            return paper.coreProjectIDs.contains(projectID)
        case .tagged:
            return !paper.tags.isEmpty || !paper.categories.isEmpty
        case .hasPDF:
            return appModel.agentKnowledgePaperHasPDF(paper)
        case .hasMarkdown:
            return appModel.agentKnowledgePaperHasMarkdown(paper)
        case .missingMarkdown:
            return appModel.agentKnowledgePaperHasPDF(paper) && !appModel.agentKnowledgePaperHasMarkdown(paper)
        }
    }
}

private enum AIKnowledgeFilter: String, CaseIterable, Identifiable {
    case all
    case project
    case core
    case tagged
    case hasPDF
    case hasMarkdown
    case missingMarkdown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .project: return "Project"
        case .core: return "Core"
        case .tagged: return "Tagged"
        case .hasPDF: return "Has PDF"
        case .hasMarkdown: return "Has Markdown"
        case .missingMarkdown: return "Missing Markdown"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "tray.full"
        case .project: return "folder"
        case .core: return "star"
        case .tagged: return "tag"
        case .hasPDF: return "doc"
        case .hasMarkdown: return "doc.richtext"
        case .missingMarkdown: return "exclamationmark.circle"
        }
    }
}

private struct AILabDockShell<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(10)
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.16))
            }
            .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
    }
}

private struct AILabDockTray<Content: View>: View {
    let attachTop: Bool
    let content: Content

    init(attachTop: Bool = false, @ViewBuilder content: () -> Content) {
        self.attachTop = attachTop
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.12))
            }
            .padding(.top, attachTop ? -10 : 0)
    }
}

private struct AgentPanelView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace
    @State private var isContextExpanded = false
    @State private var isAgentDetailsExpanded = false
    @State private var isPlanExpanded = false
    @State private var isPermissionDockExpanded = true
    @State private var isHooksExpanded = false
    @State private var isMCPExpanded = false
    @State private var isPresetExpanded = false
    @State private var isHistoryExpanded = false
    private let timelineBottomID = "agent-timeline-bottom"

    var body: some View {
        VStack(spacing: 0) {
            sessionHeader

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    AgentConversationTimelineView(
                        thread: appModel.activeAgentThread,
                        runs: appModel.agentConversationRuns,
                        currentRun: appModel.agentCurrentRun,
                        events: appModel.agentTimelineItems,
                        pendingPrompt: appModel.agentPendingUserPrompt,
                        streamingResponse: appModel.agentStreamingResponseText,
                        isThinking: appModel.isPlanningAgentRun,
                        thinkingModeTitle: appModel.agentInteractionMode.title
                    )
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Color.clear
                        .frame(height: 1)
                        .id(timelineBottomID)
                }
                .onChange(of: appModel.agentTimelineItems.count) { _, _ in scrollToBottom(proxy) }
                .onChange(of: appModel.agentPendingUserPrompt) { _, _ in scrollToBottom(proxy) }
                .onChange(of: appModel.isPlanningAgentRun) { _, _ in scrollToBottom(proxy) }
                .onChange(of: appModel.agentCurrentRun?.id) { _, _ in scrollToBottom(proxy) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            pendingInteractionDock
            composerDock
        }
        .sheet(isPresented: $appModel.isShowingAgentThreadRename) {
            AgentThreadRenameSheet()
                .environmentObject(appModel)
        }
    }

    private var sessionHeader: some View {
        HStack(spacing: 12) {
            Label("计划模式：\(appModel.agentInteractionMode.title)", systemImage: "switch.2")
                .font(.caption.weight(.semibold))

            if !appModel.activeResearchProjects.isEmpty {
                Picker("项目", selection: projectSelection) {
                    ForEach(appModel.activeResearchProjects) { project in
                        Text(project.name).tag(project.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 220)
            } else {
                Text("项目：全局")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            statusMessages
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.04))
    }

    private var projectSelection: Binding<ResearchProject.ID> {
        Binding(
            get: { appModel.currentResearchProject?.id ?? appModel.activeResearchProjects.first?.id ?? "" },
            set: { appModel.focusResearchProject($0) }
        )
    }

    private var runtimeRail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Runtime", systemImage: "switch.2")
                        .font(.headline)
                    Spacer(minLength: 0)
                }

                AgentPlatformStatusView()

                DisclosureGroup("Preset Manager", isExpanded: $isPresetExpanded) {
                    AgentPresetManagerView()
                }

                DisclosureGroup("Hook Activity", isExpanded: $isHooksExpanded) {
                    AgentHookActivityView()
                }

                DisclosureGroup("MCP Servers", isExpanded: $isMCPExpanded) {
                    AgentMCPServerStatusView()
                }

                DisclosureGroup("Context", isExpanded: $isContextExpanded) {
                    AgentContextSummaryView(snapshot: appModel.agentWorkspaceSnapshot, tools: appModel.agentToolDefinitions)
                }

                if let run = appModel.agentCurrentRun {
                    DisclosureGroup("Current Plan", isExpanded: $isPlanExpanded) {
                        AgentPlanSummaryView(run: run)
                    }
                }

                DisclosureGroup("Conversation History", isExpanded: $isHistoryExpanded) {
                    AgentRunHistoryView(
                        currentRuns: appModel.agentConversationRuns,
                        orphanRuns: appModel.agentOrphanRuns
                    )
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.secondary.opacity(0.025))
    }

    @ViewBuilder
    private var threadStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Threads")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("\(appModel.agentThreads.count) / \(appModel.allAgentThreads.filter { !$0.isArchived }.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Toggle("Current workspace", isOn: $appModel.isAgentThreadWorkspaceFilterEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.caption)
                    .help("Show only chats tagged with \(workspace.displayName).")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let pendingThread = appModel.pendingAgentThread {
                        threadButton(title: pendingThread.title, subtitle: "Draft", isActive: appModel.activeAgentThreadID == pendingThread.id) {
                            // The pending thread is already the active session-only draft.
                        }
                        .contextMenu {
                            Button("Discard Draft", role: .destructive) {
                                appModel.discardPendingAgentThread()
                            }
                        }
                    }

                    ForEach(appModel.agentThreads) { thread in
                        threadButton(
                            title: thread.title,
                            subtitle: appModel.agentThreadSubtitle(for: thread),
                            isActive: appModel.activeAgentThreadID == thread.id
                        ) {
                            appModel.selectAgentThread(thread)
                        }
                        .contextMenu {
                            Button("Rename Thread") {
                                appModel.beginRenameAgentThread(thread)
                            }
                            Button("Archive Thread", role: .destructive) {
                                appModel.archiveAgentThread(thread)
                            }
                        }
                    }

                    if appModel.agentThreads.isEmpty, appModel.pendingAgentThread == nil {
                        Text(appModel.isAgentThreadWorkspaceFilterEnabled ? "No chats in this workspace." : "No saved threads yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 6)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func threadButton(title: String, subtitle: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        if isActive {
            Button(action: action) {
                threadButtonLabel(title: title, subtitle: subtitle)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        } else {
            Button(action: action) {
                threadButtonLabel(title: title, subtitle: subtitle)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func threadButtonLabel(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 110, alignment: .leading)
    }

    @ViewBuilder
    private var pendingInteractionDock: some View {
        if appModel.agentInteractionMode.allowsApprovedToolExecution,
           let run = appModel.agentCurrentRun,
           !appModel.agentPermissionDockItems(for: run).isEmpty {
            AgentPermissionDockView(run: run)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 6)
        }
    }

    private var composerDock: some View {
        VStack(spacing: 0) {
            AILabDockShell {
                HStack(alignment: .bottom, spacing: 10) {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $appModel.agentGoal)
                            .font(.system(size: CGFloat(appModel.workspacePreferences.agentChatFontSize)))
                            .frame(minHeight: 54, maxHeight: 92)
                            .padding(4)
                            .onKeyPress(keys: [.return]) { keyPress in
                                if keyPress.modifiers.contains(.shift) {
                                    return .ignored
                                }

                                submitComposer()
                                return .handled
                            }

                        if appModel.agentGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("\(appModel.agentModeStatusText) 输入问题、计划请求，或让 AI 阅读所选论文。")
                                .font(.system(size: CGFloat(appModel.workspacePreferences.agentChatFontSize)))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 12)
                                .allowsHitTesting(false)
                        }
                    }
                    .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.16))
                    }

                    Button {
                        if appModel.isPlanningAgentRun {
                            appModel.cancelAgentGeneration()
                        } else {
                            appModel.generateAgentPlan()
                        }
                    } label: {
                        Label(appModel.isPlanningAgentRun ? "停止" : "发送", systemImage: appModel.isPlanningAgentRun ? "stop.fill" : "arrow.up")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(appModel.isExecutingAgentTools)
                    .help(appModel.isPlanningAgentRun ? "停止输出" : "Return 发送，Shift+Return 换行")
                    .accessibilityLabel(appModel.isPlanningAgentRun ? "停止输出" : "发送")
                }
            }

            AILabDockTray(attachTop: true) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button {
                            appModel.startNewAgentConversation()
                        } label: {
                            Label("新对话", systemImage: "plus.bubble")
                        }

                        Button {
                            appModel.refreshAgentContext()
                        } label: {
                            Label(appModel.isRefreshingAgentContext ? "刷新中" : "刷新", systemImage: "arrow.clockwise")
                        }
                        .disabled(appModel.isRefreshingAgentContext)

                        Button {
                            appModel.openSettings(category: .aiLab)
                        } label: {
                            Label("设置", systemImage: "gearshape")
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.horizontal, 10)
                    .padding(.top, 18)
                    .padding(.bottom, 8)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 14)
        .background(Color.secondary.opacity(0.04))
    }

    private func submitComposer() {
        guard !appModel.isPlanningAgentRun else {
            return
        }

        appModel.generateAgentPlan()
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.22)) {
                proxy.scrollTo(timelineBottomID, anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private var statusMessages: some View {
        if let error = appModel.agentErrorMessage {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(1)
        }
        if let message = appModel.agentStatusMessage {
            Label(message, systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct AgentThreadRenameSheet: View {
    @EnvironmentObject private var appModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename Thread")
                .font(.headline)

            TextField("Thread title", text: $appModel.agentThreadRenameDraft)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 320)

            HStack {
                Spacer()
                Button("Cancel") {
                    appModel.isShowingAgentThreadRename = false
                    dismiss()
                }
                Button("Rename") {
                    appModel.renamePendingAgentThreadFromDraft()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
    }
}

private struct AgentConversationTimelineView: View {
    let thread: AgentThread?
    let runs: [AgentRun]
    let currentRun: AgentRun?
    let events: [AgentSessionTimelineItem]
    let pendingPrompt: String?
    let streamingResponse: String?
    let isThinking: Bool
    let thinkingModeTitle: String

    private var visibleEvents: [AgentSessionTimelineItem] {
        events.filter { $0.kind != .hookResult }
    }

    private var visibleRuns: [AgentRun] {
        if let currentRun, !runs.contains(where: { $0.id == currentRun.id }) {
            return [currentRun] + Array(runs.prefix(4))
        }

        return Array(runs.prefix(5))
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("对话时间线")
                    .font(.headline)
                if let thread {
                    Text(thread.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            if visibleEvents.isEmpty, visibleRuns.isEmpty, pendingPrompt == nil, !isThinking {
                ContentUnavailableView(
                    "还没有消息",
                    systemImage: "bubble.left.and.text.bubble.right",
                    description: Text("从下方输入框开始。")
                )
                .frame(maxWidth: .infinity, minHeight: 260)
            } else if !visibleEvents.isEmpty {
                ForEach(visibleEvents) { item in
                    AgentSessionEventRowView(item: item)
                }
            } else {
                ForEach(visibleRuns, id: \.id) { run in
                    AgentConversationRunCard(run: run, isCurrent: currentRun?.id == run.id)
                }
            }

            if let pendingPrompt {
                AgentTurnBubbleView(
                    title: "你",
                    iconName: "person.crop.circle",
                    detail: pendingPrompt,
                    metadata: "发送中",
                    payloadPreview: nil,
                    isUser: true,
                    isError: false
                )
            }

            if let streamingResponse,
               !streamingResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                AgentTurnBubbleView(
                    title: "AI",
                    iconName: "sparkles",
                    detail: streamingResponse,
                    metadata: isThinking ? "正在生成" : "已停止",
                    payloadPreview: nil,
                    isUser: false,
                    isError: false
                )
            } else if isThinking {
                AgentThinkingBubbleView(thinkingModeTitle: thinkingModeTitle)
            }
        }
    }
}

private struct AgentThinkingBubbleView: View {
    let thinkingModeTitle: String

    private let messages = [
        "正在读取所选论文和项目上下文",
        "正在整理多轮对话线索",
        "正在组织回答与可执行边界"
    ]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.8)) { context in
            let tick = Int(context.date.timeIntervalSinceReferenceDate / 0.8)
            let message = messages[tick % messages.count]
            let dots = String(repeating: ".", count: (tick % 3) + 1)
            AgentTurnBubbleView(
                title: "AI",
                iconName: "sparkles",
                detail: message + dots,
                metadata: thinkingModeTitle,
                payloadPreview: nil,
                isUser: false,
                isError: false
            )
        }
    }
}

private struct AgentSessionEventRowView: View {
    let item: AgentSessionTimelineItem

    @ViewBuilder
    var body: some View {
        switch item.kind {
        case .userMessage:
            AgentTurnBubbleView(
                title: item.title,
                iconName: iconName,
                detail: item.detail,
                metadata: item.createdAt.formatted(date: .abbreviated, time: .shortened),
                payloadPreview: item.payloadPreview,
                isUser: true,
                isError: false
            )
        case .assistantMessage:
            AgentTurnBubbleView(
                title: item.title,
                iconName: iconName,
                detail: item.detail,
                metadata: item.createdAt.formatted(date: .abbreviated, time: .shortened),
                payloadPreview: item.payloadPreview,
                isUser: false,
                isError: false
            )
        case .reasoningSummary:
            AgentRuntimeEventRow(
                title: item.title,
                iconName: iconName,
                iconColor: iconColor,
                detail: item.detail,
                metadata: item.createdAt.formatted(date: .abbreviated, time: .shortened),
                payloadPreview: item.payloadPreview,
                isError: false
            )
        default:
            AgentRuntimeEventRow(
                title: item.title,
                iconName: iconName,
                iconColor: iconColor,
                detail: item.detail,
                metadata: item.createdAt.formatted(date: .abbreviated, time: .shortened),
                payloadPreview: item.payloadPreview,
                isError: item.kind == .toolCallFailed
            )
        }
    }

    private var iconName: String {
        switch item.kind {
        case .userMessage:
            return "person.crop.circle"
        case .assistantMessage:
            return "sparkles"
        case .reasoningSummary:
            return "brain.head.profile"
        case .permissionRequested:
            return "questionmark.shield"
        case .permissionResolved:
            return "checkmark.shield"
        case .toolCallStarted:
            return "play.circle"
        case .toolCallCompleted:
            return "checkmark.circle"
        case .toolCallFailed:
            return "exclamationmark.triangle"
        case .hookResult:
            return "link"
        case .compactionSummary:
            return "text.badge.checkmark"
        }
    }

    private var iconColor: Color {
        switch item.kind {
        case .toolCallFailed:
            return .red
        case .permissionRequested:
            return .orange
        case .permissionResolved, .toolCallCompleted:
            return .green
        case .hookResult:
            return .purple
        case .reasoningSummary:
            return .blue
        default:
            return .secondary
        }
    }
}

private struct AgentTurnBubbleView: View {
    let title: String
    let iconName: String
    let detail: String
    let metadata: String
    let payloadPreview: String?
    let isUser: Bool
    let isError: Bool

    private var alignment: HorizontalAlignment {
        isUser ? .trailing : .leading
    }

    private var bubbleColor: Color {
        if isError {
            return Color.red.opacity(0.10)
        }
        return isUser ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.08)
    }

    private var bubbleWidth: CGFloat {
        if isUser {
            let text = [detail, payloadPreview ?? ""].joined(separator: "\n")
            let longestLine = text.split(separator: "\n", omittingEmptySubsequences: false).map(\.count).max() ?? text.count
            let estimated = CGFloat(min(max(longestLine, 12), 60)) * 7.6 + 42
            return min(max(estimated, 140), 480)
        }
        return 640
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if isUser {
                Spacer(minLength: 72)
            }

            VStack(alignment: alignment, spacing: 5) {
                Label(title, systemImage: iconName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)

                VStack(alignment: alignment, spacing: 6) {
                    AgentMarkdownBubbleText(markdown: detail, isError: isError)

                    if let payloadPreview {
                        Text(payloadPreview)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(5)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(width: bubbleWidth, alignment: isUser ? .trailing : .leading)
                .background(bubbleColor, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(isUser ? 0.08 : 0.12))
                }

                Text(metadata)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !isUser {
                Spacer(minLength: 72)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }
}

private struct AgentMarkdownBubbleText: View {
    @EnvironmentObject private var appModel: AppViewModel

    let markdown: String
    let isError: Bool

    var body: some View {
        let fontSize = appModel.workspacePreferences.agentChatFontSize
        if ChatMarkdownResources.isAvailable {
            ChatMarkdownWebView(markdown: markdown, fontSize: fontSize, isError: isError)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            AgentMarkdownLegacyText(markdown: markdown, fontSize: fontSize, isError: isError)
        }
    }
}

private struct AgentMarkdownLegacyText: View {
    let markdown: String
    let fontSize: Double
    let isError: Bool

    private var attributedText: AttributedString? {
        try? AttributedString(markdown: markdown)
    }

    var body: some View {
        Group {
            if let attributedText {
                Text(attributedText)
            } else {
                Text(markdown)
            }
        }
        .font(.system(size: CGFloat(fontSize)))
        .foregroundStyle(isError ? .red : .primary)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct AgentRuntimeEventRow: View {
    @EnvironmentObject private var appModel: AppViewModel

    let title: String
    let iconName: String
    let iconColor: Color
    let detail: String
    let metadata: String
    let payloadPreview: String?
    let isError: Bool

    @State private var isExpanded = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(metadata)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(isError ? .red : .secondary)
                    .textSelection(.enabled)

                if let payloadPreview {
                    DisclosureGroup(isExpanded: $isExpanded) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(payloadPreview)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))

                            if let artifact = AgentArtifactDraftPreview(payloadPreview), !artifact.evidenceRefs.isEmpty {
                                AgentEvidenceRefListView(evidenceRefs: artifact.evidenceRefs)
                            }
                        }
                    } label: {
                        Label(isExpanded ? "隐藏详情" : "查看详情", systemImage: "curlybraces")
                            .font(.caption)
                    }
                    .tint(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct AgentEvidenceRefListView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let evidenceRefs: [AgentEvidenceRef]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Evidence")
                .font(.caption.weight(.semibold))
            ForEach(evidenceRefs) { evidence in
                evidenceRow(evidence)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func evidenceRow(_ evidence: AgentEvidenceRef) -> some View {
        let jump = appModel.currentResearchRoot.map { evidence.sourceJump(in: $0) }
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: iconName(for: jump?.status))
                .foregroundStyle(color(for: jump?.status))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(evidence.relativePath ?? "Missing source")
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(evidenceLineSummary(evidence, jump: jump))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let warning = jump?.warning {
                    Text(warning)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
            Button {
                if let url = jump?.sourceURL {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            } label: {
                Label("Open Source", systemImage: "arrow.up.right.square")
                    .labelStyle(.iconOnly)
            }
            .disabled(jump?.sourceURL == nil)
            .help("Open source file")
        }
        .padding(7)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
    }

    private func evidenceLineSummary(_ evidence: AgentEvidenceRef, jump: AgentEvidenceSourceJump?) -> String {
        let lineText: String
        if let start = jump?.startLine, let end = jump?.endLine {
            lineText = "lines \(start)-\(end)"
        } else {
            lineText = "line range unavailable"
        }
        let confidence = evidence.confidence.map { String(format: "%.2f", $0) }
        return [lineText, evidence.heading, confidence.map { "confidence \($0)" }].compactMap { $0 }.joined(separator: " · ")
    }

    private func iconName(for status: AgentEvidenceSourceStatus?) -> String {
        switch status {
        case .available:
            return "link"
        case .stale:
            return "exclamationmark.triangle"
        case .missingSource, nil:
            return "questionmark.circle"
        }
    }

    private func color(for status: AgentEvidenceSourceStatus?) -> Color {
        switch status {
        case .available:
            return .green
        case .stale:
            return .orange
        case .missingSource, nil:
            return .secondary
        }
    }
}

private struct AgentArtifactDraftPreview: Decodable {
    var evidenceRefs: [AgentEvidenceRef]

    init?(_ rawJSON: String) {
        guard let data = rawJSON.data(using: .utf8), let decoded = try? AgentRunDirectoryStore.decoder().decode(Self.self, from: data) else {
            return nil
        }
        self = decoded
    }

    private enum CodingKeys: String, CodingKey {
        case evidenceRefs = "evidence_refs"
    }
}

private struct AgentConversationRunCard: View {
    let run: AgentRun
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AgentTurnBubbleView(
                title: "You",
                iconName: "person.crop.circle",
                detail: run.goal,
                metadata: run.createdAt.formatted(date: .abbreviated, time: .shortened),
                payloadPreview: nil,
                isUser: true,
                isError: false
            )

            AgentTurnBubbleView(
                title: isCurrent ? "Agent / Current" : "Agent",
                iconName: "sparkles",
                detail: run.plan.finalResponseDraft?.nilIfEmpty ?? "\(run.plan.title?.nilIfEmpty ?? "Plan")\n\n\(run.plan.summary)",
                metadata: run.mode.rawValue,
                payloadPreview: nil,
                isUser: false,
                isError: false
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AgentPlatformStatusView: View {
    @EnvironmentObject private var appModel: AppViewModel

    var body: some View {
        GroupBox("Agent Platform") {
            VStack(alignment: .leading, spacing: 10) {
                WorkspacePathRow(label: "Core", value: appModel.agentPlatformSummary)
                WorkspacePathRow(label: "Runtime", value: appModel.agentRuntimeSelectionSummary)
                WorkspacePathRow(label: "Effective", value: appModel.agentRuntimeEffectiveSummary)
                WorkspacePathRow(label: "Health", value: appModel.agentSidecarHealthSummary)
                WorkspacePathRow(label: "Fallback", value: appModel.agentRuntimeFallbackSummary)
                WorkspacePathRow(label: "Provider", value: appModel.agentProviderSummary)
                WorkspacePathRow(label: "Provider V2", value: appModel.agentProviderV2Summary)
                WorkspacePathRow(label: "Presets", value: appModel.agentPresetSummary)
                WorkspacePathRow(label: "Permissions", value: appModel.agentPermissionSummary)
                WorkspacePathRow(label: "Hooks", value: appModel.agentHookSummary)
                WorkspacePathRow(label: "MCP", value: appModel.agentMCPStatusSummary)
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
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }
}

private struct AgentContextSummaryView: View {
    let snapshot: AgentWorkspaceSnapshot?
    let tools: [AgentToolDefinition]

    var body: some View {
        GroupBox("Current Context") {
            VStack(alignment: .leading, spacing: 10) {
                WorkspacePathRow(label: "Root", value: snapshot?.rootName ?? "-")
                WorkspacePathRow(label: "Current Project", value: snapshot?.currentProject?.name ?? "None")
                WorkspacePathRow(label: "Project Papers", value: "\(snapshot?.projectPapers.count ?? 0)")
                WorkspacePathRow(label: "Project Open Todos", value: "\(snapshot?.projectOpenTodos.count ?? 0)")
                WorkspacePathRow(label: "Available Tools", value: tools.map(\.name).joined(separator: ", ").nilIfEmpty ?? "-")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }
}

private struct AgentPlanSummaryView: View {
    let run: AgentRun

    var body: some View {
        GroupBox("Plan") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(run.plan.title?.nilIfEmpty ?? "Plan Only")
                        .font(.headline)
                    Text(run.plan.summary)
                        .foregroundStyle(.secondary)
                }

                if let risk = run.plan.risk?.nilIfEmpty {
                    Label(risk, systemImage: "exclamationmark.shield")
                        .foregroundStyle(.secondary)
                }

                if !run.plan.steps.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Steps")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        ForEach(Array(run.plan.steps.enumerated()), id: \.offset) { index, step in
                            Text("\(index + 1). \(step)")
                        }
                    }
                }

                if let finalResponse = run.plan.finalResponseDraft?.nilIfEmpty {
                    Text(finalResponse)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }
}

private struct AgentPermissionDockView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let run: AgentRun

    var body: some View {
        let items = appModel.agentPermissionDockItems(for: run)

        VStack(spacing: 0) {
            AILabDockShell {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Label("Permission Dock", systemImage: "questionmark.shield")
                            .font(.headline)
                        Text("\(items.count) tool calls")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }

                    ForEach(items) { item in
                        AgentPermissionDockRow(item: item)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            AILabDockTray(attachTop: true) {
                HStack(spacing: 8) {
                    Label("Ready to execute", systemImage: "checkmark.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button {
                        appModel.executeApprovedAgentTools()
                    } label: {
                        Label(appModel.isExecutingAgentTools ? "Running" : "Run Approved Tools", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(run.plan.toolCalls.isEmpty || appModel.isPlanningAgentRun || appModel.isExecutingAgentTools)
                }
                .padding(.horizontal, 10)
                .padding(.top, 18)
                .padding(.bottom, 8)
            }
        }
    }
}

private struct AgentPermissionDockRow: View {
    @EnvironmentObject private var appModel: AppViewModel

    let item: AgentPermissionDockItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                permissionStateLabel

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.displayName)
                        .font(.headline)
                    Text(item.summary)
                        .foregroundStyle(.secondary)
                    Text("\(item.permissionKey) / \(item.risk.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(item.matchedPolicyDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(item.argumentsPreview)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            if !item.pathPreview.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Path Preview")
                        .font(.caption)
                        .fontWeight(.semibold)
                    ForEach(item.pathPreview, id: \.self) { path in
                        Text(path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding(.leading, 22)
            }

            HStack(spacing: 8) {
                Button {
                    appModel.setAgentToolApproval(callID: item.id, isApproved: true)
                } label: {
                    Label("Allow Once", systemImage: "checkmark.shield")
                }
                .controlSize(.small)
                .disabled(item.approvalState == .completed || item.approvalState == .deniedByPolicy)

                Button(role: .destructive) {
                    appModel.setAgentToolDenied(callID: item.id, isDenied: true)
                } label: {
                    Label("Deny", systemImage: "xmark.octagon")
                }
                .controlSize(.small)
                .disabled(item.approvalState == .completed)

                Toggle(
                    "Session Draft",
                    isOn: Binding(
                        get: { appModel.agentToolSessionApprovalDrafts.contains(item.id) },
                        set: { appModel.setAgentSessionApprovalDraft(callID: item.id, isEnabled: $0) }
                    )
                )
                .toggleStyle(.checkbox)
                .controlSize(.small)

                Spacer(minLength: 0)
            }

            TextField(
                "Correction feedback",
                text: Binding(
                    get: { appModel.agentCorrectionFeedback(callID: item.id) },
                    set: { appModel.updateAgentCorrectionFeedback(callID: item.id, text: $0) }
                )
            )
            .textFieldStyle(.roundedBorder)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var permissionStateLabel: some View {
        Label(stateTitle, systemImage: stateIcon)
            .font(.caption)
            .foregroundStyle(stateColor)
            .frame(minWidth: 120, alignment: .leading)
    }

    private var stateTitle: String {
        switch item.approvalState {
        case .autoAllowed:
            return "Auto-allow"
        case .waitingForApproval:
            return "Needs approval"
        case .allowedOnce:
            return "Allow once"
        case .denied:
            return "Denied"
        case .deniedByPolicy:
            return "Policy deny"
        case .sessionApprovalDraft:
            return "Session draft"
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        }
    }

    private var stateIcon: String {
        switch item.approvalState {
        case .autoAllowed, .allowedOnce, .completed:
            return "checkmark.circle"
        case .waitingForApproval, .sessionApprovalDraft:
            return "questionmark.circle"
        case .denied, .deniedByPolicy, .failed:
            return "exclamationmark.triangle"
        }
    }

    private var stateColor: Color {
        switch item.approvalState {
        case .autoAllowed, .allowedOnce, .completed:
            return .green
        case .waitingForApproval, .sessionApprovalDraft:
            return .orange
        case .denied, .deniedByPolicy, .failed:
            return .red
        }
    }
}

struct AgentHookActivityView: View {
    @EnvironmentObject private var appModel: AppViewModel
    @State private var selectedHookResult: AgentHookActivityItem?

    var body: some View {
        GroupBox("Hook Activity") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Enabled Hooks")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    ForEach(appModel.agentHookActivitySummary.hooks) { hook in
                        HStack(alignment: .top, spacing: 8) {
                            Toggle(
                                isOn: Binding(
                                    get: { hook.isEnabled && !appModel.agentDisabledHookIDs.contains(hook.id) },
                                    set: { appModel.setAgentHook(hook.id, isEnabled: $0) }
                                )
                            ) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(hook.eventName.rawValue) / \(hook.id)")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                    Text(hook.message ?? hook.additionalContext ?? hook.matcher ?? "No hook message configured.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent Results")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    if appModel.agentHookActivitySummary.results.isEmpty {
                        Text("No hook results recorded for the current timeline yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(appModel.agentHookActivitySummary.results) { result in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(result.eventName?.rawValue ?? "Hook")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                    if let decision = result.permissionDecision {
                                        Text(decision.rawValue)
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.secondary.opacity(0.12), in: Capsule())
                                    }
                                    Spacer(minLength: 0)
                                    Text(result.createdAt.formatted(date: .omitted, time: .shortened))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Text(result.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .textSelection(.enabled)
                                HStack(spacing: 8) {
                                    if result.additionalContext != nil {
                                        Label("含完整上下文", systemImage: "text.badge.plus")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    Button {
                                        selectedHookResult = result
                                    } label: {
                                        Label("查看", systemImage: "eye")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                            .padding(8)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
        .sheet(item: $selectedHookResult) { result in
            AgentHookResultDetailSheet(result: result)
        }
    }
}

private struct AgentHookResultDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let result: AgentHookActivityItem

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.eventName?.rawValue ?? "Hook Result")
                        .font(.headline)
                    Text(result.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button("完成") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    detailBlock(title: "Summary", value: result.summary)
                    if let additionalContext = result.additionalContext {
                        detailBlock(title: "Additional Context", value: additionalContext)
                    }
                    if let permissionDecision = result.permissionDecision {
                        WorkspacePathRow(label: "Permission", value: permissionDecision.rawValue)
                    }
                    if let hookID = result.hookID {
                        WorkspacePathRow(label: "Hook ID", value: hookID)
                    }
                    WorkspacePathRow(label: "Session", value: result.sessionID)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 420)
    }

    private func detailBlock(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct AgentMCPServerStatusView: View {
    @EnvironmentObject private var appModel: AppViewModel

    var body: some View {
        GroupBox("MCP Server Status") {
            VStack(alignment: .leading, spacing: 12) {
                WorkspacePathRow(label: "Product Templates", value: ".sci-ai/sci-station/ tracked, no raw secrets")
                WorkspacePathRow(label: "Local Config", value: ".sci-ai/workspace.local/ local-only, ignored by git")
                WorkspacePathRow(label: "Local Gateway", value: "Swift ToolHost exposes tools/list and tools/call; write calls return approval_required")

                statusSection(title: "Product Preset", statuses: appModel.agentProductMCPServerStatuses, emptyText: "No product MCP template is available in this root.")
                statusSection(title: "Local Workspace", statuses: appModel.agentLocalMCPServerStatuses, emptyText: "No local workspace MCP config is present.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private func statusSection(title: String, statuses: [AgentMCPServerStatus], emptyText: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            if statuses.isEmpty {
                Text(emptyText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(statuses) { status in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Label(status.displayName, systemImage: status.isEnabled ? "checkmark.circle" : "pause.circle")
                                .foregroundStyle(status.isEnabled ? .green : .secondary)
                            Spacer(minLength: 0)
                            Text(status.source.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        WorkspacePathRow(label: "Endpoint", value: status.endpointSummary)
                        WorkspacePathRow(label: "Allowed Tools", value: status.allowedTools.joined(separator: ", ").nilIfEmpty ?? "not restricted")
                        WorkspacePathRow(label: "Timeout", value: "\(Int(status.timeoutSeconds))s")
                        WorkspacePathRow(label: "Credential Refs", value: "\(status.credentialReferenceCount)")
                        WorkspacePathRow(label: "Permission Layer", value: status.sideEffectsRequirePermission ? "side-effect tools require approval" : "read-only only")
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}

private struct AgentPresetManagerView: View {
    @EnvironmentObject private var appModel: AppViewModel

    var body: some View {
        GroupBox("Preset Manager") {
            VStack(alignment: .leading, spacing: 12) {
                if let preset = appModel.agentPresetDetails {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(preset.name) \(preset.version)")
                            .font(.headline)
                        Text(preset.description)
                            .foregroundStyle(.secondary)
                        WorkspacePathRow(label: "Manifest", value: preset.manifestRelativePath)
                    }

                    presetList(title: "Commands", values: preset.commands.map { "\($0.slashCommand) - \($0.title)" })
                    presetList(title: "Skills", values: preset.skills.map { "\($0.id) - \($0.description)" })
                    presetList(title: "Hooks", values: preset.hooks.map { "\($0.eventName.rawValue) - \($0.id)" })
                    presetList(title: "MCP Servers", values: preset.mcpServers.map { "\($0.id) - \($0.endpointSummary)" })

                    if preset.validationIssues.isEmpty {
                        Label("Validation passed", systemImage: "checkmark.seal")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        presetList(title: "Validation Issues", values: preset.validationIssues.map { "\($0.field): \($0.message)" })
                    }
                } else {
                    Text("No tracked research-core preset was found for the current root.")
                        .foregroundStyle(.secondary)
                }

                Text("Local overrides stay in .sci-ai/workspace.local/ or non-sensitive .sci-station/agent/ state.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private func presetList(title: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            if values.isEmpty {
                Text("None")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(values, id: \.self) { value in
                    Text(value)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

private struct AgentRunHistoryView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let currentRuns: [AgentRun]
    let orphanRuns: [AgentRun]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            historySection(title: "Current Thread Runs", runs: currentRuns, isOrphan: false)

            Divider()

            historySection(title: "Unthreaded Project Runs", runs: orphanRuns, isOrphan: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func historySection(title: String, runs: [AgentRun], isOrphan: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)

            if runs.isEmpty {
                Text(isOrphan ? "No unthreaded runs for this project." : "No runs in this thread yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(runs, id: \.id) { run in
                    historyRow(run, isOrphan: isOrphan)
                    Divider()
                }
            }
        }
    }

    private func historyRow(_ run: AgentRun, isOrphan: Bool) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(run.goal)
                    .font(.subheadline)
                    .lineLimit(1)
                Text("\(run.mode.rawValue) · \(status(for: run)) · \(run.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open") {
                appModel.openAgentRun(run)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Menu("More") {
                Button("Duplicate Prompt to New Chat") {
                    appModel.duplicateAgentRunPromptToNewChat(run)
                }

                if isOrphan {
                    Button("Create Thread from Run") {
                        appModel.createAgentThread(from: run)
                    }
                    Button("Add to Current Thread") {
                        appModel.addAgentRunToCurrentThread(run)
                    }
                }
            }
            .menuStyle(.button)
            .controlSize(.small)
        }
    }

    private func status(for run: AgentRun) -> String {
        guard run.mode == .executeApproved else {
            return "Plan only"
        }
        guard !run.toolResults.isEmpty else {
            return "No tools"
        }
        return run.toolResults.allSatisfy(\.succeeded) ? "Succeeded" : "Needs review"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
