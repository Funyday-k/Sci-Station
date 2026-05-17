import AppKit
import SwiftUI

struct ProjectOverviewView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace

    @State private var dashboardAggregator = ProjectDashboardAggregator()
    @State private var dashboardSnapshot: ProjectDashboardSnapshot?
    @State private var dashboardErrorMessage: String?
    @State private var projectMaterials: [WorkspaceMaterial] = []
    @State private var materialErrorMessage: String?
    @State private var isEditingBriefInline = false

    private let materialRepository = WorkspaceMaterialRepository()

    private var projectOverviewPath: String {
        projectWikiPath("projects/project_overview.md")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                projectWidgetBoard
            }
            .padding(24)
        }
        .task(id: appModel.currentProjectID ?? "__none__") {
            await refreshProjectWidgets(invalidating: true)
        }
        .onChange(of: appModel.papers) { _, _ in
            Task { await reloadDashboard(invalidating: true) }
        }
        .onChange(of: appModel.todos) { _, _ in
            Task { await reloadDashboard(invalidating: true) }
        }
        .onChange(of: appModel.markdownDocuments) { _, _ in
            Task { await reloadDashboard(invalidating: true) }
        }
        .onChange(of: appModel.agentRunHistory) { _, _ in
            Task { await reloadDashboard(invalidating: true) }
        }
        .onChange(of: appModel.agentCurrentRun) { _, _ in
            Task { await reloadDashboard(invalidating: true) }
        }
        .onChange(of: appModel.researchQueueScopes) { _, _ in
            Task { await reloadDashboard(invalidating: true) }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(appModel.currentResearchProject?.name ?? appModel.localized("未选择项目", "No Project Selected"))
                    .font(.largeTitle.weight(.semibold))
                    .lineLimit(1)
                Text(appModel.localized("项目驾驶舱", "Project Overview"))
                    .font(.title3.weight(.semibold))
                Text(appModel.localized(
                    "把 brief、研究问题、核心论文、任务、材料、gap 和近期活动放在同一个项目工作台。",
                    "Brief, questions, core papers, tasks, materials, gaps, and recent activity in one project cockpit."
                ))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button {
                Task { await refreshProjectWidgets(invalidating: true) }
            } label: {
                Label(appModel.localized("刷新", "Refresh"), systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .help(appModel.localized("刷新项目小组件", "Refresh project widgets"))
        }
    }

    private var projectWidgetBoard: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    projectStatusWidget
                        .frame(minWidth: 280, idealWidth: 320, maxWidth: 360)
                    projectBriefWidget
                        .frame(maxWidth: .infinity)
                }

                VStack(alignment: .leading, spacing: 14) {
                    projectStatusWidget
                    projectBriefWidget
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], alignment: .leading, spacing: 14) {
                researchQuestionsWidget
                corePapersWidget
                currentTasksWidget
                materialsWidget
                knowledgeGapsWidget
                recentActivityWidget
                projectDocumentsWidget
                workflowWidget
            }
        }
    }

    private var projectStatusWidget: some View {
        ProjectOverviewWidgetCard(
            title: appModel.localized("项目状态", "Project Status"),
            subtitle: appModel.localized("阶段、指标和下个 deadline。", "Stage, metrics, and the next deadline."),
            systemImage: "gauge.with.dots.needle.33percent",
            accent: .accentColor,
            minHeight: 220
        ) {
            if let dashboardErrorMessage {
                ProjectOverviewInlineMessage(
                    message: dashboardErrorMessage,
                    systemImage: "exclamationmark.triangle",
                    color: .orange
                )
            } else if let dashboardSnapshot {
                VStack(alignment: .leading, spacing: 14) {
                    StageBadge(stage: dashboardSnapshot.stage, rule: dashboardSnapshot.stageRule)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], alignment: .leading, spacing: 8) {
                        ProjectOverviewMetricPill(title: appModel.localized("论文", "Papers"), value: "\(projectPapers.count)", systemImage: "books.vertical")
                        ProjectOverviewMetricPill(title: appModel.localized("核心", "Core"), value: "\(corePapers.count)", systemImage: "star")
                        ProjectOverviewMetricPill(title: appModel.localized("文档", "Docs"), value: "\(projectDocuments.count)", systemImage: "doc.text")
                        ProjectOverviewMetricPill(title: appModel.localized("任务", "Open"), value: "\(openTodosCount)", systemImage: "checklist")
                    }

                    if let deadline = dashboardSnapshot.nextDeadline {
                        ProjectOverviewPlainRow(
                            title: deadline.title,
                            detail: deadline.dueDate.formatted(date: .abbreviated, time: .omitted),
                            systemImage: "calendar.badge.clock"
                        ) {
                            openProjectTab("tasks")
                        }
                    } else {
                        ProjectOverviewInlineMessage(
                            message: appModel.localized("没有即将到期的项目任务。", "No upcoming project tasks."),
                            systemImage: "calendar",
                            color: .secondary
                        )
                    }
                }
            } else {
                ProgressView(appModel.localized("正在加载项目状态...", "Loading project status..."))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var projectBriefWidget: some View {
        ProjectOverviewWidgetCard(
            title: appModel.localized("项目 Brief", "Project Brief"),
            subtitle: appModel.localized("可在概览页内快速编辑 living proposal。", "Inline-edit the living proposal from the overview."),
            systemImage: "doc.text",
            accent: .blue,
            minHeight: 260
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if let document = projectOverviewDocument {
                    if isEditingBriefInline, appModel.selectedMarkdownDraft?.relativePath == document.relativePath {
                        TextEditor(text: briefEditorBinding(for: document))
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 190)
                            .scrollContentBackground(.hidden)
                            .background(Color.secondary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                    } else {
                        MarkdownPreviewView(markdown: briefPreviewMarkdown(for: document), baseURL: document.fileURL.deletingLastPathComponent())
                            .frame(minHeight: 170, maxHeight: 240)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    ProjectOverviewInlineMessage(
                        message: appModel.localized("还没有载入项目 brief 文档。", "No project brief document has been loaded yet."),
                        systemImage: "doc.badge.plus",
                        color: .secondary
                    )
                }

                HStack(spacing: 8) {
                    Button {
                        beginBriefInlineEditing()
                    } label: {
                        Label(appModel.localized("内联编辑", "Edit Inline"), systemImage: "pencil")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(projectOverviewDocument == nil)

                    if isEditingBriefInline {
                        Button {
                            appModel.saveSelectedMarkdownChanges()
                            isEditingBriefInline = false
                        } label: {
                            Label(appModel.localized("保存", "Save"), systemImage: "checkmark")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(appModel.selectedMarkdownDraft?.relativePath != projectOverviewPath)

                        Button {
                            isEditingBriefInline = false
                        } label: {
                            Label(appModel.localized("收起", "Close"), systemImage: "xmark")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Button {
                        appModel.openMarkdownDocument(relativePath: projectOverviewPath)
                    } label: {
                        Label(appModel.localized("完整编辑器", "Full Editor"), systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var researchQuestionsWidget: some View {
        ProjectOverviewWidgetCard(
            title: appModel.localized("研究问题", "Research Questions"),
            subtitle: appModel.localized("从 Project Brief 中提取。", "Extracted from the project brief."),
            systemImage: "questionmark.bubble",
            accent: .teal,
            minHeight: 220
        ) {
            if researchQuestions.isEmpty {
                ProjectOverviewEmptyState(
                    message: appModel.localized("还没有写下研究问题。", "No research questions have been written yet."),
                    actionTitle: appModel.localized("编辑 Brief", "Edit Brief"),
                    systemImage: "pencil"
                ) {
                    beginBriefInlineEditing()
                }
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(Array(researchQuestions.prefix(5).enumerated()), id: \.offset) { _, question in
                        ProjectOverviewTextBullet(text: question, systemImage: "questionmark.circle")
                    }
                }
            }
        }
    }

    private var corePapersWidget: some View {
        ProjectOverviewWidgetCard(
            title: appModel.localized("核心论文", "Core Papers"),
            subtitle: appModel.localized("按核心标记、优先级和评分排序。", "Sorted by core mark, priority, and rating."),
            systemImage: "star",
            accent: .indigo,
            minHeight: 280
        ) {
            if corePapers.isEmpty {
                ProjectOverviewEmptyState(
                    message: appModel.localized("还没有核心论文。", "No core papers yet."),
                    actionTitle: appModel.localized("打开项目论文", "Open Project Papers"),
                    systemImage: "books.vertical"
                ) {
                    openProjectTab("papers")
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(corePapers.prefix(8)) { paper in
                        ProjectOverviewPaperRow(paper: paper, canRead: appModel.canOpenPDF(for: paper)) {
                            appModel.selectPaper(id: paper.id)
                            openProjectTab("papers")
                        } readAction: {
                            appModel.openPaperReader(paper)
                        }
                    }
                }
            }
        }
    }

    private var currentTasksWidget: some View {
        ProjectOverviewWidgetCard(
            title: appModel.localized("当前任务", "Current Tasks"),
            subtitle: appModel.localized("项目待办和核心论文阅读动作。", "Project todos and core-paper reading actions."),
            systemImage: "checklist",
            accent: .orange,
            minHeight: 280
        ) {
            VStack(alignment: .leading, spacing: 11) {
                if unreadCorePapersCount > 0 {
                    ProjectOverviewPlainRow(
                        title: appModel.localized("阅读 \(unreadCorePapersCount) 篇未读核心论文", "Read \(unreadCorePapersCount) unread core papers"),
                        detail: appModel.localized("从核心论文队列开始", "Start from the core paper queue"),
                        systemImage: "books.vertical"
                    ) {
                        openProjectTab("papers")
                    }
                }

                if currentProjectTodos.isEmpty {
                    ProjectOverviewEmptyState(
                        message: unreadCorePapersCount > 0
                            ? appModel.localized("没有显式项目待办。", "No explicit project todos.")
                            : appModel.localized("没有打开中的项目任务。", "No open project tasks."),
                        actionTitle: appModel.localized("打开任务", "Open Tasks"),
                        systemImage: "arrow.up.right"
                    ) {
                        openProjectTab("tasks")
                    }
                } else {
                    ForEach(currentProjectTodos.prefix(5)) { todo in
                        ProjectOverviewTodoRow(todo: todo) {
                            appModel.toggleTodo(todo)
                        }
                    }

                    Button {
                        openProjectTab("tasks")
                    } label: {
                        Label(appModel.localized("查看全部任务", "View All Tasks"), systemImage: "arrow.right")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var materialsWidget: some View {
        ProjectOverviewWidgetCard(
            title: appModel.localized("材料", "Materials"),
            subtitle: appModel.localized("近期 data、code、figures 和 outputs。", "Recent data, code, figures, and outputs."),
            systemImage: "shippingbox",
            accent: .green,
            minHeight: 280
        ) {
            if let materialErrorMessage {
                ProjectOverviewInlineMessage(message: materialErrorMessage, systemImage: "exclamationmark.triangle", color: .orange)
            } else if recentMaterials.isEmpty {
                ProjectOverviewEmptyState(
                    message: appModel.localized("这个项目还没有材料文件。", "This project has no material files yet."),
                    actionTitle: appModel.localized("打开材料", "Open Materials"),
                    systemImage: "shippingbox"
                ) {
                    openProjectTab("materials")
                }
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(recentMaterials.prefix(5)) { material in
                        ProjectOverviewMaterialRow(material: material) {
                            appModel.openWorkspaceRelativePath(material.relativePath)
                        }
                    }

                    Button {
                        openProjectTab("materials")
                    } label: {
                        Label(appModel.localized("查看材料库", "View Materials"), systemImage: "arrow.right")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var knowledgeGapsWidget: some View {
        ProjectOverviewWidgetCard(
            title: appModel.localized("知识缺口", "Knowledge Gaps"),
            subtitle: appModel.localized("来自 wiki/gaps 和项目上下文。", "From wiki/gaps and project context."),
            systemImage: "scope",
            accent: .purple,
            minHeight: 240
        ) {
            let gaps = dashboardSnapshot?.openGaps ?? []
            if gaps.isEmpty {
                ProjectOverviewEmptyState(
                    message: appModel.localized("还没有登记 research gap。", "No research gaps are registered."),
                    actionTitle: appModel.localized("打开 Wiki", "Open Wiki"),
                    systemImage: "doc.text"
                ) {
                    openProjectTab("wiki")
                }
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(gaps.prefix(5)) { gap in
                        ProjectOverviewPlainRow(title: gap.title, detail: gap.relativePath ?? "wiki/gaps", systemImage: "questionmark.bubble") {
                            if let relativePath = gap.relativePath {
                                appModel.openMarkdownDocument(relativePath: relativePath)
                            } else {
                                openProjectTab("wiki")
                            }
                        }
                    }
                }
            }
        }
    }

    private var recentActivityWidget: some View {
        ProjectOverviewWidgetCard(
            title: appModel.localized("近期活动", "Recent Activity"),
            subtitle: appModel.localized("论文、材料和 AI artifact 的最新信号。", "Latest signals from papers, materials, and AI artifacts."),
            systemImage: "clock.arrow.circlepath",
            accent: .red,
            minHeight: 280
        ) {
            if recentActivityItems.isEmpty {
                ProjectOverviewInlineMessage(
                    message: appModel.localized("还没有可显示的项目活动。", "No project activity to show yet."),
                    systemImage: "clock",
                    color: .secondary
                )
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(recentActivityItems) { item in
                        ProjectOverviewActivityRow(item: item) {
                            performActivityAction(item.action)
                        }
                    }
                }
            }
        }
    }

    private var projectDocumentsWidget: some View {
        ProjectOverviewWidgetCard(
            title: appModel.localized("项目文档", "Project Docs"),
            subtitle: appModel.localized("项目 wiki/projects 下的 Markdown。", "Markdown under the project wiki/projects folder."),
            systemImage: "doc.on.doc",
            accent: .cyan,
            minHeight: 240
        ) {
            if projectDocuments.isEmpty {
                ProjectOverviewEmptyState(
                    message: appModel.localized("还没有项目文档。", "No project documents yet."),
                    actionTitle: appModel.localized("打开 Brief", "Open Brief"),
                    systemImage: "doc.text"
                ) {
                    appModel.openMarkdownDocument(relativePath: projectOverviewPath)
                }
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(projectDocuments.prefix(6)) { document in
                        ProjectOverviewPlainRow(
                            title: document.title,
                            detail: document.relativePath,
                            systemImage: document.relativePath == projectOverviewPath ? "doc.text" : "doc.plaintext"
                        ) {
                            appModel.openMarkdownDocument(relativePath: document.relativePath)
                        }
                    }
                }
            }
        }
    }

    private var workflowWidget: some View {
        ProjectOverviewWidgetCard(
            title: appModel.localized("工作流", "Workflow"),
            subtitle: appModel.localized("把项目内容快速切到行动入口。", "Jump from project context to action surfaces."),
            systemImage: "square.grid.2x2",
            accent: .yellow,
            minHeight: 260
        ) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], alignment: .leading, spacing: 8) {
                ProjectOverviewShortcutButton(title: appModel.localized("Brief", "Brief"), systemImage: "doc.text") {
                    appModel.openMarkdownDocument(relativePath: projectOverviewPath)
                }
                ProjectOverviewShortcutButton(title: appModel.localized("论文", "Papers"), systemImage: "books.vertical") {
                    openProjectTab("papers")
                }
                ProjectOverviewShortcutButton(title: appModel.localized("Wiki", "Wiki"), systemImage: "text.book.closed") {
                    openProjectTab("wiki")
                }
                ProjectOverviewShortcutButton(title: appModel.localized("任务", "Tasks"), systemImage: "checklist") {
                    openProjectTab("tasks")
                }
                ProjectOverviewShortcutButton(title: appModel.localized("材料", "Materials"), systemImage: "shippingbox") {
                    openProjectTab("materials")
                }
                ProjectOverviewShortcutButton(title: appModel.localized("AI Lab", "AI Lab"), systemImage: "brain") {
                    openProjectTab("ai-drafts")
                }
                ProjectOverviewShortcutButton(title: appModel.localized("PDF", "PDF"), systemImage: "doc.viewfinder") {
                    openProjectTab("pdf-reader")
                }
                ProjectOverviewShortcutButton(title: appModel.localized("共享上下文", "Shared"), systemImage: "square.stack.3d.up") {
                    NSWorkspace.shared.open(projectSharedResearchURL)
                }
            }
        }
    }

    @MainActor
    private func refreshProjectWidgets(invalidating: Bool) async {
        await reloadDashboard(invalidating: invalidating)
        await reloadMaterials()
    }

    @MainActor
    private func reloadDashboard(invalidating: Bool) async {
        if invalidating {
            await dashboardAggregator.invalidate(reason: "project_overview_widget_change")
        }

        do {
            let input = ProjectDashboardAggregationInput(
                workspaceID: workspace.id.path,
                project: appModel.currentResearchProject,
                papers: appModel.papers,
                todos: appModel.todos,
                markdownDocuments: appModel.markdownDocuments,
                agentRuns: agentRunsForAggregation,
                unsupportedClaims: unsupportedClaimsForAggregation,
                queueEntries: Array(appModel.researchQueueScopes.values.joined())
            )
            dashboardSnapshot = try await dashboardAggregator.snapshot(input: input)
            dashboardErrorMessage = nil
        } catch {
            dashboardSnapshot = nil
            dashboardErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func reloadMaterials() async {
        do {
            projectMaterials = try await materialRepository.loadMaterials(in: workspace, project: appModel.currentResearchProject)
            materialErrorMessage = nil
        } catch {
            projectMaterials = []
            materialErrorMessage = error.localizedDescription
        }
    }

    private func beginBriefInlineEditing() {
        guard let document = projectOverviewDocument else {
            appModel.openMarkdownDocument(relativePath: projectOverviewPath)
            return
        }

        if appModel.selectedMarkdownDraft?.relativePath != document.relativePath {
            guard !appModel.selectedMarkdownHasUnsavedChanges else {
                appModel.selectMarkdownDocument(id: document.id)
                return
            }
            appModel.selectMarkdownDocument(id: document.id)
        }

        isEditingBriefInline = appModel.selectedMarkdownDraft?.relativePath == document.relativePath
    }

    private func briefEditorBinding(for document: MarkdownDocument) -> Binding<String> {
        Binding(
            get: {
                appModel.selectedMarkdownDraft?.relativePath == document.relativePath
                    ? appModel.selectedMarkdownDraft?.rawContents ?? document.rawContents
                    : document.rawContents
            },
            set: { newValue in
                guard appModel.selectedMarkdownDraft?.relativePath == document.relativePath else {
                    return
                }
                appModel.updateSelectedMarkdownContents(newValue)
            }
        )
    }

    private func briefPreviewMarkdown(for document: MarkdownDocument) -> String {
        let trimmed = document.rawContents.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? appModel.localized("_这个项目 brief 还是空的。_", "_This project brief is still empty._") : trimmed
    }

    private func openProjectTab(_ tabID: String) {
        if let projectID = appModel.currentProjectID {
            appModel.focusResearchProject(projectID)
        }
        appModel.selectProjectSpaceTab(tabID)
    }

    private func performActivityAction(_ action: ProjectOverviewActivityAction) {
        switch action {
        case let .paper(paperID):
            appModel.selectPaper(id: paperID)
            openProjectTab("papers")
        case let .material(relativePath):
            appModel.openWorkspaceRelativePath(relativePath)
        case let .artifact(targetPath):
            if let targetPath {
                appModel.openWorkspaceRelativePath(targetPath)
            } else {
                openProjectTab("ai-drafts")
            }
        }
    }

    private var agentRunsForAggregation: [AgentRun] {
        guard let currentRun = appModel.agentCurrentRun else {
            return appModel.agentRunHistory
        }
        if appModel.agentRunHistory.contains(where: { $0.id == currentRun.id }) {
            return appModel.agentRunHistory
        }
        return [currentRun] + appModel.agentRunHistory
    }

    private var unsupportedClaimsForAggregation: [ClaimSummary] {
        let input = HomeAggregationInput(
            workspaceID: workspace.id.path,
            currentProjectID: appModel.currentProjectID,
            projects: appModel.researchProjects,
            papers: appModel.papers,
            todos: appModel.todos,
            markdownDocuments: appModel.markdownDocuments,
            agentRuns: agentRunsForAggregation,
            sessionEvents: appModel.agentSessionEvents,
            retrievalIndexStatus: appModel.agentRetrievalIndexStatus,
            moduleConfiguration: appModel.workspaceModuleConfiguration
        )
        return (try? HomeSnapshotBuilder().build(input: input).aiReview.unsupportedClaims) ?? []
    }

    private var projectOverviewDocument: MarkdownDocument? {
        appModel.markdownDocuments.first { $0.relativePath == projectOverviewPath }
    }

    private var researchQuestions: [String] {
        guard let document = projectOverviewDocument else {
            return []
        }

        let lines = markdownSectionLines(
            in: document.body,
            matching: ["research question", "research questions", "研究问题"]
        )
        return Array(lines.compactMap(cleanedMarkdownListText).prefix(6))
    }

    private var currentProjectTodos: [TodoItem] {
        guard let projectID = appModel.currentProjectID else {
            return []
        }

        return appModel.todos
            .filter { $0.projectIDs.contains(projectID) && $0.status != .done && $0.status != .cancelled }
            .sorted(by: projectTodoSort)
    }

    private var unreadCorePapersCount: Int {
        corePapers.filter { $0.status == .unread || $0.status == .skimmed }.count
    }

    private var recentMaterials: [WorkspaceMaterial] {
        projectMaterials.sorted { first, second in
            switch (first.modifiedAt, second.modifiedAt) {
            case let (firstDate?, secondDate?) where firstDate != secondDate:
                return firstDate > secondDate
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return first.relativePath.localizedStandardCompare(second.relativePath) == .orderedAscending
            }
        }
    }

    private var recentActivityItems: [ProjectOverviewActivityItem] {
        var items: [ProjectOverviewActivityItem] = []

        for artifact in dashboardSnapshot?.recentArtifacts ?? [] {
            items.append(ProjectOverviewActivityItem(
                id: "artifact-\(artifact.id)",
                title: artifact.title,
                detail: artifact.kind,
                date: artifact.savedAt,
                systemImage: artifact.status == "needs_review" ? "doc.badge.clock" : "sparkles",
                action: .artifact(artifact.targetPath)
            ))
        }

        for material in recentMaterials.prefix(6) {
            if let modifiedAt = material.modifiedAt {
                items.append(ProjectOverviewActivityItem(
                    id: "material-\(material.id)",
                    title: material.displayName,
                    detail: material.category.capitalized,
                    date: modifiedAt,
                    systemImage: ProjectOverviewMaterialRow.systemImage(for: material.kind),
                    action: .material(material.relativePath)
                ))
            }
        }

        for paper in projectPapers.sorted(by: { $0.updatedAt > $1.updatedAt }).prefix(6) {
            items.append(ProjectOverviewActivityItem(
                id: "paper-\(paper.id)",
                title: paper.displayTitle,
                detail: paper.updatedAt.formatted(date: .abbreviated, time: .omitted),
                date: paper.updatedAt,
                systemImage: "doc.richtext",
                action: .paper(paper.id)
            ))
        }

        return Array(items.sorted { first, second in
            if first.date == second.date {
                return first.title.localizedStandardCompare(second.title) == .orderedAscending
            }
            return first.date > second.date
        }.prefix(6))
    }

    private var projectDocuments: [MarkdownDocument] {
        appModel.markdownDocuments
            .filter { $0.relativePath.hasPrefix(projectWikiPath("projects/")) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private var projectSharedResearchURL: URL {
        if let project = appModel.currentResearchProject {
            return workspace.fileURL(for: project.relativePath + "/shared_research.md")
        }

        return workspace.sharedResearchURL
    }

    private func projectWikiPath(_ suffix: String) -> String {
        if let project = appModel.currentResearchProject {
            return project.relativePath + "/wiki/" + suffix
        }

        return "wiki/" + suffix
    }

    private var corePapers: [Paper] {
        let candidates = projectPapers.filter(isCorePaper)
        return Array(candidates.sorted(by: corePaperSort).prefix(6))
    }

    private var projectPapers: [Paper] {
        guard let projectID = appModel.currentProjectID else {
            return []
        }

        return appModel.papers(for: projectID)
    }

    private var openTodosCount: Int {
        guard let projectID = appModel.currentProjectID else {
            return 0
        }

        return appModel.todos.filter { $0.projectIDs.contains(projectID) && $0.status != .done && $0.status != .cancelled }.count
    }

    private func isCorePaper(_ paper: Paper) -> Bool {
        guard let projectID = appModel.currentProjectID else {
            return false
        }

        return paper.coreProjectIDs.contains(projectID)
    }

    private func corePaperSort(_ first: Paper, _ second: Paper) -> Bool {
        if let projectID = appModel.currentProjectID,
           appModel.projectPaperLinkSortPrecedes(first, second, projectID: projectID) {
            return true
        }
        if let projectID = appModel.currentProjectID,
           appModel.projectPaperLinkSortPrecedes(second, first, projectID: projectID) {
            return false
        }

        let firstScore = corePaperScore(first)
        let secondScore = corePaperScore(second)
        if firstScore == secondScore {
            return first.updatedAt > second.updatedAt
        }
        return firstScore > secondScore
    }

    private func corePaperScore(_ paper: Paper) -> Int {
        var score = 0
        if isCorePaper(paper) { score += 10 }
        if paper.priority == .urgent { score += 4 }
        if paper.priority == .high { score += 3 }
        score += paper.rating ?? 0
        return score
    }

    private func projectTodoSort(_ first: TodoItem, _ second: TodoItem) -> Bool {
        switch (first.dueDate, second.dueDate) {
        case let (firstDate?, secondDate?) where firstDate != secondDate:
            return firstDate < secondDate
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            let firstPriority = prioritySortValue(first.priority)
            let secondPriority = prioritySortValue(second.priority)
            if firstPriority == secondPriority {
                return first.updatedAt > second.updatedAt
            }
            return firstPriority < secondPriority
        }
    }

    private func prioritySortValue(_ priority: Priority) -> Int {
        switch priority {
        case .urgent: return 0
        case .high: return 1
        case .medium: return 2
        case .low: return 3
        }
    }

    private func markdownSectionLines(in markdown: String, matching headings: Set<String>) -> [String] {
        var isCollecting = false
        var collected: [String] = []

        for rawLine in markdown.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("#") {
                let heading = normalizedMarkdownHeading(trimmed)
                isCollecting = headings.contains { heading == $0 || heading.contains($0) }
                continue
            }

            if isCollecting {
                collected.append(rawLine)
            }
        }

        return collected
    }

    private func normalizedMarkdownHeading(_ line: String) -> String {
        String(line.drop(while: { $0 == "#" || $0.isWhitespace }))
            .trimmingCharacters(in: CharacterSet(charactersIn: " :："))
            .lowercased()
    }

    private func cleanedMarkdownListText(_ line: String) -> String? {
        var text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return nil
        }

        for prefix in ["- [ ] ", "- [x] ", "- [X] ", "- ", "* ", "+ "] where text.hasPrefix(prefix) {
            text.removeFirst(prefix.count)
            break
        }

        if let numberRange = text.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) {
            text.removeSubrange(numberRange)
        }

        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

}

private enum ProjectOverviewActivityAction {
    case paper(String)
    case material(String)
    case artifact(String?)
}

private struct ProjectOverviewActivityItem: Identifiable {
    let id: String
    let title: String
    let detail: String
    let date: Date
    let systemImage: String
    let action: ProjectOverviewActivityAction
}

private struct ProjectOverviewWidgetCard<Content: View>: View {
    @EnvironmentObject private var appModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    let title: String
    let subtitle: String
    let systemImage: String
    let accent: Color
    let minHeight: CGFloat
    let content: Content

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        accent: Color,
        minHeight: CGFloat,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.accent = accent
        self.minHeight = minHeight
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 30, height: 30)
                    .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            content
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .glassEffect(
            .regular.tint(appModel.liquidGlassTintColor.opacity(isHovering ? 0.04 : 0.025)),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color.white.opacity(0.10), Color.white.opacity(0.025)]
                            : [Color.white.opacity(0.18), Color.white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.6
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(accent.opacity(isHovering ? 0.20 : 0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(isHovering ? 0.07 : 0.04), radius: isHovering ? 12 : 8, x: 0, y: isHovering ? 6 : 4)
        .onHover { hovering in
            isHovering = hovering
        }
        .animation(.smooth(duration: 0.22), value: isHovering)
    }
}

private struct ProjectOverviewMetricPill: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ProjectOverviewInlineMessage: View {
    let message: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label {
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ProjectOverviewEmptyState: View {
    let message: String
    let actionTitle: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: action) {
                Label(actionTitle, systemImage: systemImage)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ProjectOverviewTextBullet: View {
    let text: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(Color.accentColor)
                .frame(width: 16)
                .padding(.top, 2)
            Text(text)
                .font(.callout)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

private struct ProjectOverviewPlainRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout.weight(.medium))
                        .lineLimit(2)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
}
private struct ProjectOverviewPaperRow: View {
    let paper: Paper
    let canRead: Bool
    let openAction: () -> Void
    let readAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: openAction) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(paper.displayTitle)
                        .font(.callout.weight(.medium))
                        .lineLimit(2)
                    Text(paper.authorsDisplay)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(paper.status.label)
                        Text(paper.priority.label)
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button(action: readAction) {
                Image(systemName: "doc.viewfinder")
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.borderless)
            .disabled(!canRead)
            .help(canRead ? "Open PDF Reader" : "No PDF attached")
        }
        .padding(.vertical, 2)
    }
}

private struct ProjectOverviewTodoRow: View {
    let todo: TodoItem
    let toggleAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Button(action: toggleAction) {
                Image(systemName: todo.status == .done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(todo.status == .done ? Color.green : Color.secondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.borderless)
            .help("Toggle task")

            VStack(alignment: .leading, spacing: 3) {
                Text(todo.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(todo.priority.label)
                        .foregroundStyle(priorityColor)
                    Text(todo.status.label)
                    if let dueDate = todo.dueDate {
                        Text(dueDate.formatted(date: .abbreviated, time: .omitted))
                    }
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private var priorityColor: Color {
        switch todo.priority {
        case .urgent: return .red
        case .high: return .orange
        case .medium: return .secondary
        case .low: return .secondary
        }
    }
}

private struct ProjectOverviewMaterialRow: View {
    let material: WorkspaceMaterial
    let action: () -> Void

    var body: some View {
        ProjectOverviewPlainRow(
            title: material.displayName,
            detail: material.relativePath,
            systemImage: Self.systemImage(for: material.kind),
            action: action
        )
    }

    static func systemImage(for kind: WorkspaceMaterialKind) -> String {
        switch kind {
        case .markdown: return "doc.richtext"
        case .python: return "chevron.left.forwardslash.chevron.right"
        case .text: return "doc.text"
        case .image: return "photo"
        case .pdf: return "doc.viewfinder"
        case .data: return "externaldrive"
        case .other: return "shippingbox"
        }
    }
}

private struct ProjectOverviewActivityRow: View {
    let item: ProjectOverviewActivityItem
    let action: () -> Void

    var body: some View {
        ProjectOverviewPlainRow(
            title: item.title,
            detail: item.detail + " - " + item.date.formatted(date: .abbreviated, time: .omitted),
            systemImage: item.systemImage,
            action: action
        )
    }
}

private struct ProjectOverviewShortcutButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 18)
                Text(title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
